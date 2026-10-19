import Foundation
import FocusJudge

/// One piece of beta feedback, as the file a tester saves and sends themself. Schema `focus-feedback/1`, read by tools/beta/feedback.py.
/// What it may hold: the words the tester typed, the build, the Mac's kind and macOS version, permission states, settings that are
/// switches or choices, counts, the event journal (kinds and numbers) and a crash summary. What it never holds: task or project names,
/// window titles, addresses, screen words, pictures or the model's reasons (docs/BETA.md, "What a report holds"). Focus's recent calls go
/// as the call and how it was reached only (on, unsure or off; model, rule, matching words), never which window it was about.
public struct FeedbackReport: Codable, Equatable, Sendable {
    public static let schema = "focus-feedback/1"
    public static let messageLimit = 4000

    public enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case bug, wrongCall, idea, other
        public var id: String { rawValue }
        public var title: String {
            switch self { case .bug: return "Something broke"; case .wrongCall: return "Wrong call"; case .idea: return "Idea"; case .other: return "Other" }
        }
        public var symbol: String {
            switch self { case .bug: return "ladybug"; case .wrongCall: return "exclamationmark.bubble"; case .idea: return "lightbulb"; case .other: return "text.bubble" }
        }
        public var prompt: String {
            switch self {
            case .bug: return "What did you do, and what happened instead?"
            case .wrongCall: return "Was a window called off task when it was work, or the other way round? Describe the kind of window, not its contents."
            case .idea: return "What would make Focus better for you?"
            case .other: return "Tell us anything."
            }
        }
        /// The GitHub issue form (.github/ISSUE_TEMPLATE) for this kind. Ideas and everything else share one.
        public var issueTemplate: String {
            switch self { case .bug: return "beta-bug.yml"; case .wrongCall: return "beta-wrong-call.yml"; case .idea, .other: return "beta-idea.yml" }
        }
    }

    public struct App: Codable, Equatable, Sendable { public var version, build: String; public var buildID: String?; public var channel: String }
    public struct System: Codable, Equatable, Sendable {
        public var macOS: String
        public var model: String
        public var memoryGB: Int
        public var appleSilicon: Bool
        public var lowPower: Bool
        public var judge: String           // ready, unavailable, unknown
        public var windowAccess: String    // allowed, appNamesOnly, unknown
        public var screenRecording: String // allowed, denied, unknown
    }
    public struct Usage: Codable, Equatable, Sendable {
        public var sessions: Int
        public var sessionsLast14Days: Int
        public var activeMinutesLast14Days: Int
        public var onTaskMinutesLast14Days: Int
        public var drifts: Int
        public var nudges: Int
        public var refusals: Int
        public var reads: ReadStats
        public var reviewAnswered: Int
        public var reviewAgreed: Int
        public var projects: Int
        public var projectsDescribed: Int
        public var daysUsed: Int
    }
    /// One of Focus's recent calls, without the window: when, what it decided, and how.
    public struct Call: Codable, Equatable, Sendable {
        public var at: Date
        public var call: String   // on, unsure, off
        public var by: String     // model, rule, words, refused, private, skipped
    }

    public var schema = FeedbackReport.schema
    public var id: String
    public var created: Date
    public var kind: Kind
    public var message: String
    public var contact: String?
    public var app: App
    public var system: System?
    public var settings: [String: String]?
    public var usage: Usage?
    public var events: [BetaEvent]?
    public var pulses: [BetaPulse]?
    public var crash: CrashSummary?
    public var calls: [Call]?

    public func encoded() -> Data? {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try? e.encode(self)
    }
    public var fileName: String {
        let day = ISO8601DateFormatter.day.string(from: created)
        return "focus-feedback-\(day)-\(id.prefix(8)).json"
    }
}

