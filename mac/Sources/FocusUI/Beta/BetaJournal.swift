import Foundation
import Observation

/// What happened, as kinds and numbers only: never a task, title, address, screen word or model reason (CLAUDE.md principle 2).
/// The journal stays on this Mac. It leaves only inside a feedback report the tester previews and saves themself.
public enum BetaEventKind: String, Codable, CaseIterable, Sendable {
    case launch, quit, uncleanExit
    case sessionStart, sessionEnd          // sessionEnd value: active minutes
    case warning, pauseScreen, checkIn     // a nudge the person saw
    case backToTask                        // value: 1 when Focus found the place, 0 when it did not
    case judgeRefusal, judgeUnavailable
    case saveFailed
    case hang                              // value: seconds the app did not respond
    case feedbackSaved, pulseAnswered      // pulseAnswered value: the score
}

public struct BetaEvent: Codable, Equatable, Sendable {
    public var at: Date
    public var kind: BetaEventKind
    public var value: Double?
    public init(at: Date, kind: BetaEventKind, value: Double? = nil) { self.at = at; self.kind = kind; self.value = value }
}

/// "How is the beta going?" One score from 1 to 5 and, if the tester wants, a line they typed.
public struct BetaPulse: Codable, Equatable, Sendable {
    public var at: Date
    public var score: Int
    public var note: String?
    public init(at: Date, score: Int, note: String? = nil) { self.at = at; self.score = score; self.note = note }
}

/// The beta's own small file beside the store (~/Library/Application Support/Focus/beta.json), plus a marker that says the app is
/// running, so the next launch knows whether the last one ended without quitting. A journal with no URL lives in memory (tests, demo).
@MainActor @Observable
public final class BetaJournal {
    public static let limit = 600
    public static let pulseEvery: TimeInterval = 7 * 24 * 3600
    /// Pulses start once the tester has really used the build, never on the first day.
    public static let pulseAfterSessions = 3

    public private(set) var events: [BetaEvent] = []
    public private(set) var pulses: [BetaPulse] = []
    /// Off: nothing new is written. The switch is in Settings > Beta.
    public var recording = true { didSet { save() } }
    /// Weekly pulse question on Today. Off: never asked.
    public var pulseOn = true { didSet { save() } }
    public private(set) var lastPulseAsked: Date?
    /// The last launch found the previous one had not quit. Cleared when the tester answers or dismisses the notice.
    public private(set) var unacknowledgedExit: Date?
    /// The build whose "What's new" was last shown.
    public private(set) var notesSeenFor: String?
    /// The first beta launch's welcome on Today was seen (opened or put off). It never comes back, even for a newer build.
    public private(set) var welcomed = false

    @ObservationIgnored private let url: URL?
    @ObservationIgnored private let marker: URL?
    @ObservationIgnored public var now: () -> Date = Date.init

    struct File: Codable {
        var events: [BetaEvent] = []
        var pulses: [BetaPulse] = []
        var recording: Bool? = true
        var pulseOn: Bool? = true
        var lastPulseAsked: Date?
        var unacknowledgedExit: Date?
        var notesSeenFor: String?
        var welcomed: Bool?
    }

    public init(url: URL? = nil, marker: URL? = nil) {
        self.url = url; self.marker = marker
        guard let url, let data = try? Data(contentsOf: url), let f = try? JSONDecoder.store.decode(File.self, from: data) else { return }
        events = f.events; pulses = f.pulses; recording = f.recording ?? true; pulseOn = f.pulseOn ?? true
        lastPulseAsked = f.lastPulseAsked; unacknowledgedExit = f.unacknowledgedExit; notesSeenFor = f.notesSeenFor; welcomed = f.welcomed ?? false
    }

    public static var defaultFolder: URL { DataStore.defaultURL.deletingLastPathComponent() }
    public static func standard(in folder: URL? = nil) -> BetaJournal {
        let folder = folder ?? defaultFolder
        return BetaJournal(url: folder.appendingPathComponent("beta.json"), marker: folder.appendingPathComponent("running.marker"))
    }

    // MARK: launch and quit
    /// Call once at launch. Returns true when the last run ended without a clean quit (a crash, a force quit or a power loss).
    @discardableResult public func launched() -> Bool {
        var unclean = false
        if let marker {
            let fm = FileManager.default
            if fm.fileExists(atPath: marker.path) {
                unclean = true
                let when = (try? fm.attributesOfItem(atPath: marker.path))?[.modificationDate] as? Date ?? now()
                note(.uncleanExit, at: when)
                unacknowledgedExit = when
            }
            try? Data().write(to: marker, options: [.atomic])
        }
        note(.launch)
        return unclean
    }

