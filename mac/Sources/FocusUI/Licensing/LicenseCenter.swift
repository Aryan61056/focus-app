import Foundation
import Observation

// Hushd's license, as the app sees it. The rules (the per-key Mac cap, revoke, expiry) live on the server; this file only keeps what
// it said, decides what to show, and lets the app keep working through a short time offline. The network call itself is a closure the
// app target provides (`LicenseTransport`), so the engine modules stay free of networking (tools/check_privacy.py).

/// What the server says about a key. Mirrors `license` in src/lib/licensing/handler.ts on the website.
public struct LicenseInfo: Codable, Equatable, Sendable {
    public var plan: String
    public var expiresAt: Date?
    public var maxActivations: Int
    public var activations: Int
    /// The last four characters of the key, the only part shown on screen.
    public var keyHint: String
    public init(plan: String, expiresAt: Date? = nil, maxActivations: Int = 2, activations: Int = 1, keyHint: String) {
        self.plan = plan; self.expiresAt = expiresAt; self.maxActivations = maxActivations; self.activations = activations; self.keyHint = keyHint
    }
}

/// Why a key was turned down. The raw values are the server's `error` codes; `offlineTooLong` is only ever decided here.
public enum LicenseRefusal: String, Equatable, Sendable {
    case invalidKey = "invalid_key", notActivated = "not_activated", activationLimit = "activation_limit"
    case revoked, expired, missingDevice = "missing_device", badRequest = "bad_request", serverError = "server_error"
    case offlineTooLong = "offline_too_long"

    /// One plain sentence for the person, in Hushd's voice: what happened and what to do.
    public var message: String {
        switch self {
        case .invalidKey: return "That key isn’t one we know. Check it for typos."
        case .notActivated: return "This Mac isn’t activated on that key yet."
        case .activationLimit: return "That key is already on the most Macs it allows. Deactivate one of them first."
        case .revoked: return "That key has been turned off."
        case .expired: return "That key has run out."
        case .missingDevice, .badRequest: return "Hushd couldn’t send that. Try again."
        case .serverError: return "Licensing is busy right now. Try again in a minute."
        case .offlineTooLong: return "Hushd hasn’t been able to check your key for a while. Connect to the internet once."
        }
    }
    /// A refusal that says nothing about the key itself: the server was down or confused. These never lock anyone out.
    public var isTransient: Bool { self == .serverError || self == .badRequest || self == .missingDevice }
}

public enum LicenseCall: Sendable { case activate, validate, deactivate }

public enum LicenseReply: Equatable, Sendable {
    case ok(LicenseInfo)
    case refused(LicenseRefusal, LicenseInfo?)
    /// No answer at all: offline, timed out, or not an answer Hushd understands.
    case unreachable
}

/// Sends one license call for a key and returns the answer. Provided by the app, which knows this Mac's id and the server's address.
public typealias LicenseTransport = @Sendable (LicenseCall, String) async -> LicenseReply

/// What the Mac keeps about its own license: the key, the last answer, and when the server last confirmed it.
public struct LicenseRecord: Codable, Equatable, Sendable {
    public var key: String
    public var info: LicenseInfo
    public var validatedAt: Date
}

public enum LicenseStatus: Equatable, Sendable {
    /// A key is on this Mac and the server hasn’t been asked yet this launch. It counts as licensed meanwhile.
    case checking(LicenseInfo)
    case unlicensed
    case active(LicenseInfo)
    /// The server couldn’t be reached; the last good answer still holds for this many more days.
    case offline(LicenseInfo, daysLeft: Int)
    case blocked(LicenseRefusal, LicenseInfo?)
}

