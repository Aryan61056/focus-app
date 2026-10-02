import Foundation
import FocusUI

/// Where the current window comes from. The real one reads the Accessibility tree; tests use a fake. Nothing here may touch the network.
public protocol WindowSource {
    /// The window the user is looking at, or nil when nothing should be judged (no window, or Focus itself is in front).
    func current() -> WindowSnapshot?
    /// True once the user has allowed Accessibility. Without it only the app name is available.
    var isTrusted: Bool { get }
}

/// Polls a WindowSource once a second while a session runs and passes changes to the controller.
/// Only runs during a session: when nothing is being watched, nothing is read (CLAUDE.md principle 3, never invisible).
@MainActor
public final class WindowWatcher {
    private let source: WindowSource
    private let controller: SessionController
    private var timer: Timer?
    private var last: WindowSnapshot?

    public init(source: WindowSource, controller: SessionController) { self.source = source; self.controller = controller }

    public var isRunning: Bool { timer != nil }

    public func start(interval: TimeInterval = 1) {
        guard timer == nil else { return }
        last = nil
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
    }

    public func stop() { timer?.invalidate(); timer = nil; last = nil }

    /// One read. Exposed so tests can drive it without a timer.
    public func poll() {
        controller.setWindowAccess(source.isTrusted ? .allowed : .appNamesOnly)
        guard let w = source.current(), w != last else { return }
        last = w
        controller.windowChanged(w)
    }
}
