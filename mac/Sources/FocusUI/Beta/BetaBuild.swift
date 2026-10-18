import Foundation

/// Which build this is and what kind: read from the Info.plist keys `tools/build_app.sh` stamps (see docs/BETA.md).
/// A beta build carries its number, an end date, optional release notes and, if the owner chose one, the address testers send
/// feedback to. Nothing here reaches the network; the address is only offered to the tester's own mail app.
public struct BetaBuild: Equatable, Sendable {
    public enum Channel: String, Sendable { case dev, beta, release }
    public var version: String
    public var build: String
    public var buildID: String?
    public var channel: Channel
    /// After this date the build says it is out of date. It keeps working: a beta never locks anyone out of their own data.
    public var expires: Date?
    public var feedbackAddress: String?
    public var notes: [String]

    public init(version: String = "0.1.0", build: String = "1", buildID: String? = nil, channel: Channel = .dev,
                expires: Date? = nil, feedbackAddress: String? = nil, notes: [String] = []) {
        self.version = version; self.build = build; self.buildID = buildID; self.channel = channel
        self.expires = expires; self.feedbackAddress = feedbackAddress; self.notes = notes
    }

    public static func from(info: [String: Any]) -> BetaBuild {
        let channel = (info["FocusChannel"] as? String).flatMap(Channel.init(rawValue:)) ?? .dev
        let expires = (info["FocusBetaExpires"] as? String).flatMap { ISO8601DateFormatter.day.date(from: $0) }
        let address = (info["FocusFeedbackAddress"] as? String).map { $0.trimmingCharacters(in: .whitespaces) }
        // Notes are one item per line in the plist, so the build script can pass a Markdown list as it is.
        let notes = ((info["FocusReleaseNotes"] as? String) ?? "").split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("- ") || $0.hasPrefix("* ") ? String($0.dropFirst(2)) : $0 }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return BetaBuild(version: info["CFBundleShortVersionString"] as? String ?? "0.1.0", build: info["CFBundleVersion"] as? String ?? "1",
                         buildID: info["FocusBuildID"] as? String, channel: channel, expires: expires,
                         feedbackAddress: (address?.contains("@") ?? false) ? address : nil, notes: Array(notes.prefix(12)))
    }

    public static var current: BetaBuild { from(info: Bundle.main.infoDictionary ?? [:]) }

    /// "0.1.0 beta 3", "0.1.0 (dev)" or "0.1.0".
    public var label: String {
        switch channel {
        case .beta: return "\(version) beta \(build)"
        case .dev: return "\(version) (dev)"
        case .release: return version
        }
    }
    /// Short tag for the account chip.
    public var tag: String { channel == .beta ? "Beta \(build)" : channel == .dev ? "Dev build" : "Version \(version)" }

    public func expired(at now: Date) -> Bool { expires.map { now >= $0 } ?? false }
    public func daysLeft(at now: Date, calendar: Calendar = .current) -> Int? {
        guard let e = expires else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: e)).day
    }
    /// Testers are asked for feedback in the beta and in dev builds (the owner tests those); a release keeps it in the Help menu only.
    public var isTesting: Bool { channel != .release }
}

extension ISO8601DateFormatter {
    /// "2026-12-01": the build script's end date.
    static var day: ISO8601DateFormatter { let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f }
}
