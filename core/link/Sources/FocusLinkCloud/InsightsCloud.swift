import Foundation
import CloudKit
import FocusLinkWire
#if os(macOS)
import Security
import AppKit
#else
import UIKit
#endif

/// What the Mac keeps in the person's own iCloud for their phone: the Insights numbers as of a moment.
public struct CloudSnapshot: Codable, Equatable, Sendable {
    public var asOf: Date
    public var insights: Insights
    public init(asOf: Date, insights: Insights) { self.asOf = asOf; self.insights = insights }

    /// What a reader shows. A snapshot from an earlier day must not claim time for today.
    public func shown(now: Date = Date(), calendar cal: Calendar = .current) -> Insights {
        var i = insights
        if !cal.isDate(asOf, inSameDayAs: now) { i.todayOnTaskSeconds = 0 }
        return i
    }
}

public enum CloudAvailability: Equatable, Sendable {
    case available, noAccount
    /// This build cannot use iCloud (not signed for it, or no container named), or iCloud said no. A plain sentence.
    case unavailable(String)
}

/// Insights between the Mac and the iPhone through the person's private iCloud database (docs/ICLOUD-SYNC.md).
/// The Mac writes one record; the phone reads it. Both are the same Apple ID, so no sharing, accounts or servers of ours are involved.
/// The numbers and task names are CloudKit encrypted values: iCloud stores them but cannot read them.
///
/// Unverified against real iCloud: it needs a signed build with the iCloud entitlement and a container. Without one, every call
/// answers `unavailable` instead of touching CloudKit (making a container without the entitlement crashes the app).
@MainActor public final class InsightsCloud {
    static let zoneName = "Sync", subscriptionID = "insights-changes"

    /// The container named by the app's Info.plist (`FocusCloudContainer`). Empty or missing means iCloud is not set up in this build.
    public static var configuredContainer: String? {
        let id = Bundle.main.object(forInfoDictionaryKey: "FocusCloudContainer") as? String
        return (id?.isEmpty ?? true) || id?.hasPrefix("$(") == true ? nil : id
    }

