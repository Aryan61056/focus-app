import Foundation
import Observation
import FocusUI

/// While a session runs and the user has turned screen reading on, takes a picture every few seconds, shows it in the app, and
/// reads the words on it (every `readEvery` seconds, or at once for a new app) so the judge can use them. A picture is dropped if
/// the window became private while it was being taken. Stops, and everything is cleared, when the session ends or the switch goes off.
@MainActor
public final class PreviewWatcher {
    private let grabber: ScreenGrabber
    private let reader: ScreenReader
    private let controller: SessionController
    private let readEvery: TimeInterval
    private var lastRead = Date.distantPast
    private var lastApp = ""
    private var lastKey = ""
    private var lastWords = ""
    private var timer: Timer?
    private var busy = false
    private var ticks = 0
    private var bound = false

    public init(grabber: ScreenGrabber, reader: ScreenReader = VisionScreenReader(), controller: SessionController, readEvery: TimeInterval = 8, openSettings: (() -> Void)? = nil) {
        self.grabber = grabber; self.reader = reader; self.controller = controller; self.readEvery = readEvery
        controller.onRequestPreviewAccess = { [weak self] in
            guard let self else { return }
            self.grabber.requestAccess(); self.syncAccess()
            if !self.grabber.isAllowed { openSettings?() }
        }
    }

    public var isRunning: Bool { timer != nil }

    private var accessTimer: Timer?
    public func bind() {
        guard !bound else { return }; bound = true; track()
        // Only the permission flag, so Settings shows the truth between sessions.
        accessTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.syncAccess() } }
    }

    private func track() {
        withObservationTracking { _ = controller.isActive; _ = controller.prefs.readScreen } onChange: { [weak self] in
            Task { @MainActor in self?.sync(); self?.track() }
        }
        sync()
    }

    func syncAccess() { controller.setPreviewAccess(grabber.isAllowed ? .allowed : .denied) }

    func sync() {
        if controller.isActive && controller.prefs.readScreen {
            syncAccess()
            if timer == nil { timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.capture() } }; capture() }
        } else {
            timer?.invalidate(); timer = nil; lastWords = ""; lastApp = ""; lastKey = ""; lastRead = .distantPast; controller.clearPreview()
        }
    }

    /// One capture. Exposed so tests can drive it without a timer.
    public func capture() {
        syncAccess()
        // On battery saver or when the Mac is hot, look a third as often.
        ticks += 1
        let p = ProcessInfo.processInfo
        if (p.isLowPowerModeEnabled || p.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue), ticks % 3 != 0 { return }
        guard grabber.isAllowed, controller.previewWanted, !busy else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            guard let g = await grabber.grab() else { return }
            let key = (controller.currentWindow?.title ?? "") + "|" + (controller.currentWindow?.url ?? "")
            let due = g.app != lastApp || key != lastKey || Date().timeIntervalSince(lastRead) >= readEvery
            if due {
                lastApp = g.app; lastKey = key; lastRead = Date()
                lastWords = await reader.words(in: g.image)
            }
            controller.setPreview(g.image, app: g.app, text: lastWords)
        }
    }
}