/// Where the record lives: one small JSON file, readable by this user only. Not the Keychain: Hushd builds are signed ad hoc, so every
/// update would change the app’s identity and the Keychain would ask for the login password again.
public struct LicenseVault: Sendable {
    public var url: URL?
    public init(url: URL?) { self.url = url }
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Focus", isDirectory: true).appendingPathComponent("license.json")
    }
    public func load() -> LicenseRecord? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(LicenseRecord.self, from: data)
    }
    public func save(_ record: LicenseRecord?) {
        guard let url else { return }
        guard let record else { try? FileManager.default.removeItem(at: url); return }
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(record) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// How a key is typed and shown. The server accepts sloppy input too; this makes the field look right while typing.
public enum LicenseKey {
    public static let prefix = "HUSHD"
    public static let groups = 5, groupSize = 5

    /// "hushd abc12 de..." -> "HUSHD-ABC12-DE...". Letters and digits only, the prefix added, at most five groups of five.
    public static func format(_ raw: String) -> String {
        var body = raw.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        if body.hasPrefix(prefix) { body.removeFirst(prefix.count) }
        body = String(body.prefix(groups * groupSize))
        guard !body.isEmpty else { return raw.trimmingCharacters(in: .whitespaces).isEmpty ? "" : prefix + "-" }
        var parts = [prefix]
        var rest = Substring(body)
        while !rest.isEmpty { parts.append(String(rest.prefix(groupSize))); rest = rest.dropFirst(groupSize) }
        return parts.joined(separator: "-")
    }
    public static func isComplete(_ formatted: String) -> Bool {
        let p = formatted.split(separator: "-")
        return p.count == groups + 1 && p.dropFirst().allSatisfy { $0.count == groupSize }
    }
}

@MainActor @Observable
public final class LicenseCenter {
    public private(set) var status: LicenseStatus
    /// A call is on its way (the Activate button shows it).
    public private(set) var busy = false
    /// The last thing that went wrong while the person was doing something, in words.
    public private(set) var error: String?
    /// A key was just accepted and the person hasn’t pressed Continue yet, so the success state stays up instead of vanishing.
    public private(set) var awaitingContinue = false
    /// Whether the app is locked without a license. Dev builds are not (so the person building Hushd isn’t asked), unless forced.
    public let enforced: Bool
    /// Opens a page on the Hushd website in the browser, set by the app (outside the scanned modules).
    @ObservationIgnored public var onOpenWeb: ((URL) -> Bool)?
    @ObservationIgnored public var now: () -> Date = Date.init

    @ObservationIgnored private let transport: LicenseTransport
    @ObservationIgnored private let vault: LicenseVault
    @ObservationIgnored private var record: LicenseRecord?
    /// How long a good answer keeps Hushd working with no connection.
    public static let graceDays = 14
    /// A good answer is trusted for this long before the app asks again.
    public static let recheckEvery: TimeInterval = 24 * 3600

    public init(transport: @escaping LicenseTransport, vault: LicenseVault, enforced: Bool, now: @escaping () -> Date = Date.init) {
        self.transport = transport; self.vault = vault; self.enforced = enforced; self.now = now
        record = vault.load()
        status = record.map { .checking($0.info) } ?? .unlicensed
        if let r = record { status = Self.offlineStatus(r, now: now()) ?? .checking(r.info) }
    }

    // MARK: what the rest of the app asks

    /// True while Hushd may be used: a key that is confirmed, being checked, or confirmed recently enough to carry through no connection.
    public var allowsUse: Bool {
        switch status { case .checking, .active, .offline: return true; case .unlicensed, .blocked: return false }
    }
    /// The app shows the license screen instead of its work. Never while a session runs: the caller checks that.
    public var needsLicense: Bool { enforced && (!allowsUse || awaitingContinue) }
    public var info: LicenseInfo? {
        switch status { case .checking(let i), .active(let i), .offline(let i, _): return i; case .blocked(_, let i): return i; case .unlicensed: return nil }
    }
    public var keyHint: String? { info?.keyHint }
    /// Days until the plan ends, when it ends (beta keys do).
    public func daysLeft(calendar: Calendar = .current) -> Int? {
        guard let e = info?.expiresAt else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now()), to: calendar.startOfDay(for: e)).day
    }
    public var summary: String {
        switch status {
        case .unlicensed: return "No key on this Mac"
        case .checking, .active: return "Active"
        case .offline(_, let d): return "Active, offline (\(d) day\(d == 1 ? "" : "s") left without a connection)"
        case .blocked(let why, _): return why.message
        }
    }

    // MARK: acting

    /// Turns a typed key into an activation on this Mac. On success the key is kept; otherwise `error` says why in words.
    @discardableResult public func activate(_ typed: String) async -> Bool {
        let key = LicenseKey.format(typed)
        guard LicenseKey.isComplete(key) else { error = "That key looks short. It has five groups of five."; return false }
        guard !busy else { return false }
        busy = true; error = nil
        defer { busy = false }
        switch await transport(.activate, key) {
        case .ok(let info):
            store(LicenseRecord(key: key, info: info, validatedAt: now()))
            status = .active(info); awaitingContinue = true
            return true
        case .refused(let why, _): error = why.message; return false
        case .unreachable: error = "Hushd couldn’t reach the internet. Connect and try again."; return false
        }
    }

    /// Confirms the key with the server. Offline or a busy server never locks anyone out until the grace period is used up.
    public func refresh() async {
        guard let r = record else { status = .unlicensed; return }
        switch await transport(.validate, r.key) {
        case .ok(let info):
            store(LicenseRecord(key: r.key, info: info, validatedAt: now()))
            status = .active(info)
        case .refused(let why, let info) where !why.isTransient:
            status = .blocked(why, info ?? r.info)
        case .refused, .unreachable:
            status = Self.offlineStatus(r, now: now()) ?? .offline(r.info, daysLeft: Self.graceDays)
        }
    }

    /// Asks again only when the last good answer is a day old.
    public func refreshIfDue() async {
        guard let r = record, now().timeIntervalSince(r.validatedAt) >= Self.recheckEvery || { if case .checking = status { return true }; return false }() else { return }
        await refresh()
    }

    /// Frees this Mac’s place on the key, so it can be used on another Mac. The key is forgotten here once the server agrees.
    @discardableResult public func deactivate() async -> Bool {
        guard let r = record, !busy else { return false }
        busy = true; error = nil
        defer { busy = false }
        switch await transport(.deactivate, r.key) {
        case .ok, .refused(.notActivated, _), .refused(.invalidKey, _):
            forget(); return true
        case .refused(let why, _): error = why.message; return false
        case .unreachable: error = "Hushd couldn’t reach the internet, so this Mac’s place on the key wasn’t freed. Try again online."; return false
        }
    }

    /// Continue after a key was accepted.
    public func acknowledge() { awaitingContinue = false }
    public func clearError() { error = nil }

    @discardableResult public func openWeb(_ url: URL) -> Bool { onOpenWeb?(url) ?? false }

    // MARK: private

    private func store(_ r: LicenseRecord) { record = r; vault.save(r) }
    private func forget() { record = nil; vault.save(nil); status = .unlicensed; awaitingContinue = false }

    /// How a record stands with no new answer: still inside the grace period (offline, days left) or past it (blocked). Nil when it was
    /// confirmed less than a day ago, so it simply counts as active.
    static func offlineStatus(_ r: LicenseRecord, now: Date) -> LicenseStatus? {
        let age = now.timeIntervalSince(r.validatedAt)
        guard age >= recheckEvery else { return nil }
        let left = graceDays - Int(age / 86400)
        return left > 0 ? .offline(r.info, daysLeft: left) : .blocked(.offlineTooLong, r.info)
    }
}
