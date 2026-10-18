import SwiftUI

/// Light catching the top edge of a black pill, so it reads as a solid object sitting on the art.
enum PillEdge {
    static let gradient = LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.03), .clear], startPoint: .top, endPoint: .bottom)
}

/// A slimmer banner for a page: the same halftone art with the one number the page is about on a black pill, so each page says where
/// you are at a glance. The ripple plays once per launch, so coming back to a page is quiet.
struct PageBanner: View {
    var key: String
    var symbol: String
    var text: String
    var detail: String?
    var phase: Double
    var body: some View {
        ZStack {
            Halftone(pattern: .ridge(phase: phase), ripple: .oncePerLaunch(key))
            HStack(spacing: Space.s) {
                Image(systemName: symbol).font(Tokens.symbol(15, .semibold)).foregroundStyle(NotchView.accent)
                    .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.08)))
                Text(text).font(Tokens.text(.headline, .semibold)).foregroundStyle(NotchView.ink).contentTransition(.interpolate)
                if let detail {
                    Text(detail).font(Tokens.text(.callout, .medium)).foregroundStyle(NotchView.ink2).lineLimit(1)
                }
            }
            .padding(.leading, Space.xs).padding(.trailing, Space.l).frame(height: 52)
            .background(Capsule().fill(.black))
            .overlay { Capsule().strokeBorder(PillEdge.gradient, lineWidth: 1) }
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .motion(Motion.notchSettle, value: text)
        }
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous).strokeBorder(Color.white.opacity(0.08)) }
        .accessibilityElement(children: .combine)
    }
}
