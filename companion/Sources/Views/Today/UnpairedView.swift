import SwiftUI

struct UnpairedView: View {
    @Environment(AppModel.self) private var model
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            // The app icon's ring on the Mac's halftone art: the first thing a new user sees, so it gets the full arrival ripple.
            HeroBanner(key: "unpaired", height: 232) {
                ZStack {
                    Circle().fill(.black).frame(width: 104, height: 104)
                        .overlay { Circle().strokeBorder(PillEdge.gradient, lineWidth: 1) }
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 7)
                    FocusRing(phase: .onTask, progress: nil, lineWidth: 8, onDark: true).frame(width: 66, height: 66)
                }
            }
            .padding(.top, 8)
            .reveal(0, key: "unpaired")
            VStack(spacing: 10) {
                Text("Focus for iPhone").font(.largeTitle.weight(.bold))
                Text("See your Mac's session at a glance, start and pause it from here, and keep your phone honest while you work.")
                    .font(.body).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
            }
            .reveal(1, key: "unpaired")
            VStack(spacing: 12) {
                PrimaryButton(title: "Add your Mac", systemImage: "macbook.and.iphone", action: onAdd)
                Text("On your Mac, open Focus and click Connect your iPhone in the sidebar.")
                    .font(.footnote).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
                Button("Try a demo") { model.startDemo() }
                    .font(.body.weight(.medium)).foregroundStyle(Palette.ink2)
                    .frame(minHeight: 44)
            }
            .padding(.top, 8)
            .reveal(2, key: "unpaired")
        }
        .frame(maxWidth: 520)
    }
}
