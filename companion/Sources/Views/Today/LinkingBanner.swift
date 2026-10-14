import SwiftUI

/// Says what is happening after the Camera app opens a pairing link, then gets out of the way.
struct LinkingBanner: View {
    @Environment(AppModel.self) private var model

    private var content: (text: String, symbol: String, busy: Bool)? {
        switch model.linking {
        case .idle: nil
        case .working(let t): (t, "macbook.and.iphone", true)
        case .done(let name): (String(localized: "Paired with \(name)"), "checkmark.circle.fill", false)
        case .failed(let why): (why, "exclamationmark.circle", false)
        }
    }

    var body: some View {
        Group {
            if let c = content {
                HStack(spacing: 10) {
                    if c.busy { ProgressView() } else { Image(systemName: c.symbol).foregroundStyle(Palette.accent).symbolRenderingMode(.hierarchical) }
                    Text(c.text).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, Metrics.gutter)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
        }
        .motion(Motion.land, value: model.linking)
    }
}
