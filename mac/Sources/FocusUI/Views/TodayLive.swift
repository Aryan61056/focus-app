import SwiftUI
import FocusBrain

// The pieces of Today while a session runs: what Focus is reading and why, at a glance.

/// The heart of the screen. The window Focus looked at, what it concluded and in one line why, how it got there, and a strip of the
/// recent readings you can tap to see the reason behind any one of them.
struct SeeingCard: View {
    @Bindable var c: SessionController
    @State private var pinned: UUID?
    @State private var showAll = false

    var shown: Reading? { pinned.flatMap { id in c.readings.first { $0.id == id } } ?? c.latest }

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let r = shown {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 18) {
                            windowLine(r)
                            verdict(r)
                            steps(r)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if c.prefs.readScreen { PreviewCard(c: c).frame(width: 250) }
                    }
                    if !c.prefs.readScreen { screenRow }
                    if c.readings.count > 1 {
                        ReadingsStrip(readings: c.readings, pinned: $pinned)
                        allReadings
                    }
                } else {
                    HStack(spacing: 12) {
                        RingView(.unsure, color: Tokens.ink).frame(width: 30, height: 30)
                        Text("Waiting for the first window. Switch to what you are working on.").font(Tokens.text(13.5)).foregroundStyle(Tokens.ink2)
                    }
                }
                Text("The model can be wrong. When it is not sure, Focus does nothing.").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
            }
        }
        .animation(.easeOut(duration: 0.2), value: shown?.id)
        .onChange(of: c.isActive) { _, on in if !on { pinned = nil } }
    }

    var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("What Focus is reading").font(Tokens.text(14, .semibold)).accessibilityAddTraits(.isHeader)
            if shown?.source == .model { AITag() }
            if c.isJudging { HStack(spacing: 6) { ThinkingDot(); Text("Reading now").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2) } }
            Spacer()
            if let r = shown {
                if pinned != nil {
                    Text("At \(r.date.formatted(.dateTime.hour().minute()))").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
                    Button("Back to now") { pinned = nil }.buttonStyle(FocusButtonStyle(.plain, small: true))
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(Self.ago(c.nowSeconds() - r.at)).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).monospacedDigit()
                    }
                }
            }
        }
    }
    static func ago(_ s: Double) -> String { s < 5 ? "Checked just now" : "Checked \(Int(s)) s ago" }

    func windowLine(_ r: Reading) -> some View {
        HStack(spacing: 12) {
            Text(String(r.appText.prefix(2))).font(Tokens.rounded(13, .semibold)).foregroundStyle(Tokens.ink2)
                .frame(width: 38, height: 38).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Tokens.control))
            VStack(alignment: .leading, spacing: 1) {
                Text(r.appText).font(Tokens.text(14, .semibold)).lineLimit(1)
                Text(r.titleText).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /// The call, large, with Focus's own one-line reason.
    func verdict(_ r: Reading) -> some View {
        HStack(alignment: .top, spacing: 16) {
            RingView(r.ring, color: r.tint).frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(r.label).font(Tokens.rounded(26, .semibold))
                Text(r.reason).font(Tokens.text(14)).foregroundStyle(Tokens.ink).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(r.call == .on ? Tokens.accentSoft : Tokens.control))
        .accessibilityElement(children: .combine)
    }

    /// Read, Compared, and the outcome: three labels on a line. The sentences live in the tooltips.
    func steps(_ r: Reading) -> some View {
        HStack(spacing: 8) {
            stepDot("Read", help: r.sawScreen ? "The app, window title, address and the words on screen." : "The app, the window title and the page or file it shows.", filled: false, r)
            connector
            stepDot("Compared", help: "With \u{201C}\(c.taskName)\u{201D} and what you wrote about it.", filled: false, r)
            connector
            stepDot(r.outcomeTitle, help: r.outcomeText, filled: true, r)
            Spacer(minLength: 0)
        }
    }
    var connector: some View { Capsule().fill(Tokens.track).frame(width: 18, height: 2) }
    func stepDot(_ title: String, help: String, filled: Bool, _ r: Reading) -> some View {
        HStack(spacing: 6) {
            Group {
                if filled {
                    switch r.call {
                    case .on: Circle().fill(Tokens.accent)
                    case .unsure: Circle().strokeBorder(Tokens.ink, style: StrokeStyle(lineWidth: 2, dash: [2, 2]))
                    case .off: Circle().strokeBorder(Tokens.ink, lineWidth: 2)
                    }
                } else { Circle().strokeBorder(Tokens.accent, lineWidth: 2) }
            }.frame(width: 12, height: 12)
            Text(title).font(Tokens.text(12.5, .semibold))
        }
        .help(help).accessibilityElement(children: .ignore).accessibilityLabel("\(title). \(help)")
    }

    var screenRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye").foregroundStyle(Tokens.ink2)
            Text("Screen reading is off. Turn it on and Focus also reads the words in the window.").font(Tokens.text(13)).foregroundStyle(Tokens.ink2)
                .help("It takes a picture of the front window, reads its words on this Mac and shows you the picture here. The model sees the words, not the picture, and nothing is saved.")
            Spacer(minLength: 8)
            Button("Turn on") { c.prefs.readScreen = true; c.onRequestPreviewAccess?() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
        }
    }

    var allReadings: some View {
        DisclosureGroup(isExpanded: $showAll) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(c.readings.prefix(12))) { r in
                    HStack(spacing: 10) {
                        Text(r.date.formatted(.dateTime.hour().minute())).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).monospacedDigit().frame(width: 56, alignment: .leading)
                        Text(r.appText).font(Tokens.text(13)).lineLimit(1).frame(width: 110, alignment: .leading)
                        HStack(spacing: 6) { RingView(r.ring, color: r.tint).frame(width: 14, height: 14); Text(r.label).font(Tokens.text(12.5, .semibold)) }.frame(width: 100, alignment: .leading)
                        Text(r.reason).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).lineLimit(1)
                        Spacer(minLength: 6)
                        if r.source == .rule { Text(r.byWords ? "Matching words" : "Your rule").font(Tokens.text(11.5)).foregroundStyle(Tokens.ink2).padding(.horizontal, 8).padding(.vertical, 1).overlay { Capsule().strokeBorder(Tokens.line) } }
                    }
                    .padding(.vertical, 7).contentShape(Rectangle()).onTapGesture { pinned = r.id }
                    Divider().overlay(Tokens.line)
                }
                Text("Kept only while this session runs.").font(Tokens.text(12)).foregroundStyle(Tokens.ink2).padding(.top, 8)
            }.padding(.top, 8)
        } label: {
            Text("All readings").font(Tokens.text(12.5, .semibold))
        }
    }
}