/// What the tester chose in the feedback sheet.
public struct FeedbackDraft: Equatable, Sendable {
    public var kind: FeedbackReport.Kind = .bug
    public var message = ""
    public var contact = ""
    public var includeSystem = true
    public var includeUsage = true
    public var includeEvents = true
    public var includeCrash = true
    /// Focus's last calls (the call and how, never the window). Most useful with a wrong call.
    public var includeCalls = true
    public init(kind: FeedbackReport.Kind = .bug) { self.kind = kind }
    public var ready: Bool { !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public enum FeedbackBuilder {
    /// Days of journal, pulses and usage a report carries.
    public static let window = 14

    @MainActor public static func make(_ d: FeedbackDraft, build: BetaBuild, system: FeedbackReport.System?, prefs: Preferences?,
                                       store: DataStore?, journal: BetaJournal?, crash: CrashSummary?, readings: [Reading] = [],
                                       now: Date = Date(), id: UUID = UUID()) -> FeedbackReport {
        let since = now.addingTimeInterval(-Double(window) * 86400)
        let contact = d.contact.trimmingCharacters(in: .whitespacesAndNewlines)
        return FeedbackReport(
            id: id.uuidString.lowercased(), created: now, kind: d.kind,
            message: String(d.message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(FeedbackReport.messageLimit)),
            contact: contact.isEmpty ? nil : String(contact.prefix(200)),
            app: .init(version: build.version, build: build.build, buildID: build.buildID, channel: build.channel.rawValue),
            system: d.includeSystem ? system : nil,
            settings: d.includeSystem ? prefs.map(settings) : nil,
            usage: d.includeUsage ? store.map { usage($0, since: since, now: now) } : nil,
            events: d.includeEvents ? journal?.events.filter { $0.at >= since }.suffix(400).map { $0 } : nil,
            pulses: d.includeUsage ? journal?.pulses.filter { $0.at >= since } : nil,
            crash: d.includeCrash ? crash : nil,
            calls: d.includeCalls && !readings.isEmpty ? calls(readings) : nil)
    }

    /// The call and how it was reached, newest first. The window's app, title, key and the model's reason stay behind.
    public static func calls(_ readings: [Reading]) -> [FeedbackReport.Call] {
        readings.prefix(12).map { r in
            let call: String
            switch r.call { case .on: call = "on"; case .unsure: call = "unsure"; case .off: call = "off" }
            let by: String
            switch r.source {
            case .model: by = r.failed ? "refused" : (r.byWords ? "words" : "model")
            case .rule: by = r.byWords ? "words" : "rule"
            case .sensitive: by = "private"
            case .skipped: by = "skipped"
            }
            return FeedbackReport.Call(at: r.date, call: call, by: by)
        }
    }

    /// Switches and choices only. The never-judged list is app names the person typed, so only its length goes.
    @MainActor public static func settings(_ p: Preferences) -> [String: String] {
        func b(_ v: Bool) -> String { v ? "on" : "off" }
        return [
            "preset": p.preset.rawValue, "checkRate": p.checkRate.rawValue, "sensitivity": p.sensitivity.rawValue, "nudgeTone": p.nudgeTone.rawValue,
            "useModel": b(p.useModel), "aiHelp": b(p.aiHelp), "matchTaskWords": b(p.matchTaskWords), "readScreen": b(p.readScreen),
            "skipPersonal": b(p.skipPersonal), "neverJudgedCount": String(p.neverJudgedApps.count), "escalate": b(p.escalate),
            "screenGrayscale": b(p.screenGrayscale), "grayWindowOnly": b(p.grayWindowOnly), "screenFog": b(p.screenFog), "screenEdges": b(p.screenEdges),
            "cursorHalo": b(p.cursorHalo), "easeSound": b(p.easeSound), "showBanner": b(p.showBanner), "headsUp": b(p.headsUp),
            "hapticTap": b(p.hapticTap), "speakNudges": b(p.speakNudges), "nudgeSound": b(p.nudgeSound), "showNotch": b(p.showNotch),
            "switchTabs": b(p.switchTabs), "closeOnStrict": b(p.closeOnStrict), "hideDistractingApp": b(p.hideDistractingApp),
            "practice": p.practiceRemoved ? "removed" : (p.practiceActive ? "active" : "done"), "showProgress": b(p.showProgress),
            "dailyGoalMinutes": String(p.dailyGoalMinutes), "rhythm": p.rhythm.rawValue, "textScale": String(format: "%.2f", p.textScale),
            "shareWithFriends": b(p.shareWithFriends),
        ]
    }

    @MainActor public static func usage(_ s: DataStore, since: Date, now: Date, calendar: Calendar = .current) -> FeedbackReport.Usage {
        let recent = s.sessions.filter { $0.start >= since }
        let agree = s.agreement
        return .init(
            sessions: s.sessions.count, sessionsLast14Days: recent.count,
            activeMinutesLast14Days: Int(recent.reduce(0) { $0 + $1.activeSeconds } / 60),
            onTaskMinutesLast14Days: Int(recent.reduce(0) { $0 + $1.onTaskSeconds } / 60),
            drifts: recent.reduce(0) { $0 + $1.drifts }, nudges: recent.reduce(0) { $0 + $1.interrupts }, refusals: recent.reduce(0) { $0 + $1.refusals },
            reads: s.readTotals, reviewAnswered: agree.answered, reviewAgreed: agree.agreed,
            projects: s.projects.count, projectsDescribed: s.projects.filter { !$0.context.trimmingCharacters(in: .whitespaces).isEmpty }.count,
            daysUsed: Set(s.sessions.map { calendar.startOfDay(for: $0.start) }).count)
    }

    /// The Mac's kind and state, for the report. Reads sysctl and ProcessInfo only.
    public static func system(judge: JudgeStatus, windowAccess: WindowAccess, screen: PreviewAccess) -> FeedbackReport.System {
        let p = ProcessInfo.processInfo
        let v = p.operatingSystemVersion
        func word(_ j: JudgeStatus) -> String { switch j { case .ready: return "ready"; case .unavailable: return "unavailable"; case .unknown: return "unknown" } }
        func word(_ w: WindowAccess) -> String { switch w { case .allowed: return "allowed"; case .appNamesOnly: return "appNamesOnly"; case .unknown: return "unknown" } }
        func word(_ s: PreviewAccess) -> String { switch s { case .allowed: return "allowed"; case .denied: return "denied"; case .unknown: return "unknown" } }
        return .init(macOS: "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)", model: sysctl("hw.model") ?? "unknown",
                     memoryGB: Int((Double(p.physicalMemory) / 1_073_741_824).rounded()), appleSilicon: sysctlInt("hw.optional.arm64") == 1,
                     lowPower: p.isLowPowerModeEnabled, judge: word(judge), windowAccess: word(windowAccess), screenRecording: word(screen))
    }

    static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
    static func sysctlInt(_ name: String) -> Int32? {
        var v: Int32 = 0; var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &v, &size, nil, 0) == 0 ? v : nil
    }
}
