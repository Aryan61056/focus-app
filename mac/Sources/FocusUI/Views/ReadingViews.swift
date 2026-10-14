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
        if n > 0 { RoundedRectangle(cornerRadius: 4).fill(color).frame(width: max(4, w * CGFloat(n) / CGFloat(t) - 3)) }
    }
}


/// The picture Focus took of the window it is reading, with plain words about what it is for.
/// The model never sees this picture: it reads the app, the window title and the page or file address.
struct PreviewCard: View {
    @Bindable var c: SessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !c.prefs.readScreen {
                Text("Let Focus look at the window. It reads the words on screen to judge, and shows you the picture here. Nothing is saved.").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                Button("Turn on screen reading") { c.prefs.readScreen = true; c.onRequestPreviewAccess?() }.buttonStyle(FocusButtonStyle(.plain, small: true))
            } else if let held = c.previewHeld {
                note("eye.slash", held)
            } else if c.previewAccess == .denied {
                note("lock", "Allow Screen Recording for Focus in System Settings so it can look at the window.")
                Button("Open System Settings") { c.onRequestPreviewAccess?() }.buttonStyle(FocusButtonStyle(.plain, small: true))
            } else if let f = c.previewFrame {
                Image(decorative: f.image, scale: 2).resizable().aspectRatio(CGFloat(f.image.width) / CGFloat(max(1, f.image.height)), contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Tokens.line))
                    .accessibilityLabel("Picture of the \(f.app) window")
                Text(c.screenText.isEmpty ? "Reading the words in this picture on your Mac."
                     : "Read \(c.screenWordCount) words on this Mac. The model sees the words, not the picture. Nothing is saved, and it is gone when the session ends.")
                    .font(Tokens.text(11.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                if !c.screenText.isEmpty {
                    DisclosureGroup("Words Focus read") {
                        Text(String(c.screenText.prefix(600)).replacingOccurrences(of: "\n", with: " "))
                            .font(Tokens.text(11.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }.font(Tokens.text(12))
                }
            } else {
                note("photo", "Waiting for a picture. Switch to a window and it appears here.")
            }
            if c.prefs.readScreen { Button("Turn screen reading off") { c.prefs.readScreen = false }.buttonStyle(FocusButtonStyle(.plain, small: true)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func note(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Tokens.ink2)
            Text(text).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }
}
