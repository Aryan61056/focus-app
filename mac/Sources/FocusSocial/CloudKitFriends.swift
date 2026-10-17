import Foundation
import AppKit
import CloudKit
import Security
import FocusUI

/// Friends over iCloud (docs/SOCIAL.md). The one place in the app that talks to CloudKit; FocusUI only sees `FriendsTransport`.
///
/// Layout: your private database holds one zone, `Friends`, shared as a whole with the people you invite (read only). In it are your
/// card (record "card") and the cheers you send (one record each, addressed to a friend). A friend reads your zone from their shared
/// database and picks out your card and the cheers addressed to them. Nobody writes into anyone else's zone.
///
/// Unverified: this needs a provisioned build with the iCloud entitlement and a real container. The local ad-hoc build has neither, so
/// `availability()` says so instead of touching CloudKit (creating a container without the entitlement crashes the app).
@MainActor public final class CloudKitFriends: FriendsTransport {
    /// Placeholder: follows the bundle ID, which waits on the owner's Mac distribution decision.
    /// A signed build names its real container in Info.plist (`FocusCloudContainer`, written by tools/build_app.sh).
    public static var containerID: String {
        (Bundle.main.object(forInfoDictionaryKey: "FocusCloudContainer") as? String) ?? "iCloud.com.example.focus-app"
    }
    static let sharedSub = "friends-shared", privateSub = "friends-private"
    static let zoneName = "Friends"
    static let cardName = FriendRecords.cardName
    /// Cheers older than this are left out and, for the ones you sent, deleted on the next publish.
    static let cheerLife: TimeInterval = 7 * 86_400

