import SwiftUI

/// "Connect your iPhone", always in view at the foot of the sidebar. Until a phone is paired it is the one call to action in the
/// sidebar; afterwards it says whether the phone is connected right now. One click opens the pairing window.
struct PhoneConnectCard: View {
    @Bindable var c: SessionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String {
        switch c.phoneState {
        case .none: return "Connect your iPhone"
        case .paired: return "Your iPhone"
        case .connected: return "iPhone connected"
        }
    }
    private var detail: String {
        switch c.phoneState {
        case .none: return "Scan a code. About ten seconds."
        case .paired(let n): return n == 1 ? "Paired, not connected now" : "\(n) paired, none connected now"
        case .connected(let name): return name
        }
    }
    private var tile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Tokens.accentSoft)
            PhoneGlyph(adding: c.phoneState == .none)
        }
        .frame(width: 34, height: 34)
    }
    private var live: Bool { if case .connected = c.phoneState { return true } else { return false } }

    var body: some View {
        Button { c.onOpenPhone?() } label: {
            // Full card when the sidebar is wide enough; just the icon tile when it is squeezed, so the words never wrap letter by letter.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    tile
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(title).font(Tokens.text(.body, .semibold)).foregroundStyle(Tokens.ink).lineLimit(1)
                            if live { Circle().fill(Tokens.accent).frame(width: 7, height: 7).transition(.scale.combined(with: .opacity)) }
                        }
                        Text(detail).font(Tokens.text(.caption2)).foregroundStyle(Tokens.ink2).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Tokens.ink2.opacity(0.7))
                }
                .fixedSize(horizontal: true, vertical: false)
                // Squeezed sidebar: the tile with a one-word label.
                HStack(spacing: 6) {
                    tile.scaleEffect(0.82).frame(width: 28, height: 28)
                    Text(c.phoneState == .none ? "Add iPhone" : "iPhone").font(Tokens.text(.caption, .semibold)).foregroundStyle(Tokens.ink).lineLimit(1)
                    if live { Circle().fill(Tokens.accent).frame(width: 6, height: 6) }
                }
                .fixedSize(horizontal: true, vertical: false)
                tile.frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8).padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .glassSurface(RoundedRectangle(cornerRadius: 12, style: .continuous), interactive: true)
        }
        .buttonStyle(PhoneCardPress())
        .motion(Motion.notchSettle, value: c.phoneState)
        .help("Pair this Mac with the Focus app on your iPhone")
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityHint("Opens iPhone pairing")
    }
}

/// Press feedback from the first moment of contact, springing back on release.
private struct PhoneCardPress: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(Motion.notchPress, value: configuration.isPressed)
    }
}

/// A phone, with a small plus when none is paired yet. (There is no single SF Symbol for it that exists on every macOS we support.)
struct PhoneGlyph: View {
    var adding: Bool
    var size: CGFloat = 15
    var body: some View {
        Image(systemName: "iphone").font(.system(size: size, weight: .semibold)).foregroundStyle(Tokens.accentInk)
            .overlay(alignment: .topTrailing) {
                if adding { Image(systemName: "plus").font(.system(size: size * 0.5, weight: .heavy)).foregroundStyle(Tokens.accentInk).offset(x: size * 0.4, y: -size * 0.3) }
            }
    }
}
