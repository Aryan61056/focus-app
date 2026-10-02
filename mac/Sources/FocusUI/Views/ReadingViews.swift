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
        case (.rule, _): return "Your rule decided"
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
        case (.rule, _): return "A rule you set applies, so the model was not needed."
        case (_, .on): return "It matches the task. Nothing to do."
        case (_, .unsure): return "Focus waits and does nothing."
        case (_, .off): return "Focus keeps watching. It speaks up only if this lasts."
        }
    }
}

/// The product's centrepiece while a session runs: what Focus sees, what it concluded and why.
struct ReadingPanel: View {
    @Bindable var c: SessionController

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("What Focus is reading").font(Tokens.text(15, .semibold)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    if let r = c.latest {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(ago(c.nowSeconds() - r.at)).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).monospacedDigit()
                        }
                    }
                }
                if let r = c.latest {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 12) { seen(r); PreviewCard(c: c) }.frame(width: 290)
                        verdict(r)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    steps(r)
                    if c.readings.count > 1 { recent }
                } else {
                    HStack(spacing: 12) {
                        RingView(.unsure, color: Tokens.ink).frame(width: 30, height: 30)
                        Text("Waiting for the first window. Switch to what you are working on and Focus reads it.").font(Tokens.text(13.5)).foregroundStyle(Tokens.ink2)
                    }
                }
                Text("Focus uses Apple's on-device model, and it can be wrong. When it is not sure it does nothing. It speaks up only after two checks agree and the drift lasts.")
                    .font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func ago(_ s: Double) -> String { s < 5 ? "Checked just now" : "Checked \(Int(s)) seconds ago" }

    func seen(_ r: Reading) -> some View {
        HStack(spacing: 12) {
            Text(String(r.appText.prefix(2))).font(Tokens.rounded(13, .semibold)).foregroundStyle(Tokens.ink2)
                .frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: 9).fill(Tokens.control))
            VStack(alignment: .leading, spacing: 1) {
                Text(r.appText).font(Tokens.text(14, .semibold)).lineLimit(1)
                Text(r.titleText).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Tokens.window2))
    }

    func verdict(_ r: Reading) -> some View {
        HStack(alignment: .center, spacing: 14) {
            RingView(r.ring, color: r.tint).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(r.label).font(Tokens.rounded(20, .semibold))
                Text(r.reason).font(Tokens.text(13.5)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(r.call == .on ? Tokens.accentSoft : Tokens.control))
        .accessibilityElement(children: .combine)
    }

    func steps(_ r: Reading) -> some View {
        HStack(alignment: .top, spacing: 0) {
            step("Read", r.sawScreen ? "The app, window title, address and the words on screen" : "The app, the window title and the page or file it shows", filled: false, r)
            step("Compared", "With \u{201C}\(c.taskName)\u{201D} and what you wrote about it", filled: false, r)
            step(r.outcomeTitle, r.outcomeText, filled: true, r)
        }
    }

    func step(_ title: String, _ text: String, filled: Bool, _ r: Reading) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if filled {
                    switch r.call {
                    case .on: Circle().fill(Tokens.accent)
                    case .unsure: Circle().strokeBorder(Tokens.ink, style: StrokeStyle(lineWidth: 2, dash: [2, 2]))
                    case .off: Circle().strokeBorder(Tokens.ink, lineWidth: 2)
                    }
                } else { Circle().strokeBorder(Tokens.accent, lineWidth: 2) }
            }.frame(width: 14, height: 14).padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Tokens.text(13, .semibold))
                Text(text).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 12)
        .accessibilityElement(children: .combine)
    }

    var recent: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text("Recent readings").font(Tokens.text(12.5, .semibold)); Spacer(); Text("Kept only while this session runs").font(Tokens.text(12)).foregroundStyle(Tokens.ink2) }
                .padding(.bottom, 4)
            ForEach(Array(c.readings.dropFirst().prefix(5))) { r in
                HStack(spacing: 10) {
                    Text(r.date.formatted(.dateTime.hour().minute())).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).monospacedDigit().frame(width: 50, alignment: .leading)
                    Text(r.appText).font(Tokens.text(13)).lineLimit(1).frame(width: 110, alignment: .leading)
                    HStack(spacing: 6) { RingView(r.ring, color: r.tint).frame(width: 14, height: 14); Text(r.label).font(Tokens.text(12.5, .semibold)) }.frame(width: 104, alignment: .leading)
                    Text(r.reason).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).lineLimit(1)
                    Spacer(minLength: 6)
                    if r.source == .rule { Text("Your rule").font(Tokens.text(11.5)).foregroundStyle(Tokens.ink2).padding(.horizontal, 8).padding(.vertical, 1).overlay { Capsule().strokeBorder(Tokens.line) } }
                }
                .padding(.vertical, 6)
                Divider().overlay(Tokens.line)
            }
        }
    }
}

/// Before a session: say what the AI does, in three steps, with the honest limit.
struct HowFocusDecides: View {
    var body: some View {
        Panel(tinted: true) {
            VStack(alignment: .leading, spacing: 14) {
                Text("How Focus decides").font(Tokens.text(15, .semibold)).accessibilityAddTraits(.isHeader)
                HStack(alignment: .top, spacing: 18) {
                    item("1", "It reads the window", "The app, the window title and the page or file address, on this Mac. Never a recording.")
                    item("2", "It compares with your task", "Plus what you wrote about the project. It judges meaning, so it does not need a list of sites.")
                    item("3", "It waits to be sure", "On task, not sure or off topic. Not sure does nothing, and a nudge needs two checks that agree and a drift that lasts.")
                }
                Text("It runs on Apple's on-device model and can be wrong. Rules you set are optional and only add certainty.").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
            }
        }
    }
    func item(_ n: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(n).font(Tokens.rounded(12, .semibold)).foregroundStyle(Tokens.ink2).frame(width: 20, height: 20).overlay { Circle().strokeBorder(Tokens.line) }
            Text(title).font(Tokens.text(13.5, .semibold))
            Text(text).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
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
                Text(c.screenText.isEmpty ? "Focus is reading the words in this picture on your Mac."
                     : "Focus read \(c.screenWordCount) words from this picture on your Mac and compares them with the task. The model sees the words, not the picture. Nothing is saved or sent anywhere, and it is gone when the session ends.")
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
