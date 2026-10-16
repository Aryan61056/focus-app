import AppKit
import FocusUI

/// Local auto-update for the dev bundle. `tools/build_app.sh` stamps each build with an ID and the folder it was built in; this app
/// watches that folder and, when a newer finished build appears, offers to restart into it. No network, nothing downloaded, and it
/// never restarts without a click (the controller also refuses while a session runs).
@MainActor final class Updater {
    private let controller: SessionController
    private let own = Bundle.main.bundleURL
    private let ownID = Bundle.main.infoDictionary?["FocusBuildID"] as? String
    private let source: URL?
    private var timer: Timer?

    init(controller: SessionController) {
        self.controller = controller
        source = (Bundle.main.infoDictionary?["FocusBuildSource"] as? String).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    func start() {
        // Only an installed copy updates: the running bundle must be an .app that is not the build folder's own copy.
        guard let source, own.pathExtension == "app",
              own.resolvingSymlinksInPath().path != source.resolvingSymlinksInPath().path else { return }
        controller.updateSource = source.path
        controller.onCheckUpdates = { [weak self] in self?.check() }
        controller.onInstallUpdate = { [weak self] in self?.install($0) }
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.check() } }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    func check() {
        guard let source, controller.prefs.offerUpdates else { controller.setUpdateOffer(nil); return }
        controller.setUpdateOffer(UpdateCheck.offer(ownID: ownID, ownApp: own, sourceApp: source))
    }

    /// A helper shell waits for this process to exit, swaps the bundle (only if the new one's signature verifies), and opens it again.
    /// It reopens the old copy if anything fails, so an update can never leave the app unlaunchable. Paths are arguments, not script text.
    func install(_ offer: UpdateOffer) {
        // Only a bundle signed for this app's own identifier is swapped in, and the old copy is kept until the new one is in place, so a
        // failure at any step puts the old one back instead of leaving no app.
        let script = """
        n=0; while kill -0 "$3" 2>/dev/null && [ $n -lt 50 ]; do sleep 0.2; n=$((n+1)); done
        if /usr/bin/codesign --verify -R='identifier "com.example.focus-app.dev"' "$1" 2>/dev/null; then
          rm -rf "$2.updating" "$2.old"
          if /usr/bin/ditto "$1" "$2.updating" && mv "$2" "$2.old"; then
            if mv "$2.updating" "$2"; then rm -rf "$2.old"; else mv "$2.old" "$2"; fi
          fi
          rm -rf "$2.updating"
        fi
        /usr/bin/open "$2"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "sh", offer.sourcePath, own.path, String(ProcessInfo.processInfo.processIdentifier)]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return }
        NSApp.terminate(nil)
    }
}
