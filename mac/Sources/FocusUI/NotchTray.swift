import SwiftUI
import AppKit
import QuickLookThumbnailing
import Observation

/// A shelf in the notch for files you are working with (owner, 2026-10-14: "add a file tray", after Droppy). Drag a file onto the
/// notch to keep it here, drag it out to wherever it is going. Hushd keeps only where each file is, in memory: nothing is copied,
/// moved, read or opened, and the shelf is empty again after Hushd quits.
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
        ZStack {
            if tray.items.isEmpty || targeted {
                DropZone(targeted: targeted).transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(tray.items) { item in
                            TrayTile(item: item) { tray.remove(item.id) }
                                .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                        }
                        // Clearing the shelf is the last tile, so the page needs no header line of its own.
                        Button { tray.removeAll() } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(NotchView.ink2)
                                .frame(width: 28, height: 28).background(Circle().fill(Color.white.opacity(0.08)))
                                .frame(width: 44, height: 60).contentShape(Rectangle())
                        }
                        .buttonStyle(ShelfIconStyle())
                        .help("Clear the tray")
                        .accessibilityLabel("Clear the tray")
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

/// The empty shelf: a dashed outline that marches, and brightens with the accent as a file comes over it.
private struct DropZone: View {
    var targeted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        // The dashes march only while a file is over the zone; an empty tray stands still, so an open notch costs no frames.
        TimelineView(.animation(paused: reduceMotion || !targeted)) { ctx in
            let phase = reduceMotion || !targeted ? 0 : CGFloat(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) * -28)
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(targeted ? NotchView.accent.opacity(0.12) : Color.white.opacity(0.03))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(targeted ? NotchView.accent : Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 7], dashPhase: phase))
                HStack(spacing: 7) {
                    Image(systemName: targeted ? "arrow.down.circle.fill" : "tray")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(targeted ? NotchView.accent : NotchView.ink2)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: targeted)
                    Text(targeted ? "Drop to keep it" : "Drop files here").font(Tokens.fixed(.caption, .semibold))
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
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            Text(item.name).font(Tokens.fixed(.caption2, .medium)).foregroundStyle(NotchView.ink2)
                .lineLimit(1).truncationMode(.middle).frame(width: 56)
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
                .buttonStyle(.plain).transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
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

/// The tray as an open-card page: padded to sit between the shoulders and clear of the rounded foot, and risen in like the home page.
struct TrayPage: View {
    @Bindable var tray: NotchTray
    var targeted: Bool
    @State private var arrived = false
    var body: some View {
        TrayColumn(tray: tray, targeted: targeted)
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 30)
            .rise(0, arrived)
            .onAppear { DispatchQueue.main.async { arrived = true } }
            .onDisappear { arrived = false }
    }
}
