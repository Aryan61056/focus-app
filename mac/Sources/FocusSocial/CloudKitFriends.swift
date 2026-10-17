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
    public static let containerID = "iCloud.com.example.focus-app"
    static let zoneName = "Friends"
    static let cardName = "card"
    /// Cheers older than this are left out and, for the ones you sent, deleted on the next publish.
    static let cheerLife: TimeInterval = 7 * 86_400

    private lazy var container = CKContainer(identifier: Self.containerID)
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }
    private var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName) }
    private var me: String?

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
        let record = CKRecord(recordType: "FocusCard", recordID: CKRecord.ID(recordName: Self.cardName, zoneID: zoneID))
        // Encrypted end to end: iCloud stores them but cannot read them.
        record.encryptedValues["name"] = card.name
        record.encryptedValues["days"] = try JSONEncoder().encode(card.days)
        record.encryptedValues["streak"] = card.streak
        record.encryptedValues["emoji"] = card.emoji ?? ""
        // Your old cheers go in the same trip, so the zone never fills up.
        let stale = try await records(in: privateDB, zone: zoneID).filter {
            $0.recordType == "FocusCheer" && ($0.creationDate ?? .distantPast) < Date().addingTimeInterval(-Self.cheerLife)
        }
        _ = try await privateDB.modifyRecords(saving: [record], deleting: stale.map(\.recordID), savePolicy: .allKeys)
    }

    func _send(_ kind: CheerKind, to friend: String) async throws {
        _ = try await ensureShare()
        let record = CKRecord(recordType: "FocusCheer", recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID))
        record.encryptedValues["kind"] = kind.rawValue
        record.encryptedValues["to"] = friend
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
                // Only what the zone's owner wrote counts, so nobody can put words in a friend's mouth.
                if let creator = r.creatorUserRecordID?.recordName, creator != owner, creator != CKCurrentUserDefaultName { continue }
                switch r.recordType {
                case "FocusCard" where r.recordID.recordName == Self.cardName:
                    guard let name = r.encryptedValues["name"] as? String, let data = r.encryptedValues["days"] as? Data,
                          let days = try? JSONDecoder().decode([ShareDay].self, from: data) else { continue }
                    cards.append(FriendCard(id: owner, name: String(name.prefix(40)), days: days,
                                            streak: r.encryptedValues["streak"] as? Int ?? 0, updated: r.modificationDate ?? .distantPast,
                                            emoji: r.encryptedValues["emoji"] as? String))
                case "FocusCheer":
                    guard r.encryptedValues["to"] as? String == me, let raw = r.encryptedValues["kind"] as? String,
                          let kind = CheerKind(rawValue: raw), let at = r.creationDate, at >= cutoff else { continue }
                    cheers.append(Cheer(id: r.recordID.recordName, from: owner, kind: kind, at: at))
                default: continue
                }
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
        service.perform(withItems: [item])
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

    /// Runs a CloudKit call and turns its error into a sentence the page can show.
    func plain<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch let e as FriendsError { throw e } catch { throw FriendsError.plain(Self.say(error)) }
    }

    static func say(_ error: Error) -> String {
        guard let e = error as? CKError else { return "Could not reach iCloud. Try again in a moment." }
        switch e.code {
        case .networkFailure, .networkUnavailable: return "You seem to be offline. Friends will catch up when you are back online."
        case .notAuthenticated: return "Sign in to iCloud in System Settings to share with friends."
        case .quotaExceeded: return "Your iCloud storage is full."
        case .requestRateLimited, .zoneBusy, .serviceUnavailable: return "iCloud is busy. Try again in a minute."
        default: return "Could not reach iCloud. Try again in a moment."
        }
    }
}