    private lazy var container = CKContainer(identifier: Self.containerID)
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }
    private var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName) }
    private var me: String?
    private var handler: (@MainActor (FriendsEvent) -> Void)?
    private var accountWatcher: NSObjectProtocol?
    private let inviteDelegate = InviteDelegate()

    public init() {}

    /// The entitlements this process was signed with: iCloud with CloudKit, and our container.
    static var entitled: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let services = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) as? [String] ?? []
        let containers = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String] ?? []
        return services.contains("CloudKit") && containers.contains(containerID)
    }

    public func availability() async -> FriendsAvailability {
        guard Self.entitled else { return .unavailable("Friends need iCloud, and this build of Focus is not set up for it yet.") }
        do {
            switch try await container.accountStatus() {
            case .available:
                let id = try await container.userRecordID().recordName
                me = id
                return .available(id)
            case .noAccount, .restricted: return .noAccount
            default: return .unavailable("iCloud is not reachable right now. Try again in a moment.")
            }
        } catch { return .unavailable(Self.say(error)) }
    }

    // MARK: FriendsTransport, with errors as plain sentences

    public func publish(_ card: FriendCard) async throws { try await plain { try await _publish(card) } }
    public func send(_ kind: CheerKind, to friend: String) async throws { try await plain { try await _send(kind, to: friend) } }
    public func fetch() async throws -> FriendsSnapshot { try await plain { try await _fetch() } }
    public func invite() async throws { try await plain { try await _invite() } }
    public func remove(_ friend: String) async throws { try await plain { try await _remove(friend) } }
    public func stopSharing() async throws { try await plain { try await _stopSharing() } }

    // MARK: pushes and account changes

    public func listen(_ handler: @escaping @MainActor (FriendsEvent) -> Void) async {
        self.handler = handler
        guard Self.entitled else { return }
        if accountWatcher == nil {
            accountWatcher = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.me = nil; self?.handler?(.accountChanged) }
            }
        }
        // Pushes tell this Mac when a friend's numbers change (shared database) or someone accepts your invite (private database).
        // Missing push entitlement is not fatal: the page still refreshes when it opens and after each session.
        NSApplication.shared.registerForRemoteNotifications()
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        let shared = CKDatabaseSubscription(subscriptionID: Self.sharedSub), mine = CKDatabaseSubscription(subscriptionID: Self.privateSub)
        shared.notificationInfo = info; mine.notificationInfo = info
        _ = try? await sharedDB.modifySubscriptions(saving: [shared], deleting: [])
        _ = try? await privateDB.modifySubscriptions(saving: [mine], deleting: [])
    }

    public func stopListening() async {
        handler = nil
        if let w = accountWatcher { NotificationCenter.default.removeObserver(w); accountWatcher = nil }
        guard Self.entitled else { return }
        _ = try? await sharedDB.modifySubscriptions(saving: [], deleting: [Self.sharedSub])
        _ = try? await privateDB.modifySubscriptions(saving: [], deleting: [Self.privateSub])
    }

    /// The app delegate got a remote notification: if it is from our subscriptions, tell the store.
    public func receive(_ userInfo: [String: Any]) {
        guard let n = CKNotification(fromRemoteNotificationDictionary: userInfo),
              n.subscriptionID == Self.sharedSub || n.subscriptionID == Self.privateSub else { return }
        handler?(.remoteChange)
    }

    // MARK: your zone

    /// The Friends zone and its zone-wide share, made the first time.
    func ensureShare() async throws -> CKShare {
        _ = try await privateDB.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        if let existing = try? await privateDB.record(for: shareID) as? CKShare { return existing }
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "Focus friends" as CKRecordValue
        share.publicPermission = .none   // only people you invite
        let saved = try await privateDB.modifyRecords(saving: [share], deleting: [], savePolicy: .allKeys)
        if case .success(let r)? = saved.saveResults[share.recordID], let s = r as? CKShare { return s }
        return share
    }

    func _publish(_ card: FriendCard) async throws {
        _ = try await ensureShare()
        let record = try FriendRecords.card(card, zone: zoneID)
        // Your old cheers go in the same trip, so the zone never fills up.
        let stale = try await records(in: privateDB, zone: zoneID).filter {
            $0.recordType == "FocusCheer" && ($0.creationDate ?? .distantPast) < Date().addingTimeInterval(-Self.cheerLife)
        }
        _ = try await privateDB.modifyRecords(saving: [record], deleting: stale.map(\.recordID), savePolicy: .allKeys)
    }

    func _send(_ kind: CheerKind, to friend: String) async throws {
        _ = try await ensureShare()
        let record = FriendRecords.cheer(kind, to: friend, zone: zoneID)
        _ = try await privateDB.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
    }

    // MARK: friends' zones

    func _fetch() async throws -> FriendsSnapshot {
        if me == nil { me = try await container.userRecordID().recordName }
        var cards: [FriendCard] = [], cheers: [Cheer] = []
        let cutoff = Date().addingTimeInterval(-Self.cheerLife)
        for zone in try await sharedDB.allRecordZones() where zone.zoneID.zoneName == Self.zoneName {
            let owner = zone.zoneID.ownerName
            for r in try await records(in: sharedDB, zone: zone.zoneID) {
                if let card = FriendRecords.decodeCard(r, owner: owner) { cards.append(card) }
                else if let cheer = FriendRecords.decodeCheer(r, owner: owner, me: me, cutoff: cutoff) { cheers.append(cheer) }
            }
        }
        return FriendsSnapshot(cards: cards, cheers: cheers, audience: try await audience())
    }

    /// Who accepted your invite.
    func audience() async throws -> Set<String> {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        guard let share = try? await privateDB.record(for: shareID) as? CKShare else { return [] }
        return Set(share.participants.compactMap { p in
            p.role != .owner && p.acceptanceStatus == .accepted ? p.userIdentity.userRecordID?.recordName : nil
        })
    }

    /// Every record in a zone, following the change feed from the start (no query indexes needed).
    func records(in db: CKDatabase, zone: CKRecordZone.ID) async throws -> [CKRecord] {
        var out: [CKRecord] = [], token: CKServerChangeToken?
        while true {
            let page = try await db.recordZoneChanges(inZoneWith: zone, since: token)
            out += page.modificationResultsByID.values.compactMap { try? $0.get().record }
            token = page.changeToken
            if !page.moreComing { return out }
        }
    }

    // MARK: invites, removing, stopping

    func _invite() async throws {
        let share = try await ensureShare()
        let item = NSItemProvider()
        item.registerCloudKitShare(share, container: container)
        guard let service = NSSharingService(named: .cloudSharing), service.canPerform(withItems: [item]) else {
            throw FriendsError.cannotInvite
        }
        // Friends may only read: the sheet offers private, read-only invites, and anything else is tightened after it saves.
        inviteDelegate.onSaved = { [weak self] share in Task { @MainActor in await self?.tighten(share) } }
        inviteDelegate.onDone = { [weak self] in Task { @MainActor in self?.handler?(.remoteChange) } }
        service.delegate = inviteDelegate
        service.perform(withItems: [item])
    }

    /// Makes every friend read-only, in case the sheet let one through as read and write.
    func tighten(_ share: CKShare) async {
        var changed = false
        for p in share.participants where p.role != .owner && p.permission == .readWrite { p.permission = .readOnly; changed = true }
        if changed { _ = try? await privateDB.modifyRecords(saving: [share], deleting: [], savePolicy: .changedKeys) }
    }

    /// A friend's invite link was opened: join their zone.
    public func accept(_ metadata: CKShare.Metadata) async throws {
        _ = try await container.accept(metadata)
    }

    func _remove(_ friend: String) async throws {
        if let zone = try await sharedDB.allRecordZones().first(where: { $0.zoneID.ownerName == friend && $0.zoneID.zoneName == Self.zoneName }) {
            _ = try await sharedDB.modifyRecordZones(saving: [], deleting: [zone.zoneID])
        }
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        if let share = try? await privateDB.record(for: shareID) as? CKShare,
           let p = share.participants.first(where: { $0.userIdentity.userRecordID?.recordName == friend }) {
            share.removeParticipant(p)
            _ = try await privateDB.modifyRecords(saving: [share], deleting: [], savePolicy: .changedKeys)
        }
    }

    /// Deleting the zone deletes your card, your cheers and the share with it, so friends lose access at once.
    func _stopSharing() async throws {
        guard Self.entitled else { return }
        await stopListening()
        do { _ = try await privateDB.modifyRecordZones(saving: [], deleting: [zoneID]) }
        catch let e as CKError where e.code == .zoneNotFound { }
    }

    enum FriendsError: LocalizedError {
        case cannotInvite, plain(String)
        var errorDescription: String? {
            switch self {
            case .cannotInvite: return "The invite sheet could not open. Check that iCloud is on in System Settings."
            case .plain(let s): return s
            }
        }
    }

    /// Runs a CloudKit call, waits once when iCloud asks for a pause, and turns an error into a sentence the page can show.
    func plain<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await attempt(body) } catch let e as FriendsError { throw e } catch { throw FriendsError.plain(Self.say(error)) }
    }

    private func attempt<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() }
        catch let e as CKError where [.requestRateLimited, .zoneBusy, .serviceUnavailable].contains(e.code) {
            try await Task.sleep(nanoseconds: UInt64(min(e.retryAfterSeconds ?? 3, 8) * 1_000_000_000))
            return try await body()
        }
    }

    static func say(_ error: Error) -> String {
        guard let e = error as? CKError else { return "Could not reach iCloud. Try again in a moment." }
        switch e.code {
        case .partialFailure:
            // One sentence for the first thing that went wrong inside a batch.
            if let inner = e.partialErrorsByItemID?.values.first { return say(inner) }
            return "Could not reach iCloud. Try again in a moment."
        case .networkFailure, .networkUnavailable: return "You seem to be offline. Friends will catch up when you are back online."
        case .notAuthenticated, .accountTemporarilyUnavailable: return "Sign in to iCloud in System Settings to share with friends."
        case .quotaExceeded: return "Your iCloud storage is full."
        case .requestRateLimited, .zoneBusy, .serviceUnavailable: return "iCloud is busy. Try again in a minute."
        case .permissionFailure: return "iCloud did not allow that. Check that iCloud Drive is on in System Settings."
        default: return "Could not reach iCloud. Try again in a moment."
        }
    }
}

