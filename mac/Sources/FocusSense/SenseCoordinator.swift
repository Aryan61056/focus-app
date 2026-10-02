import Foundation
import Observation
import FocusUI

/// Starts the window watcher when a session begins and stops it when the session ends or is over, so nothing is read between sessions.
@MainActor
public final class SenseCoordinator {
    private let watcher: WindowWatcher
    private let controller: SessionController
    private var bound = false

    public init(source: WindowSource, controller: SessionController) {
        self.controller = controller
        watcher = WindowWatcher(source: source, controller: controller)
    }

    public func bind() { guard !bound else { return }; bound = true; track() }

    private func track() {
        withObservationTracking { _ = controller.isActive } onChange: { [weak self] in
            Task { @MainActor in self?.sync(); self?.track() }
        }
        sync()
    }

    func sync() { if controller.isActive { watcher.start() } else { watcher.stop() } }
}
