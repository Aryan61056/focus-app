import Foundation
import Observation

/// Whether friends can work at all right now.
public enum FriendsAvailability: Equatable, Sendable {
    /// Ready, and this is your id.
    case available(String)
    /// No iCloud account on this Mac, or it is restricted.
    case noAccount
    /// This build cannot use iCloud (not signed for it), or iCloud said no. A plain sentence for the page.
    case unavailable(String)
}

/// What a refresh brings back: friends' cards, the cheers sent to you, and who has accepted your invite (so the page can say
/// "Invite back" to a friend who shares with you but cannot see yours yet).
public struct FriendsSnapshot: Sendable {
    public var cards: [FriendCard]
    public var cheers: [Cheer]
    public var audience: Set<String>
    public init(cards: [FriendCard], cheers: [Cheer], audience: Set<String>) { self.cards = cards; self.cheers = cheers; self.audience = audience }
}

/// How friends' numbers travel. The real one (CloudKit) lives in the FocusSocial module, so this module never imports a networking
/// framework (tools/check_privacy.py); the demo and the tests use `DemoFriendsTransport`.
@MainActor public protocol FriendsTransport: AnyObject {
    func availability() async -> FriendsAvailability
    /// Puts your card where the friends you invited can read it, creating the share the first time.
    func publish(_ card: FriendCard) async throws
    func fetch() async throws -> FriendsSnapshot
    func send(_ kind: CheerKind, to friend: String) async throws
    /// Shows the system's sharing sheet for your share.
    func invite() async throws
    /// Stops reading this friend and removes them from your share.
    func remove(_ friend: String) async throws
    /// Deletes everything you shared: your card, the share, and cheers sent to you.
    func stopSharing() async throws
}

/// Friends state for the app: your sharing switch, friends' cards, cheers. Off until you turn sharing on.
@MainActor @Observable
public final class FriendsStore {
    public enum Status: Equatable, Sendable { case off, checking, ready, syncing, unavailable(String), failed(String) }

    public private(set) var status: Status = .off
    public private(set) var friends: [FriendCard] = []
    public private(set) var cheers: [Cheer] = []
    public private(set) var you: String?
    public private(set) var lastSync: Date?
    /// Friends who accepted your invite and so see your numbers.
    public private(set) var audience: Set<String> = []
    /// Cheers you have looked at, so the sidebar count only shows new ones.
    public private(set) var seen: Set<String> = []
    /// Cheers you sent today, per friend, for the daily limit.
    private var sent: [String: [Date]] = [:]

    public static let cheersPerFriendPerDay = 3

    @ObservationIgnored let transport: FriendsTransport
    @ObservationIgnored let prefs: Preferences
    @ObservationIgnored let store: DataStore?
    @ObservationIgnored private let url: URL?
    @ObservationIgnored var now: () -> Date = Date.init

    public init(transport: FriendsTransport, prefs: Preferences, store: DataStore?, url: URL? = nil) {
        self.transport = transport; self.prefs = prefs; self.store = store; self.url = url
        load()
        if prefs.shareWithFriends { status = .checking }
    }

    public var sharing: Bool { prefs.shareWithFriends }
    public var newCheers: Int { cheers.filter { !seen.contains($0.id) }.count }
    public func seesYou(_ id: String) -> Bool { audience.contains(id) }
    public func name(of id: String) -> String { id == you ? "You" : (friends.first { $0.id == id }?.name ?? "A friend") }

    /// Your card as friends would see it now. Built from the store each time, so it is never stale.
    public var myCard: FriendCard {
        FriendCard.mine(id: you ?? "you", name: prefs.friendName.isEmpty ? "You" : prefs.friendName, emoji: prefs.friendEmoji.isEmpty ? nil : prefs.friendEmoji,
                        sessions: store?.sessions ?? [], today: now())
    }

