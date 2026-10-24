import SwiftUI

struct UnpairedView: View {
    @Environment(AppModel.self) private var model
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            FocusRing(phase: .idle, progress: nil, lineWidth: 10)
                .frame(width: 150, height: 150)
                .padding(.top, 36)
                .reveal(0, key: "unpaired")
            VStack(spacing: 10) {
                Text("Hushd for iPhone").font(.largeTitle.weight(.bold))
                Text("See your Mac's session at a glance, start and pause it from here, and keep your phone honest while you work.")
                    .font(.body).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
            }
            .reveal(1, key: "unpaired")
            VStack(spacing: 12) {
                PrimaryButton(title: "Add your Mac", systemImage: "macbook.and.iphone", action: onAdd)
                Text("On your Mac, open Hushd and click Connect your iPhone in the sidebar.")
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