    public func quitCleanly() {
        note(.quit)
        if let marker { try? FileManager.default.removeItem(at: marker) }
    }

    public func acknowledgeExit() { unacknowledgedExit = nil; save() }

    // MARK: events
    public func note(_ kind: BetaEventKind, _ value: Double? = nil) { note(kind, value, at: now()) }
    func note(_ kind: BetaEventKind, _ value: Double? = nil, at: Date) {
        guard recording else { return }
        events.append(BetaEvent(at: at, kind: kind, value: value.map { ($0 * 10).rounded() / 10 }))
        if events.count > Self.limit { events.removeFirst(events.count - Self.limit) }
        save()
    }

    public func count(_ kind: BetaEventKind, since: Date? = nil) -> Int {
        events.filter { e in e.kind == kind && (since.map { e.at >= $0 } ?? true) }.count
    }
    public func recent(days: Int) -> [BetaEvent] {
        let from = now().addingTimeInterval(-Double(days) * 86400)
        return events.filter { $0.at >= from }
    }

    public func clear() { events = []; pulses = []; lastPulseAsked = nil; unacknowledgedExit = nil; save() }

    // MARK: weekly pulse
    /// Asked between sessions only, at most once a week, after the tester has finished a few sessions on this Mac.
    public func pulseDue(sessionsFinished: Int, sessionActive: Bool) -> Bool {
        guard pulseOn, !sessionActive, sessionsFinished >= Self.pulseAfterSessions else { return false }
        guard let last = lastPulseAsked else { return true }
        return now().timeIntervalSince(last) >= Self.pulseEvery
    }
    public func answerPulse(score: Int, note text: String? = nil) {
        let s = min(5, max(1, score))
        let t = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        pulses.append(BetaPulse(at: now(), score: s, note: (t?.isEmpty ?? true) ? nil : String(t!.prefix(500))))
        if pulses.count > 52 { pulses.removeFirst(pulses.count - 52) }
        lastPulseAsked = now()
        note(.pulseAnswered, Double(s))
        save()
    }
    public func skipPulse() { lastPulseAsked = now(); save() }

    // MARK: what's new
    public func notesUnseen(for build: BetaBuild) -> Bool { !build.notes.isEmpty && notesSeenFor != build.label }
    public func markNotesSeen(for build: BetaBuild) { notesSeenFor = build.label; save() }
    /// The welcome covers this build's notes too, so they are not offered again right after it.
    public func markWelcomed(for build: BetaBuild) { welcomed = true; notesSeenFor = build.label; save() }

    // MARK: file
    private func save() {
        guard let url else { return }
        let f = File(events: events, pulses: pulses, recording: recording, pulseOn: pulseOn, lastPulseAsked: lastPulseAsked,
                     unacknowledgedExit: unacknowledgedExit, notesSeenFor: notesSeenFor, welcomed: welcomed)
        guard let data = try? JSONEncoder.store.encode(f) else { return }
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// A main-thread timer that notices when it fires late: if it was held up two seconds or more, the app did not respond for that long.
/// No second thread and no sampling of what the app was doing. Gaps from sleep or App Nap are not counted (the app must be in front,
/// and a gap over a minute is a sleep, not a hang).
@MainActor public final class HangWatch {
    public nonisolated static let interval = 0.5
    public nonisolated static let threshold = 2.0
    public nonisolated static let ignoreAbove = 60.0
    private var timer: Timer?
    private var last = Date()
    private let isFront: () -> Bool
    private let onHang: (Double) -> Void

    public init(isFront: @escaping () -> Bool, onHang: @escaping (Double) -> Void) { self.isFront = isFront; self.onHang = onHang }

    /// Seconds the main thread was stuck, or nil when the delay was ordinary (or too long to be a hang).
    public nonisolated static func hang(last: Date, now: Date, interval: Double = interval) -> Double? {
        let late = now.timeIntervalSince(last) - interval
        return late >= threshold && late < ignoreAbove ? late : nil
    }

    public func start() {
        last = Date()
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.fire() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    public func stop() { timer?.invalidate(); timer = nil }

    private func fire() {
        let n = Date()
        if isFront(), let h = Self.hang(last: last, now: n) { onHang(h) }
        last = n
    }
}
