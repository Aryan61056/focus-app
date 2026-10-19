import Foundation

/// Which build this is and what kind: read from the Info.plist keys `tools/build_app.sh` stamps (see docs/BETA.md).
/// A beta build carries its number, an end date, optional release notes and known issues and, if the owner chose them, the address
/// testers send feedback to and the GitHub project where they post it and find newer builds. Nothing here reaches the network: the
/// address is only offered to the tester's own mail app, and the project's pages open in the tester's browser when they click.
public struct BetaBuild: Equatable, Sendable {
    public enum Channel: String, Sendable { case dev, beta, release }
    public var version: String
    public var build: String
    public var buildID: String?
    public var channel: Channel
    /// After this date the build says it is out of date. It keeps working: a beta never locks anyone out of their own data.
    public var expires: Date?
    public var feedbackAddress: String?
    /// The project on GitHub, `https://github.com/<owner>/<repo>`: testers post reports as issues there and download newer builds.
    public var feedbackRepo: URL?
    public var notes: [String]
    /// Problems the owner already knows about in this build, so testers do not spend a report on them.
    public var knownIssues: [String]

    public init(version: String = "0.1.0", build: String = "1", buildID: String? = nil, channel: Channel = .dev,
                expires: Date? = nil, feedbackAddress: String? = nil, feedbackRepo: URL? = nil, notes: [String] = [], knownIssues: [String] = []) {
        self.version = version; self.build = build; self.buildID = buildID; self.channel = channel
        self.expires = expires; self.feedbackAddress = feedbackAddress; self.feedbackRepo = feedbackRepo; self.notes = notes; self.knownIssues = knownIssues
    }

    public static func from(info: [String: Any]) -> BetaBuild {
        let channel = (info["FocusChannel"] as? String).flatMap(Channel.init(rawValue:)) ?? .dev
        let expires = (info["FocusBetaExpires"] as? String).flatMap(endDay(_:))
        let address = (info["FocusFeedbackAddress"] as? String).map { $0.trimmingCharacters(in: .whitespaces) }
        return BetaBuild(version: info["CFBundleShortVersionString"] as? String ?? "0.1.0", build: info["CFBundleVersion"] as? String ?? "1",
                         buildID: info["FocusBuildID"] as? String, channel: channel, expires: expires,
                         feedbackAddress: (address?.contains("@") ?? false) ? address : nil,
                         feedbackRepo: (info["FocusFeedbackRepo"] as? String).flatMap(repo(_:)),
                         notes: Array(lines(info["FocusReleaseNotes"]).prefix(12)), knownIssues: Array(lines(info["FocusKnownIssues"]).prefix(8)))
    }

    /// The end date as the start of that day where the tester is: "2026-11-18" ends the build at midnight going into November 18 on
    /// their Mac, the date the invite and the release name. (Read as UTC it ended the evening before in the Americas.)
    static func endDay(_ text: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"
        return f.date(from: text.trimmingCharacters(in: .whitespaces))
    }

    /// One item per line in the plist, so the build script can pass a Markdown list as it is. Headings and blank lines are left out.
    static func lines(_ value: Any?) -> [String] {
        ((value as? String) ?? "").split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("- ") || $0.hasPrefix("* ") ? String($0.dropFirst(2)) : $0 }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// Only a project page on GitHub itself, owner and name, nothing else: the app opens it and two pages under it, never another site.
    static func repo(_ text: String) -> URL? {
        guard var c = URLComponents(string: text.trimmingCharacters(in: .whitespaces)), c.scheme == "https", c.host == "github.com",
              c.query == nil, c.fragment == nil, c.user == nil, c.port == nil else { return nil }
        var parts = c.path.split(separator: "/").map(String.init)
        if parts.count == 2, parts[1].hasSuffix(".git") { parts[1] = String(parts[1].dropLast(4)) }
        let ok = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") && $0.unicodeScalars.allSatisfy(ok.contains) }) else { return nil }
        c.path = "/" + parts.joined(separator: "/")
        return c.url
    }

    /// The issue form for this kind of report on the build's GitHub project, with the title and build filled in. Only the build goes
    /// in the address: the tester's words and the report travel in the form, which they read, edit and submit themself.
    public func issueURL(_ kind: FeedbackReport.Kind) -> URL? {
        guard let repo = feedbackRepo, var c = URLComponents(url: repo.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false) else { return nil }
        c.queryItems = [URLQueryItem(name: "template", value: kind.issueTemplate),
                        URLQueryItem(name: "title", value: "\(tag): \(kind.title)"),
                        URLQueryItem(name: "build", value: label)]
        return c.url
    }
    /// Where newer builds are: the project's releases page.
    public var releasesURL: URL? { feedbackRepo?.appendingPathComponent("releases") }

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

    /// When the build was made, from the start of its ID ("20261019013000-abc1234", UTC).
    public var built: Date? {
        guard let id = buildID, id.count >= 14 else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMddHHmmss"
        return f.date(from: String(id.prefix(14)))
    }
    /// How much of the beta's time is left: 1 when it was built, 0 at the end date. Nil without an end date. A build whose date is
    /// unknown is taken to run the default 30 days.
    public func remaining(at now: Date) -> Double? {
        guard let e = expires else { return nil }
        let total = e.timeIntervalSince(built ?? e.addingTimeInterval(-30 * 86400))
        guard total > 0 else { return 0 }
        return min(1, max(0, e.timeIntervalSince(now) / total))
    }

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