    public func entries(_ board: Scoreboard.Board) -> [Scoreboard.Entry] {
        Scoreboard.entries((sharing ? [myCard] : []) + friends, you: you ?? "you", board: board, today: now())
    }

    public func cheersLeft(for friend: String) -> Int {
        let today = (sent[friend] ?? []).filter { Calendar.current.isDate($0, inSameDayAs: now()) }
        return max(0, Self.cheersPerFriendPerDay - today.count)
    }

    // MARK: actions

    /// Turns sharing on (asks iCloud first) or off (deletes what was shared).
    public func setSharing(_ on: Bool) async {
        if on {
            status = .checking
            switch await transport.availability() {
            case .available(let id):
                you = id; prefs.shareWithFriends = true
                await refresh()
            case .noAccount: status = .unavailable("Sign in to iCloud in System Settings to share with friends.")
            case .unavailable(let why): status = .unavailable(why)
            }
        } else {
            prefs.shareWithFriends = false
            status = .syncing
            do { try await transport.stopSharing(); status = .off } catch { status = .failed(Self.say(error)) }
            friends = []; cheers = []; audience = []; you = nil; save()
        }
    }

    /// Publishes your card and reads your friends'. Called when the Friends page opens, after a session is saved, and on request.
    public func refresh() async {
        guard sharing else { status = .off; return }
        if status == .syncing { return }
        if you == nil {
            switch await transport.availability() {
            case .available(let id): you = id
            case .noAccount: status = .unavailable("Sign in to iCloud in System Settings to share with friends."); return
            case .unavailable(let why): status = .unavailable(why); return
            }
        }
        status = .syncing
        do {
            try await transport.publish(myCard)
            let snap = try await transport.fetch()
            friends = snap.cards.filter { $0.id != you }
            cheers = snap.cheers.sorted { $0.at > $1.at }
            audience = snap.audience
            lastSync = now(); status = .ready; save()
        } catch { status = .failed(Self.say(error)) }
    }

    public func sessionSaved() { if sharing { Task { await refresh() } } }

    public func send(_ kind: CheerKind, to friend: String) async -> Bool {
        guard sharing, cheersLeft(for: friend) > 0 else { return false }
        do {
            try await transport.send(kind, to: friend)
            sent[friend, default: []].append(now()); save(); return true
        } catch { status = .failed(Self.say(error)); return false }
    }

    public func invite() async {
        do { try await transport.invite() } catch { status = .failed(Self.say(error)) }
    }

    public func remove(_ friend: String) async {
        do { try await transport.remove(friend); friends.removeAll { $0.id == friend }; save() } catch { status = .failed(Self.say(error)) }
    }

    public func markCheersSeen() {
        let ids = Set(cheers.map(\.id))
        guard !ids.isSubset(of: seen) else { return }
        seen.formUnion(ids); save()
    }

    static func say(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Could not reach iCloud. Try again in a moment."
    }

    // MARK: local copy
    // Friends' numbers are kept on disk so the page shows something offline. Counts and names only, like the cards themselves.

    struct File: Codable {
        var friends: [FriendCard] = []
        var cheers: [Cheer] = []
        var seen: [String] = []
        var sent: [String: [Date]] = [:]
        var lastSync: Date?
        var audience: [String] = []
    }

    func load() {
        guard let url, let data = try? Data(contentsOf: url), let f = try? JSONDecoder.store.decode(File.self, from: data) else { return }
        friends = f.friends; cheers = f.cheers; seen = Set(f.seen); sent = f.sent; lastSync = f.lastSync; audience = Set(f.audience)
    }

