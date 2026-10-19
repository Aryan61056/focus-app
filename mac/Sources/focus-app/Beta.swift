import AppKit
import FocusUI

/// The beta's app-side pieces: where its file lives, the hang watch, and the mail app hand-off (kept out of the engine modules that
/// tools/check_privacy.py scans, like every other way out of the app). Mail only opens a draft; the tester presses Send.
@MainActor enum BetaSetup {
    static var hangWatch: HangWatch?

    static func make(demo: Bool, testFolder: String?) -> BetaCenter {
        let env = ProcessInfo.processInfo.environment
        if demo {
            // FOCUS_DEMO_BETA=1 shows a made-up beta build in captures; the journal stays in memory.
            var build = BetaBuild.current
            if env["FOCUS_DEMO_BETA"] == "1" {
                build = BetaBuild(version: build.version, build: "2", buildID: build.buildID, channel: .beta,
                                  expires: Calendar.current.date(byAdding: .day, value: 24, to: Date()), feedbackAddress: nil,
                                  feedbackRepo: URL(string: "https://github.com/example/focus-app"),
                                  notes: ["Back to task returns to the tab you were in", "A weekly one-click question", "Send feedback from your profile, bottom left"],
                                  knownIssues: ["The notch can lag a second after waking from sleep"])
            }
            let center = BetaCenter(build: build, journal: BetaJournal())
            // Demo captures never open a browser; the buttons still show as they would in a beta.
            center.onOpenWeb = { _ in false }
            return center
        }
        let folder = (testFolder?.isEmpty == false) ? URL(fileURLWithPath: testFolder!, isDirectory: true) : BetaJournal.defaultFolder
        let center = BetaCenter(journal: .standard(in: folder))
        center.journal.launched()
        center.onEmail = { file, to, subject, body in
            guard let mail = NSSharingService(named: .composeEmail) else { return false }
            mail.recipients = [to]; mail.subject = subject
            let items: [Any] = [body, file]
            guard mail.canPerform(withItems: items) else { return false }
            mail.perform(withItems: items)
            return true
        }
        // The build's GitHub project in the tester's browser, on a click: its issue form or its releases page. Nothing else is opened,
        // and nothing goes in the address but the build (BetaBuild.issueURL); the tester's words travel in the form they submit.
        center.onOpenWeb = { url in
            guard url.scheme == "https", url.host == "github.com" else { return false }
            return NSWorkspace.shared.open(url)
        }
        let watch = HangWatch(isFront: { NSApp.isActive }) { [weak center] seconds in center?.journal.note(.hang, seconds) }
        watch.start(); hangWatch = watch
        return center
    }
}