    private let containerID: String?
    private var container: CKContainer?
    private var db: CKDatabase? { container?.privateCloudDatabase }
    private var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName) }
    private var handler: (@MainActor () -> Void)?
    private var accountWatcher: NSObjectProtocol?

    public init(containerID: String? = InsightsCloud.configuredContainer) { self.containerID = containerID }

    /// macOS can read its own entitlements; iOS cannot, so there the build's Info.plist naming a container is the switch.
    var entitled: Bool {
        guard let containerID else { return false }
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let services = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) as? [String] ?? []
        let containers = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String] ?? []
        return services.contains("CloudKit") && containers.contains(containerID)
        #else
        return true
        #endif
    }

    private func ready() throws -> CKDatabase {
        guard entitled, let containerID else { throw SyncError.notSetUp }
        if container == nil { container = CKContainer(identifier: containerID) }
        return container!.privateCloudDatabase
    }

    public func availability() async -> CloudAvailability {
        guard entitled, let containerID else { return .unavailable("This build of Hushd is not set up for iCloud yet.") }
        if container == nil { container = CKContainer(identifier: containerID) }
        do {
            switch try await container!.accountStatus() {
            case .available: return .available
            case .noAccount, .restricted: return .noAccount
            default: return .unavailable("iCloud is not reachable right now. Try again in a moment.")
            }
        } catch { return .unavailable(Self.say(error)) }
    }

    // MARK: write (the Mac)

    public func publish(_ snapshot: CloudSnapshot) async throws {
        try await plain {
            let db = try ready()
            _ = try await db.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
            let record = try SnapshotRecord.make(snapshot, zone: zoneID)
            // Replaces whatever is there, so a second Mac or a stale copy never blocks the newest numbers.
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        }
    }

    /// Deletes the zone, and the snapshot with it.
    public func delete() async throws {
        guard entitled else { return }
        await stopListening()
        try await plain {
            do { _ = try await ready().modifyRecordZones(saving: [], deleting: [zoneID]) }
            catch let e as CKError where e.code == .zoneNotFound { }
        }
    }

    // MARK: read (the iPhone, and a second Mac)

    public func fetch() async throws -> CloudSnapshot? {
        try await plain {
            let db = try ready()
            do {
                let record = try await db.record(for: CKRecord.ID(recordName: SnapshotRecord.recordName, zoneID: zoneID))
                return SnapshotRecord.decode(record)
            } catch let e as CKError where e.code == .unknownItem || e.code == .zoneNotFound { return nil }
        }
    }

    // MARK: pushes and account changes

    /// `onChange` runs when the snapshot changes elsewhere or the iCloud account changes: read again.
    public func listen(onChange: @escaping @MainActor () -> Void) async {
        handler = onChange
        guard entitled, let db = try? ready() else { return }
        if accountWatcher == nil {
            accountWatcher = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handler?() }
            }
        }
        #if os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #else
        UIApplication.shared.registerForRemoteNotifications()
        #endif
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        let sub = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: Self.subscriptionID)
        sub.notificationInfo = info
        _ = try? await db.modifySubscriptions(saving: [sub], deleting: [])
    }

    public func stopListening() async {
        handler = nil
        if let w = accountWatcher { NotificationCenter.default.removeObserver(w); accountWatcher = nil }
        _ = try? await db?.modifySubscriptions(saving: [], deleting: [Self.subscriptionID])
    }

    /// The app delegate got a remote notification: true if it was ours (and the reader has been told).
    @discardableResult public func receive(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let n = CKNotification(fromRemoteNotificationDictionary: userInfo), n.subscriptionID == Self.subscriptionID else { return false }
        handler?()
        return true
    }

    // MARK: errors

    public enum SyncError: LocalizedError {
        case notSetUp, plain(String)
        public var errorDescription: String? {
            switch self {
            case .notSetUp: return "This build of Hushd is not set up for iCloud yet."
            case .plain(let s): return s
            }
        }
    }

    /// Runs a CloudKit call, waits once when iCloud asks for a pause, and turns an error into a sentence a screen can show.
    func plain<T>(_ body: () async throws -> T) async throws -> T {
        do {
            do { return try await body() }
            catch let e as CKError where [.requestRateLimited, .zoneBusy, .serviceUnavailable].contains(e.code) {
                try await Task.sleep(nanoseconds: UInt64(min(e.retryAfterSeconds ?? 3, 8) * 1_000_000_000))
                return try await body()
            }
        } catch let e as SyncError { throw e } catch { throw SyncError.plain(Self.say(error)) }
    }

    nonisolated static func say(_ error: Error) -> String {
        guard let e = error as? CKError else { return "Could not reach iCloud. Try again in a moment." }
        switch e.code {
        case .partialFailure:
            if let inner = e.partialErrorsByItemID?.values.first { return say(inner) }
            return "Could not reach iCloud. Try again in a moment."
        case .networkFailure, .networkUnavailable: return "You seem to be offline. This will catch up when you are back online."
        case .notAuthenticated, .accountTemporarilyUnavailable: return "Sign in to iCloud in Settings to sync."
        case .quotaExceeded: return "Your iCloud storage is full."
        case .requestRateLimited, .zoneBusy, .serviceUnavailable: return "iCloud is busy. Try again in a minute."
        default: return "Could not reach iCloud. Try again in a moment."
        }
    }
}

/// How a snapshot becomes a CloudKit record and back. Pure, so the tests run it without iCloud.
enum SnapshotRecord {
    static let recordType = "FocusInsights", recordName = "insights"

    static func make(_ snapshot: CloudSnapshot, zone: CKRecordZone.ID) throws -> CKRecord {
        let r = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: recordName, zoneID: zone))
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        r.encryptedValues["snapshot"] = try enc.encode(snapshot)
        return r
    }

    static func decode(_ r: CKRecord) -> CloudSnapshot? {
        guard r.recordType == recordType, let data = r.encryptedValues["snapshot"] as? Data else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(CloudSnapshot.self, from: data)
    }
}

/// What the Mac and the phone need from iCloud, so their tests can use a stand-in.
@MainActor public protocol InsightsSyncing: AnyObject {
    func availability() async -> CloudAvailability
    func publish(_ snapshot: CloudSnapshot) async throws
    func fetch() async throws -> CloudSnapshot?
    func delete() async throws
    func listen(onChange: @escaping @MainActor () -> Void) async
    func stopListening() async
}
extension InsightsCloud: InsightsSyncing {}