/// Keeps the invite sheet to what Friends allows, and reports back when it closes.
final class InviteDelegate: NSObject, NSCloudSharingServiceDelegate {
    var onSaved: ((CKShare) -> Void)?
    var onDone: (() -> Void)?
    func options(for cloudKitSharingService: NSSharingService, share provider: NSItemProvider) -> NSSharingService.CloudKitOptions {
        [.allowPrivate, .allowReadOnly]
    }
    func sharingService(_ sharingService: NSSharingService, didSave share: CKShare) { onSaved?(share) }
    func sharingService(_ sharingService: NSSharingService, didCompleteForItems items: [Any], error: Error?) { onDone?() }
}

/// How a card and a cheer become CloudKit records and back. Pure, so the tests can run them without iCloud.
enum FriendRecords {
    static let cardType = "FocusCard", cheerType = "FocusCheer", cardName = "card"

    /// Encrypted end to end: iCloud stores these values but cannot read them.
    static func card(_ card: FriendCard, zone: CKRecordZone.ID) throws -> CKRecord {
        let r = CKRecord(recordType: cardType, recordID: CKRecord.ID(recordName: FriendRecords.cardName, zoneID: zone))
        r.encryptedValues["name"] = card.name
        r.encryptedValues["days"] = try JSONEncoder().encode(card.days)
        r.encryptedValues["streak"] = card.streak
        r.encryptedValues["emoji"] = card.emoji ?? ""
        return r
    }

