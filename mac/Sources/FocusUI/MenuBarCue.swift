import SwiftUI
import AppKit
import Observation

/// The menu bar ring with its cue: plain, a warm tint for a heads-up or a prompt, a warm tint that pulses slowly while you are away.
/// The pulse stops under Reduce Motion, and the ring's shape is the same either way.
@MainActor @Observable
public final class CueClock {
    public private(set) var dim = false
    private let c: SessionController
    private var timer: Timer?
    public init(controller: SessionController) { self.c = controller }
    public func start() { track() }
    private func track() {
        withObservationTracking { _ = c.menuCue } onChange: { [weak self] in Task { @MainActor in self?.sync(); self?.track() } }
        sync()
    }
    func sync() {
        if c.menuCue == .away, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if timer == nil { timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.dim.toggle() } } }
        } else { timer?.invalidate(); timer = nil; dim = false }
    }
}

public struct MenuBarLabel: View {
    @Bindable var c: SessionController
    var clock: CueClock
    public init(controller: SessionController, clock: CueClock) { self.c = controller; self.clock = clock }
    public var body: some View {
        switch c.menuCue {
        case .none: Image(nsImage: RingImage.make(c.ringState))
        case .headsUp: Image(nsImage: RingImage.make(c.ringState, tint: RingImage.warm))
        case .away: Image(nsImage: RingImage.make(c.ringState, tint: RingImage.warm.withAlphaComponent(clock.dim ? 0.35 : 1)))
        }
    }
}
