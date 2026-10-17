import Foundation
import Observation
import FocusUI
import FocusLinkWire
import FocusLinkCloud

/// Keeps the phone's Insights in the person's own iCloud, so the phone shows them when the Mac is off or on another network.
/// Off until the person turns it on in the iPhone window; turning it off deletes what was stored (docs/ICLOUD-SYNC.md).
/// One way: the Mac writes, the phone reads. Starting and controlling a session stays on the local link.
@MainActor @Observable
public final class PhoneSync {
    public enum Status: Equatable { case off, checking, ready(Date), unavailable(String), failed(String) }

    public private(set) var status: Status = .off
    public private(set) var enabled: Bool

    @ObservationIgnored private let cloud: any InsightsSyncing
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private weak var controller: SessionController?
    @ObservationIgnored private var last: CloudSnapshot?
    @ObservationIgnored private var tracking = false
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored var now: () -> Date = Date.init

    private static let enabledKey = "focus.sync.enabled"
    /// After a failed write, one more try later; a change in between tries sooner.
    static let retryAfter: TimeInterval = 120

    public init(cloud: (any InsightsSyncing)? = nil, defaults: UserDefaults? = nil) {
        // FOCUS_TEST_STORE (the app's testing switch) keeps this setting out of the real one, like the phone link's.
        let testFolder = ProcessInfo.processInfo.environment["FOCUS_TEST_STORE"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        let d = defaults ?? testFolder.flatMap { UserDefaults(suiteName: "focus-app.test.\($0.lastPathComponent)") } ?? .standard
        self.defaults = d
        self.cloud = cloud ?? InsightsCloud()
        enabled = d.bool(forKey: Self.enabledKey)
        if enabled { status = .checking }
    }

    /// Hand over the controller once the app has one. Publishes right away if the person had turned this on.
    public func attach(_ controller: SessionController) {
        self.controller = controller
        track()
        if enabled { Task { await publish() } }
    }

    public func setEnabled(_ on: Bool) async {
        if on {
            status = .checking
            switch await cloud.availability() {
            case .available: enabled = true; defaults.set(true, forKey: Self.enabledKey); await publish()
            case .noAccount: status = .unavailable("Sign in to iCloud in System Settings to sync with your phone.")
            case .unavailable(let why): status = .unavailable(why)
            }
        } else {
            enabled = false; defaults.set(false, forKey: Self.enabledKey)
            retry?.cancel(); last = nil
            do { try await cloud.delete(); status = .off } catch { status = .failed(Self.say(error)) }
        }
    }

    /// Writes the current Insights if they changed since the last write.
    public func publish() async {
        guard enabled, let controller else { return }
        var insights = InsightsBuilder.build(store: controller.store, prefs: controller.prefs, todayOnTaskSeconds: controller.todayOnTaskSeconds(), now: now())
        // The week's days carry the time they were worked out; snap them to midnight so an unchanged week compares equal.
        insights.week = insights.week.map { var d = $0; d.day = Calendar.current.startOfDay(for: d.day); return d }
        // The clock alone is no reason to write: only numbers the phone would show differently.
        if let last, last.insights == insights, case .ready = status { return }
        let snap = CloudSnapshot(asOf: now(), insights: insights)
        do {
            if status != .checking { status = .checking }
            try await cloud.publish(snap)
            last = snap; status = .ready(snap.asOf)
        } catch {
            status = .failed(Self.say(error))
            retry?.cancel()
            retry = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.retryAfter * 1_000_000_000))
                if !Task.isCancelled { await self?.publish() }
            }
        }
    }

    /// Re-run whenever the numbers the phone shows could have changed. Observation fires before the change lands, so publish on the next turn.
    private func track() {
        guard let controller, !tracking else { return }
        tracking = true
        withObservationTracking {
            _ = controller.store?.sessions.count
            _ = controller.prefs.dailyGoalMinutes
            _ = controller.prefs.showProgress
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.tracking = false
                await self.publish()
                self.track()
            }
        }
    }

    static func say(_ error: Error) -> String { (error as? LocalizedError)?.errorDescription ?? "Could not reach iCloud. Try again in a moment." }
}
