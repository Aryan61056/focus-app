import SwiftUI
import Observation
import FamilyControls
import ManagedSettings
import DeviceActivity
import FocusLinkNet

/// Covers the apps and sites the person picked while a session is running, using Apple's Screen Time shield. This is the one
/// thing iOS lets an app do about other apps. Focus never learns which apps were picked: the picker hands back opaque tokens
/// that only the system can turn into names and icons.
@MainActor @Observable
final class DistractionBlocker {
    enum Access: Equatable {
        case notAsked, denied, allowed
        /// Screen Time could not be reached at all (no entitlement in this build, or a simulator).
        case unavailable(String)
    }

    private(set) var access: Access = .notAsked
    private(set) var asking = false
    /// True while the shield is actually up.
    private(set) var shielding = false

    var selection: FamilyActivitySelection {
        didSet { guard selection != oldValue else { return }; save(); reapply() }
    }
    var enabled: Bool {
        didSet { guard enabled != oldValue else { return }; defaults.set(enabled, forKey: Keys.enabled); reapply() }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var lastState = SessionState.idle
    @ObservationIgnored private var lastCanBlock = true
    @ObservationIgnored private var scheduledEnd: Date?

    private enum Keys { static let selection = "block.selection", enabled = "block.enabled" }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = defaults.data(forKey: Keys.selection).flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) } ?? FamilyActivitySelection()
        enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        refreshAccess()
        // A block from an earlier launch may still be up; the Block tab must be able to lift it.
        let s = FocusShield.store().shield
        shielding = s.applications != nil || s.applicationCategories != nil || s.webDomains != nil
    }

    var count: Int { selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count }
    var hasSelection: Bool { count > 0 }
    var isAuthorized: Bool { access == .allowed }

    // MARK: access
    func refreshAccess() {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved: access = .allowed
        case .denied: access = .denied
        case .notDetermined: if case .unavailable = access {} else { access = .notAsked }
        default:
            // iOS 26.4 added a second kind of yes (approvedWithDataAccess); it covers apps the same way.
            if #available(iOS 26.4, *), AuthorizationCenter.shared.authorizationStatus == .approvedWithDataAccess { access = .allowed } else { access = .notAsked }
        }
    }

    func requestAccess() async {
        guard !asking else { return }
        asking = true; defer { asking = false }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            refreshAccess()
        } catch {
            // Declined, cancelled, or not allowed in this build. Say which, so nobody wonders why a button did nothing.
            refreshAccess()
            if access != .allowed, access != .denied { access = .unavailable(Self.explain(error)) }
        }
        reapply()
    }

    private static func explain(_ error: Error) -> String {
        if let e = error as? FamilyControlsError {
            switch e {
            case .restricted, .invalidAccountType, .authorizationCanceled:
                return String(localized: "Screen Time access wasn't given. You can try again.")
            default: break   // including .unauthorized (iOS 26.4): this build has no Family Controls capability
            }
        }
        return String(localized: "Screen Time isn't available in this build of Focus. Blocking needs a build signed with the Family Controls capability.")
    }

    // MARK: blocking
    /// Called with every state the Mac sends. `canBlock` is false in demo mode: a pretend session must not cover real apps.
    func sync(_ state: SessionState, canBlock: Bool, now: Date = .now) {
        lastState = state; lastCanBlock = canBlock
        apply(now: now)
    }

    /// The person's own way out, always one tap away. It lifts the block until the next session starts.
    func unblockNow() {
        lastState = .idle
        apply()
    }

    private func reapply() { apply() }

    private func apply(now: Date = .now) {
        let want = BlockRules.shouldShield(lastState, enabled: enabled, hasSelection: hasSelection, authorized: isAuthorized, canBlock: lastCanBlock)
        if want {
            raise(now: now)
        } else if shielding || scheduledEnd != nil {
            lower()
        }
    }

    private func raise(now: Date) {
        let store = FocusShield.store()
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        // Sites inside a chosen category are covered too, so a blocked category cannot be reached through Safari.
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        shielding = true
        scheduleSafetyEnd(now: now)
    }

    private func lower() {
        FocusShield.store().clearAllSettings()
        DeviceActivityCenter().stopMonitoring([FocusShield.activityName])
        shielding = false; scheduledEnd = nil
    }

    /// iOS wakes the monitor extension at this time and it lifts the block, so the block ends even if the Mac is never heard from.
    private func scheduleSafetyEnd(now: Date) {
        let end = BlockRules.safetyEnd(for: lastState, now: now)
        if let scheduledEnd, abs(scheduledEnd.timeIntervalSince(end)) < 30 { return }
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let cal = Calendar.current
        let schedule = DeviceActivitySchedule(intervalStart: cal.dateComponents(parts, from: now), intervalEnd: cal.dateComponents(parts, from: end), repeats: false)
        do {
            try DeviceActivityCenter().startMonitoring(FocusShield.activityName, during: schedule)
            scheduledEnd = end
        } catch {
            scheduledEnd = nil   // the block still works; only the safety net is missing, and the Block tab can still lift it
        }
    }

    // MARK: saving
    private func save() {
        if let data = try? JSONEncoder().encode(selection) { defaults.set(data, forKey: Keys.selection) }
    }
}
