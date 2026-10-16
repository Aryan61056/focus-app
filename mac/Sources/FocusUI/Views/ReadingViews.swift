import SwiftUI
import FocusBrain

extension Reading {
    var label: String { switch call { case .on: return "On task"; case .unsure: return "Not sure"; case .off: return "Off topic" } }
    var ring: RingState { switch call { case .on: return .on; case .unsure: return .unsure; case .off: return .drift } }
    var tint: Color { call == .on ? Tokens.accent : Tokens.ink }
    var appText: String { source == .sensitive ? "Private window" : (app.isEmpty ? "A window" : app) }
    var titleText: String { source == .sensitive || source == .skipped ? "Not read" : title }
    /// Third step of "how Focus decided", in plain words.
    var outcomeTitle: String {
        if failed { return "Could not read it" }
        switch (source, call) {
        case (.sensitive, _): return "Skipped"
        case (.skipped, _): return "Not judged"
        case (.rule, _): return byWords ? "Words matched" : "Your rule decided"
        case (_, .on): return "Confident"
        case (_, .unsure): return "Not sure"
        case (_, .off): return "Two checks agree"
        }
    }
    var outcomeText: String {
        if failed { return "Treated as not sure. Focus does nothing." }
        switch (source, call) {
        case (.sensitive, _): return "Private windows are never read."
        case (.skipped, _): return "It is on your never-judged list, so Focus did not read it."
        case (.rule, _): return byWords ? "The model was not needed. This is quiet by design: a match can only make Focus say less." : "A rule you set applies, so the model was not needed."
        case (_, .on): return "It matches the task. Nothing to do."
        case (_, .unsure): return "Focus waits and does nothing."
        case (_, .off): return "Focus keeps watching. It speaks up only if this lasts."
        }
    }
}

/// Three outcomes as a proportional bar, shape-coded so color is never the only signal.
struct ReadingSplit: View {
    var stats: ReadStats
    var body: some View {
        let t = max(stats.total, 1)
        GeometryReader { g in
            HStack(spacing: 3) {
                bar(Tokens.accent, stats.onTask, t, g.size.width)
                bar(Tokens.ink2.opacity(0.55), stats.unsure, t, g.size.width)
                bar(Tokens.ink.opacity(0.25), stats.offTask, t, g.size.width)
            }
        }.frame(height: 12).accessibilityElement().accessibilityLabel("\(stats.total) readings: \(stats.onTask) on task, \(stats.unsure) not sure, \(stats.offTask) off topic")
    }
    @ViewBuilder func bar(_ color: Color, _ n: Int, _ t: Int, _ w: CGFloat) -> some View {
        if n > 0 { RoundedRectangle(cornerRadius: Tokens.radiusTiny).fill(color).frame(width: max(4, w * CGFloat(n) / CGFloat(t) - 3)) }
    }
}


/// The picture Focus took of the window it is reading, large, in a fixed frame so the card does not jump as pictures arrive.
/// Every state fills the same frame: the picture, a reason it is not shown, or an invitation to turn screen reading on.
/// The model never sees this picture: it reads the app, the window title and the page or file address, plus the words if screen reading is on.
struct PreviewCard: View {
    @Bindable var c: SessionController

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Color.clear.aspectRatio(16 / 10, contentMode: .fit).frame(maxWidth: .infinity).overlay { frame }
            caption
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous) }

    @ViewBuilder var frame: some View {
        if c.prefs.readScreen, c.previewHeld == nil, c.previewAccess != .denied, let f = c.previewFrame {
            ZStack(alignment: .bottomLeading) {
                Color.black.opacity(0.04)
                Image(decorative: f.image, scale: 2).resizable().aspectRatio(contentMode: .fit)
                Label("Live", systemImage: "circle.fill").font(Tokens.text(.caption2, .semibold)).labelStyle(.titleAndIcon)
                    .symbolRenderingMode(.palette).foregroundStyle(.white, Tokens.accent)
                    .padding(.horizontal, Space.xs).frame(height: 22).background(Capsule().fill(.black.opacity(0.55))).padding(Space.s)
                    .accessibilityHidden(true)
            }
            .clipShape(shape).overlay(shape.strokeBorder(Tokens.line))
            .accessibilityElement().accessibilityLabel("Picture of the \(f.app) window, taken on this Mac")
            .id(f.id).transition(.opacity)
        } else {
            VStack(spacing: Space.s) {
                Image(systemName: symbol).font(.system(size: 22, weight: .medium)).foregroundStyle(Tokens.ink2)
                Text(message).font(Tokens.text(.body)).foregroundStyle(Tokens.ink2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300)
                if !c.prefs.readScreen {
                    Button("Show the window here") { c.prefs.readScreen = true; c.onRequestPreviewAccess?() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                } else if c.previewAccess == .denied {
                    Button("Open System Settings") { c.onRequestPreviewAccess?() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                }
            }
            .padding(Space.l).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shape.fill(Tokens.well))
            .overlay(shape.strokeBorder(Tokens.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
    }

    var symbol: String {
        if !c.prefs.readScreen { return "eye" }
        if c.previewHeld != nil { return "eye.slash" }
        if c.previewAccess == .denied { return "lock" }
        return "photo"
    }
    var message: String {
        if !c.prefs.readScreen { return "Let Focus show you the window it is reading. It also reads the words on screen to judge. Nothing is saved." }
        if let held = c.previewHeld { return held }
        if c.previewAccess == .denied { return "Allow Screen Recording for Focus in System Settings so it can look at the window." }
        return "Waiting for a picture. Switch to a window and it appears here."
    }

    @ViewBuilder var caption: some View {
        if c.prefs.readScreen {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(c.previewFrame == nil || c.screenText.isEmpty ? "The model sees the words, never the picture. Nothing is saved."
                     : "Read \(c.screenWordCount) words on this Mac. The model sees the words, never the picture. Gone when the session ends.")
                    .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Turn off") { c.prefs.readScreen = false }.buttonStyle(FocusButtonStyle(.plain, small: true))
            }
            if !c.screenText.isEmpty, c.previewFrame != nil {
                DisclosureGroup("Words Focus read") {
                    Text(String(c.screenText.prefix(600)).replacingOccurrences(of: "\n", with: " "))
                        .font(Tokens.text(.caption2)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }.font(Tokens.text(.caption))
            }
        }
    }

    func note(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.xs) {
            Image(systemName: symbol).foregroundStyle(Tokens.ink2)
            Text(text).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Screen reading is off: one quiet line offering it, instead of an empty frame where a picture would be.
struct PreviewOffer: View {
    @Bindable var c: SessionController
    var body: some View {
        Inset(padding: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: "eye").font(Tokens.symbol(14)).foregroundStyle(Tokens.ink2).accessibilityHidden(true)
                Text("Focus can also show the window it reads and use the words on it. Nothing is saved.")
                    .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s)
                Button("Show the window here") { c.prefs.readScreen = true; c.onRequestPreviewAccess?() }.buttonStyle(FocusButtonStyle(.secondary, small: true)).fixedSize()
            }
        }
    }
}
