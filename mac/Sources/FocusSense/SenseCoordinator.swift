import Foundation
import Observation
import FocusUI

/// Starts the window watcher when a session begins and stops it when the session ends or is over, so nothing is read between sessions.
/// It also stops while the session is on hold (paused, on a break, snoozed, in a call, idle, asleep) and starts again, reading at once, when the hold ends.
/// The system watcher keeps running through a hold: it reads only idle time, calls and power, and it is what ends an idle or call hold.
@MainActor
public final class SenseCoordinator {
    private let source: WindowSource
    private let watcher: WindowWatcher
    private var accessTimer: Timer?
    private let system: SystemWatcher
    private let controller: SessionController
    private var bound = false

    public init(source: WindowSource, controller: SessionController) {
        self.controller = controller; self.source = source
        watcher = WindowWatcher(source: source, controller: controller)
        system = SystemWatcher(controller: controller)
    }

    public func bind() {
        guard !bound else { return }; bound = true; track()
        // Only the permission flag, never a window: keeps Today's "allow Accessibility" card honest between sessions and
        // clears it soon after the user allows it in System Settings.
        refreshAccess()
        accessTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refreshAccess() } }
    }

    func refreshAccess() { controller.setWindowAccess(source.isTrusted ? .allowed : .appNamesOnly) }

    private func track() {
        withObservationTracking { _ = controller.isActive; _ = controller.isHeld } onChange: { [weak self] in
            Task { @MainActor in self?.sync(); self?.track() }
        }
        sync()
    }

    func sync() {
        if controller.isSensing { watcher.start() } else { watcher.stop() }
        if controller.isActive { system.start() } else { system.stop() }
    }
}