    static func cheer(_ kind: CheerKind, to friend: String, zone: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: cheerType, recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone))
        r.encryptedValues["kind"] = kind.rawValue
        r.encryptedValues["to"] = friend
        return r
    }

    /// Only what the zone's owner wrote counts, so nobody can put words in a friend's mouth even if a share gave write access.
    static func trusted(_ r: CKRecord, owner: String) -> Bool {
        guard let creator = r.creatorUserRecordID?.recordName else { return true }
        return creator == owner || creator == CKCurrentUserDefaultName
    }

    static func decodeCard(_ r: CKRecord, owner: String, updated: Date? = nil) -> FriendCard? {
        guard r.recordType == cardType, r.recordID.recordName == FriendRecords.cardName, trusted(r, owner: owner),
              let name = r.encryptedValues["name"] as? String, let data = r.encryptedValues["days"] as? Data,
              let days = try? JSONDecoder().decode([ShareDay].self, from: data) else { return nil }
        // Sizes are capped so a hand-made record cannot fill the page.
        return FriendCard(id: owner, name: String(name.prefix(40)), days: Array(days.suffix(FriendCard.daysKept)),
                          streak: min(max(r.encryptedValues["streak"] as? Int ?? 0, 0), 100_000),
                          updated: updated ?? r.modificationDate ?? .distantPast, emoji: r.encryptedValues["emoji"] as? String)
    }

    static func decodeCheer(_ r: CKRecord, owner: String, me: String?, cutoff: Date, at: Date? = nil) -> Cheer? {
        guard r.recordType == cheerType, trusted(r, owner: owner), let me, r.encryptedValues["to"] as? String == me,
              let raw = r.encryptedValues["kind"] as? String, let kind = CheerKind(rawValue: raw),
              let at = at ?? r.creationDate, at >= cutoff else { return nil }
        return Cheer(id: r.recordID.recordName, from: owner, kind: kind, at: at)
    }
}