    func save() {
        guard let url else { return }
        // Seen and sent only need today and the cheers still listed.
        let ids = Set(cheers.map(\.id))
        let day = Calendar.current.startOfDay(for: now())
        let f = File(friends: friends, cheers: cheers, seen: seen.filter { ids.contains($0) },
                     sent: sent.mapValues { $0.filter { $0 >= day } }.filter { !$0.value.isEmpty }, lastSync: lastSync, audience: audience.sorted())
        guard let data = try? JSONEncoder.store.encode(f) else { return }
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static var defaultURL: URL { DataStore.defaultURL.deletingLastPathComponent().appendingPathComponent("friends.json") }
}

/// A stand-in transport with made-up friends, for the demo build and the tests. Nothing leaves the process.
@MainActor public final class DemoFriendsTransport: FriendsTransport {
    public var cards: [FriendCard]
    public var cheers: [Cheer]
    public var audience: Set<String> = []
    public private(set) var published: [FriendCard] = []
    public private(set) var sentCheers: [(CheerKind, String)] = []
    public private(set) var invites = 0
    public var answer: FriendsAvailability = .available("demo-you")

    public init(cards: [FriendCard] = [], cheers: [Cheer] = []) { self.cards = cards; self.cheers = cheers }

    public func availability() async -> FriendsAvailability { answer }
    public func publish(_ card: FriendCard) async throws { published.append(card) }
    public func fetch() async throws -> FriendsSnapshot { FriendsSnapshot(cards: cards, cheers: cheers, audience: audience) }
    public func send(_ kind: CheerKind, to friend: String) async throws { sentCheers.append((kind, friend)) }
    public func invite() async throws { invites += 1 }
    public func remove(_ friend: String) async throws { cards.removeAll { $0.id == friend } }
    public func stopSharing() async throws { published = []; cheers = [] }

    /// Synthetic friends for the demo: four people with believable, different weeks. Names are made up.
    public static func sample(today: Date = .now, calendar cal: Calendar = .current) -> DemoFriendsTransport {
        func card(_ id: String, _ name: String, emoji: String?, _ minutes: [Int], _ slips: [Int], streak: Int) -> FriendCard {
            let start = cal.startOfDay(for: today)
            var days: [ShareDay] = []
            for (i, m) in minutes.enumerated() where m > 0 {
                guard let d = cal.date(byAdding: .day, value: -(minutes.count - 1 - i), to: start) else { continue }
                days.append(ShareDay(day: FriendCard.key(d, cal), focusedSeconds: Double(m * 60), slips: slips[i], sessions: max(1, m / 45)))
            }
            return FriendCard(id: id, name: name, days: days, streak: streak, updated: today, emoji: emoji)
        }
        let cards = [
            card("maya", "Maya", emoji: "\u{1F989}", [95, 120, 0, 150, 110, 80, 135, 160, 90, 140, 70, 125, 145, 60], [1, 2, 0, 1, 0, 3, 1, 2, 0, 1, 1, 0, 2, 0], streak: 9),
            card("jonah", "Jonah", emoji: "\u{1F680}", [40, 0, 55, 70, 0, 30, 45, 50, 65, 0, 80, 40, 35, 25], [3, 0, 2, 4, 0, 1, 2, 3, 2, 0, 5, 2, 1, 1], streak: 3),
            card("priya", "Priya", emoji: "\u{1F98A}", [180, 160, 200, 0, 0, 170, 190, 210, 150, 175, 0, 195, 185, 120], [0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0], streak: 14),
            card("sam", "Sam", emoji: nil, [0, 0, 20, 35, 0, 0, 25, 0, 30, 0, 15, 0, 20, 10], [0, 0, 1, 2, 0, 0, 1, 0, 2, 0, 1, 0, 0, 1], streak: 1),
        ]
        let cheers = [
            Cheer(id: "c1", from: "maya", kind: .keepGoing, at: today.addingTimeInterval(-1_800)),
            Cheer(id: "c2", from: "priya", kind: .fire, at: today.addingTimeInterval(-7_200)),
            Cheer(id: "c3", from: "jonah", kind: .withYou, at: today.addingTimeInterval(-86_400)),
        ]
        let t = DemoFriendsTransport(cards: cards, cheers: cheers)
        t.audience = ["maya", "jonah", "priya"]   // Sam shares with you but has not accepted yours yet
        return t
    }
}
