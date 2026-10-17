import SwiftUI
import AppKit

// Where "Back to task" goes, shown without words where it can be: the app's own icon, and a short name beside it.

enum PlaceIcon {
    /// The icon of a running app, by the name Focus read it under. Nil when it is not running (then a plain window glyph stands in).
    @MainActor static func image(for app: String) -> NSImage? {
        NSWorkspace.shared.runningApplications.first { $0.localizedName == app && $0.activationPolicy == .regular }?.icon
    }
}

struct PlaceMark: View {
    var app: String
    var size: CGFloat = 16
    var body: some View {
        Group {
            if let icon = PlaceIcon.image(for: app) { Image(nsImage: icon).resizable().interpolation(.high) }
            else { Image(systemName: "macwindow").font(.system(size: size * 0.7, weight: .regular)).foregroundStyle(Tokens.ink2) }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Says where "Back to task" goes, in the tooltip and to VoiceOver. Nothing is added when there is no place yet.
    @ViewBuilder func goesTo(_ place: TaskPlace?) -> some View {
        if let place { self.help("Goes to \(place.label)").accessibilityHint("Goes to \(place.label)") } else { self }
    }
}

/// The Back to task row of the menu bar: the way back, and where it lands.
struct BackToTaskRow: View {
    @Bindable var c: SessionController
    var body: some View {
        Button { c.act(.backToTask) } label: {
            HStack(spacing: 8) {
                Text("Back to task")
                Spacer(minLength: 6)
                if let p = c.returnPlace {
                    PlaceMark(app: p.window.app, size: 16)
                    Text(TaskPlaces.shortName(p.window).isEmpty ? p.window.app : TaskPlaces.shortName(p.window))
                        .font(Tokens.fixed(.caption, .regular)).foregroundStyle(Tokens.ink2).lineLimit(1).truncationMode(.tail).frame(maxWidth: 110, alignment: .trailing)
                }
            }
            .padding(.horizontal, 10).frame(height: 30).contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle()).font(Tokens.fixed(.body, .regular))
        .goesTo(c.returnPlace)
    }
}

/// Other places you worked in: one row each, the app's icon and its name, a click goes there instead.
struct OtherPlacesRows: View {
    @Bindable var c: SessionController
    var body: some View {
        ForEach(c.otherPlaces) { p in
            Button { c.goTo(p) } label: {
                HStack(spacing: 8) {
                    // The elbow says it is another way to do what the row above does.
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Tokens.ink2).frame(width: 12).accessibilityHidden(true)
                    PlaceMark(app: p.window.app, size: 16)
                    Text(p.label).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 10).padding(.trailing, 10).frame(height: 28).contentShape(Rectangle())
            }
            .buttonStyle(MenuRowStyle()).font(Tokens.fixed(.callout, .regular)).foregroundStyle(Tokens.ink2)
            .help("Go to \(p.label) instead")
            .accessibilityLabel("Go to \(p.label) instead")
        }
    }
}
