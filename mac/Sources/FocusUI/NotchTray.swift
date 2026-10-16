import SwiftUI
import AppKit
import QuickLookThumbnailing
import Observation

/// A shelf in the notch for files you are working with (owner, 2026-10-14: "add a file tray", after Droppy). Drag a file onto the
/// notch to keep it here, drag it out to wherever it is going. Focus keeps only where each file is, in memory: nothing is copied,
/// moved, read or opened, and the shelf is empty again after Focus quits.
@MainActor @Observable
public final class NotchTray {
    public struct Item: Identifiable, Equatable {
        public let id = UUID()
        public let url: URL
        public var name: String { url.lastPathComponent }
    }

    public static let shared = NotchTray()
    public private(set) var items: [Item] = []
    /// Bumped on each drop, so the shelf can play its arrival.
    public private(set) var drops = 0
    /// The most a shelf holds; the oldest goes when a new one arrives.
    public static let limit = 12

    public init() {}

    public func add(_ urls: [URL]) {
        var seen = Set(items.map(\.url))
        let new = urls.filter { $0.isFileURL && seen.insert($0).inserted }.map { Item(url: $0) }
        guard !new.isEmpty else { return }
        items.append(contentsOf: new)
        if items.count > Self.limit { items.removeFirst(items.count - Self.limit) }
        drops += 1
    }

    public func remove(_ id: Item.ID) { items.removeAll { $0.id == id } }
    public func removeAll() { items.removeAll() }
}

/// The tray side of the open notch: a dashed drop zone when it is empty or a file is on its way, and the files themselves otherwise.
struct TrayColumn: View {
    @Bindable var tray: NotchTray
    var targeted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tray.items.isEmpty && !targeted { header.transition(.opacity) }
            ZStack {
                if tray.items.isEmpty || targeted {
                    DropZone(targeted: targeted).transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 4) {
                            ForEach(tray.items) { item in
                                TrayTile(item: item) { tray.remove(item.id) }
                                    .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.never)
                    .transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity)
            .motion(Motion.notchOpen, value: tray.items)
            .motion(Motion.notchPeek, value: targeted)
        }
    }

    var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.full.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(NotchView.ink2)
            Text("Tray · \(tray.items.count)").font(Tokens.text(12, .semibold)).foregroundStyle(NotchView.ink2)
                .contentTransition(.numericText()).motion(Motion.notchSettle, value: tray.items.count)
            Spacer(minLength: 0)
            Button("Clear") { tray.removeAll() }.buttonStyle(TrayChipStyle())
        }
    }
}

/// The empty shelf: a dashed outline that marches slowly, and brightens with the accent as a file comes over it.
private struct DropZone: View {
    var targeted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            let phase = reduceMotion ? 0 : CGFloat(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) * (targeted ? -28 : -8))
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(targeted ? NotchView.accent.opacity(0.12) : Color.white.opacity(0.03))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(targeted ? NotchView.accent : Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 7], dashPhase: phase))
                VStack(spacing: 5) {
                    Image(systemName: targeted ? "arrow.down.circle.fill" : "tray.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(targeted ? NotchView.accent : NotchView.ink2)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: targeted)
                    Text(targeted ? "Drop to keep it here" : "Tray").font(Tokens.text(13, .semibold))
                        .foregroundStyle(targeted ? NotchView.ink : NotchView.ink2)
                        .contentTransition(.interpolate)
                }
            }
        }
        .scaleEffect(targeted && !reduceMotion ? 1.02 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// One file on the shelf: its thumbnail and name. Drag it out to use it; hover shows a small button to take it off the shelf.
private struct TrayTile: View {
    let item: NotchTray.Item
    var remove: () -> Void
    @State private var hover = false
    @State private var thumb: NSImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: thumb ?? NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().aspectRatio(contentMode: .fit)
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            Text(item.name).font(Tokens.text(10.5, .medium)).foregroundStyle(NotchView.ink2)
                .lineLimit(1).truncationMode(.middle).frame(width: 64)
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(hover ? 0.1 : 0)))
        .overlay(alignment: .topTrailing) {
            if hover {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 16, height: 16).background(Circle().fill(Color.white.opacity(0.25)))
                        .frame(width: 24, height: 24).contentShape(Rectangle())   // the visible disc stays small; the target is not
                }
                .buttonStyle(.plain).transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Take \(item.name) off the tray")
            }
        }
        .scaleEffect(hover && !reduceMotion ? 1.05 : 1)
        .animation(Motion.notchPress, value: hover)
        .onHover { hover = $0 }
        .onDrag { NSItemProvider(object: item.url as NSURL) }
        .help(item.url.path)
        .task(id: item.url) { thumb = await Self.thumbnail(item.url) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.name)
    }

    /// A Quick Look picture of the file, drawn on this Mac. Falls back to its Finder icon.
    static func thumbnail(_ url: URL) async -> NSImage? {
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 80, height: 80), scale: 2, representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req).nsImage
    }
}

/// The small text buttons in the notch: quiet until the pointer is on them.
private struct TrayChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration) }
    struct Inner: View {
        let configuration: Configuration
        @State private var hover = false
        var body: some View {
            configuration.label.font(Tokens.text(11, .semibold)).foregroundStyle(NotchView.ink2)
                .padding(.horizontal, 8).frame(height: 20)
                .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.2 : (hover ? 0.12 : 0.06))))
                .animation(Motion.hover, value: hover)
                .onHover { hover = $0 }
        }
    }
}

/// A faint field of dots behind the open notch that light up around the pointer, so the surface answers your hand.
/// Only the dots near the pointer change; with Reduce Motion the field stays still.
struct DotField: View {
    var model: NotchModel
    /// Where the shape sits inside the panel, so the pointer (in panel points) can be turned into the field's own points.
    var origin: CGPoint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 9, row = spacing * 0.866
            let p = model.pointer.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) }
            let reach: CGFloat = 90
            var y: CGFloat = 0, r = 0
            while y < size.height + row {
                var x: CGFloat = r % 2 == 0 ? 0 : spacing / 2
                while x < size.width + spacing {
                    var glow: CGFloat = 0
                    if let p, !reduceMotion { let d = hypot(x - p.x, y - p.y); if d < reach { glow = 1 - d / reach } }
                    let rad = 0.7 + glow * 0.6
                    ctx.opacity = 0.05 + glow * 0.22
                    ctx.fill(Path(ellipseIn: CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2)), with: .color(.white))
                    x += spacing
                }
                y += row; r += 1
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
