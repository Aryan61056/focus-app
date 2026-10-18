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
                build = BetaBuild(version: build.version, build: "3", buildID: build.buildID, channel: .beta,
                                  expires: Calendar.current.date(byAdding: .day, value: 24, to: Date()), feedbackAddress: nil,
                                  notes: ["Back to task returns to the tab you were in", "A weekly one-click question", "Send feedback from your profile, bottom left"])
            }
            return BetaCenter(build: build, journal: BetaJournal())
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
        let watch = HangWatch(isFront: { NSApp.isActive }) { [weak center] seconds in center?.journal.note(.hang, seconds) }
        watch.start(); hangWatch = watch
        return center
    }
}
