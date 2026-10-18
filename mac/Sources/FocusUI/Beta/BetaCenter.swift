import Foundation
import Observation
import AppKit

/// The beta program in one place: which build this is, the local journal, the feedback sheet and the tester's missions.
/// Feedback is a file the tester saves; if the build names an address, the tester's own mail app can attach it. Focus sends nothing.
@MainActor @Observable
public final class BetaCenter {
    public let build: BetaBuild
    public let journal: BetaJournal
    /// The feedback sheet shows while this is set, opened on that kind.
    public var feedbackKind: FeedbackReport.Kind?
    /// "What's new in this build" sheet.
    public var notesShown = false
    /// Opens the profile popover (Help menu and demo captures).
    public var accountRequests = 0
    /// Where the last report was saved, for the confirmation line.
    public private(set) var lastSaved: URL?
    /// Mail compose with the report attached, set by the app (it lives outside the scanned engine modules). Returns false if no mail app took it.
    @ObservationIgnored public var onEmail: ((_ file: URL, _ to: String, _ subject: String, _ body: String) -> Bool)?
    @ObservationIgnored public var crashFolder: URL = CrashReports.folder
    @ObservationIgnored public var now: () -> Date = Date.init

    public init(build: BetaBuild = .current, journal: BetaJournal) { self.build = build; self.journal = journal }

    public func requestFeedback(_ kind: FeedbackReport.Kind = .bug) { feedbackKind = kind }

    /// The crash macOS recorded for the last unclean exit, or the newest one in the report window.
    public func recentCrash() -> CrashSummary? {
        let since = journal.unacknowledgedExit.map { $0.addingTimeInterval(-3600) } ?? now().addingTimeInterval(-Double(FeedbackBuilder.window) * 86400)
        guard let url = CrashReports.latest(in: crashFolder, since: since), let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return CrashReports.summary(ips: text)
    }

    public func report(_ d: FeedbackDraft, c: SessionController) -> FeedbackReport {
        FeedbackBuilder.make(d, build: build, system: FeedbackBuilder.system(judge: c.judgeStatus, windowAccess: c.windowAccess, screen: c.previewAccess),
                             prefs: c.prefs, store: c.store, journal: journal, crash: d.includeCrash ? recentCrash() : nil, now: now())
    }

    /// Writes the report where the tester chose. Returns the file, or nil if they cancelled or the write failed.
    @discardableResult public func save(_ r: FeedbackReport, to url: URL) -> Bool {
        guard let data = r.encoded() else { return false }
        do { try data.write(to: url, options: [.atomic]) } catch { return false }
        lastSaved = url
        journal.note(.feedbackSaved)
        if journal.unacknowledgedExit != nil { journal.acknowledgeExit() }
        return true
    }

    public enum SaveOutcome: Equatable { case saved(URL), cancelled, failed }

    public func savePanel(for r: FeedbackReport) -> SaveOutcome {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = r.fileName
        panel.allowedContentTypes = [.json]
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.message = "Save the report, then send the file to whoever gave you this build. Focus sends nothing."
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        return save(r, to: url) ? .saved(url) : .failed
    }

    /// Saves the report beside the store and hands it to the mail app, addressed to the build's feedback address.
    public func email(_ r: FeedbackReport) -> Bool {
        guard let to = build.feedbackAddress, let onEmail else { return false }
        let dir = BetaJournal.defaultFolder.appendingPathComponent("feedback", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = dir.appendingPathComponent(r.fileName)
        guard save(r, to: url) else { return false }
        let subject = "Focus \(build.label): \(r.kind.title)"
        let body = "\(r.message)\n\nThe attached file is everything Focus put in this report. You can open it to check before sending."
        return onEmail(url, to, subject, body)
    }

    // MARK: notices on Today
    public func pulseDue(_ c: SessionController) -> Bool {
        build.isTesting && journal.pulseDue(sessionsFinished: c.store?.sessions.count ?? 0, sessionActive: c.isActive)
    }
    public var expired: Bool { build.channel == .beta && build.expired(at: now()) }
    public var crashNoticeDue: Bool { build.isTesting && journal.unacknowledgedExit != nil }
    public var notesDue: Bool { build.channel == .beta && journal.notesUnseen(for: build) }

    public func missions(_ c: SessionController) -> [BetaMission] { BetaMission.all(store: c.store, prefs: c.prefs, journal: journal) }
}

/// The things a tester is asked to try in this build. Each one ticks itself from what is already on this Mac; none asks for typing.
public struct BetaMission: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var symbol: String
    public var done: Bool

    @MainActor public static func all(store: DataStore?, prefs: Preferences, journal: BetaJournal, calendar: Calendar = .current) -> [BetaMission] {
        let sessions = store?.sessions ?? []
        let days = Set(sessions.map { calendar.startOfDay(for: $0.start) }).count
        return [
            .init(id: "first", title: "Finish a session", detail: "Any length. End it yourself or let the timer run out.", symbol: "play.circle",
                  done: !sessions.isEmpty),
            .init(id: "long", title: "Stay 25 minutes", detail: "One session with 25 minutes or more of active time.", symbol: "timer",
                  done: sessions.contains { $0.activeSeconds >= 1500 }),
            .init(id: "describe", title: "Describe a project", detail: "A line under Projects about what counts as work helps Focus decide.", symbol: "text.alignleft",
                  done: store?.projects.contains { !$0.context.trimmingCharacters(in: .whitespaces).isEmpty } ?? false),
            .init(id: "back", title: "Use Back to task", detail: "After a nudge, press Back to task and see where it takes you.", symbol: "arrow.uturn.backward.circle",
                  done: journal.count(.backToTask) > 0),
            .init(id: "review", title: "Answer a Review moment", detail: "Tell Focus whether a flagged moment was right or fine.", symbol: "flag",
                  done: (store?.agreement.answered ?? 0) > 0),
            .init(id: "days", title: "Use it on three days", detail: "Real days of work show what one session cannot.", symbol: "calendar",
                  done: days >= 3),
            .init(id: "feedback", title: "Send one report", detail: "A bug, a wrong call or an idea. Short is fine.", symbol: "paperplane",
                  done: journal.count(.feedbackSaved) > 0),
        ]
    }
}
