import Foundation
import Observation
import FocusUI

/// Starts the window watcher when a session begins and stops it when the session ends or is over, so nothing is read between sessions.
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
        withObservationTracking { _ = controller.isActive } onChange: { [weak self] in
            Task { @MainActor in self?.sync(); self?.track() }
        }
        sync()
    }

    func sync() { if controller.isActive { watcher.start(); system.start() } else { watcher.stop(); system.stop() } }
}