/// The last readings as a strip you can touch. Shape carries the call, not color: a tall solid bar is on task, a tall dashed one is not sure,
/// a short dark one is off topic. Tapping a bar shows the reason behind that reading in the card above.
struct ReadingsStrip: View {
    var readings: [Reading]
    @Binding var pinned: UUID?

    var body: some View {
        let items = Array(readings.prefix(30).reversed())
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent readings").font(Tokens.text(12.5, .semibold))
                Spacer()
                Text("Tap one to see why").font(Tokens.text(12)).foregroundStyle(Tokens.ink2)
            }
            HStack(alignment: .center, spacing: 4) {
                ForEach(items) { r in
                    let selected = (pinned ?? readings.first?.id) == r.id
                    Button { pinned = (r.id == readings.first?.id) ? nil : r.id } label: { bar(r, selected: selected) }
                        .buttonStyle(.plain)
                        .help("\(r.date.formatted(.dateTime.hour().minute())), \(r.appText), \(r.label)")
                        .accessibilityLabel("\(r.date.formatted(.dateTime.hour().minute())), \(r.appText), \(r.label)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            .frame(height: 30)
        }
    }

    @ViewBuilder func bar(_ r: Reading, selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        ZStack {
            switch r.call {
            case .on: shape.fill(Tokens.accent).frame(width: 9, height: 26)
            case .unsure: shape.strokeBorder(Tokens.ink2, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2])).frame(width: 9, height: 26)
            case .off: shape.fill(Tokens.ink.opacity(0.5)).frame(width: 9, height: 12)
            }
        }
        .frame(width: 13, height: 30)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(selected ? Tokens.control : .clear))
        .contentShape(Rectangle())
    }
}

/// How this session's readings split, as one bar and three counts. Shape-coded like the strip.
struct SessionTally: View {
    var stats: ReadStats
    var body: some View {
        Tile(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("This session").font(Tokens.text(14, .semibold)).accessibilityAddTraits(.isHeader)
                if stats.total == 0 {
                    Text("No readings yet.").font(Tokens.text(13)).foregroundStyle(Tokens.ink2)
                } else {
                    ReadingSplit(stats: stats)
                    VStack(spacing: 8) {
                        row(.on, "On task", stats.onTask)
                        row(.unsure, "Not sure", stats.unsure)
                        row(.drift, "Off topic", stats.offTask)
                    }
                }
            }
        }
    }
    func row(_ ring: RingState, _ label: String, _ n: Int) -> some View {
        HStack(spacing: 8) {
            RingView(ring, color: ring == .on ? Tokens.accent : Tokens.ink).frame(width: 14, height: 14)
            Text(label).font(Tokens.text(13))
            Spacer()
            Text("\(n)").font(Tokens.text(13, .semibold)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
