import SwiftUI
import FocusLinkNet

/// A soft glow behind the ring that changes with the state. It is what gives the glass something to bend.
struct Backdrop: View {
    var phase: SessionState.Phase
    var body: some View {
        ZStack {
            Palette.canvas
            RadialGradient(colors: [phase.tint.opacity(phase == .idle ? 0.10 : 0.22), .clear], center: .init(x: 0.5, y: 0.34), startRadius: 10, endRadius: 380)
        }
        .motion(Motion.follow, value: phase)
        .ignoresSafeArea()
    }
}
