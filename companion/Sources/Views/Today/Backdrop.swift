import SwiftUI
import FocusLinkNet

/// The plain canvas. (The soft glow behind the ring went with the Workspace look: the state is drawn by the ring's shape.)
struct Backdrop: View {
    var phase: SessionState.Phase
    var body: some View { Palette.canvas.ignoresSafeArea() }
}
