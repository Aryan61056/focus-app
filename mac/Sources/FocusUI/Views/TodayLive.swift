import SwiftUI
import FocusBrain

// The pieces of Today while a session runs: what Focus is reading and why, at a glance.

/// The heart of the screen. The window Focus looked at, what it concluded and in one line why, how it got there, and a strip of the
/// recent readings you can tap to see the reason behind any one of them.
struct SeeingCard: View {
    @Bindable var c: SessionController
    @State private var pinned: UUID?
    @State private var showAll = false
    @State private var width: CGFloat = 800

    var shown: Reading? { pinned.flatMap { id in c.readings.first { $0.id == id } } ?? c.latest }

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: Space.l) {
                header
                if c.isHeld {
                    // Paused, on a break, in a call, away: nothing is being read, so the last reading is not shown as if it were current.
                    HStack(spacing: Space.s) {
                        RingView(.paused, color: Tokens.ink).frame(width: 30, height: 30)
                        Text(c.heldLine).font(Tokens.text(.body)).foregroundStyle(Tokens.ink2)
                    }
                } else if let r = shown {
                    // The picture sits beside the call when there is room, so you see what Focus saw and what it concluded together.
                    // With screen reading off there is no picture to show, so the decision gets the whole card and the offer is one line.
                    if !c.prefs.readScreen {
                        decision(r)
                        if pinned == nil { PreviewOffer(c: c) }
                    } else if width >= 720 {
                        HStack(alignment: .top, spacing: Space.xl) {
                            decision(r).frame(maxWidth: .infinity, alignment: .leading)
                            if pinned == nil { PreviewCard(c: c).frame(width: min(440, width * 0.46)) }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: Space.l) {
                            decision(r)
                            if pinned == nil { PreviewCard(c: c) }
                        }
                    }
                    if c.readings.count > 1 {
                        ReadingsStrip(readings: c.readings, pinned: $pinned)
                        allReadings
                    }
                } else {
                    HStack(spacing: Space.s) {
                        RingView(.unsure, color: Tokens.ink).frame(width: 30, height: 30)
                        Text("Waiting for the first window. Switch to what you are working on.").font(Tokens.text(.body)).foregroundStyle(Tokens.ink2)
                    }
                }
                Text("The model can be wrong. When it is not sure, Focus does nothing.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
            }
        }
        .animation(.easeOut(duration: 0.2), value: shown?.id)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: c.isActive) { _, on in if !on { pinned = nil } }
    }

    var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text("What Focus is reading").font(Tokens.text(.callout, .semibold)).accessibilityAddTraits(.isHeader)
            if shown?.source == .model { AITag() }
            if c.isJudging { HStack(spacing: Space.xs) { ThinkingDot(); Text("Reading now").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2) } }
            Spacer()
            if let r = shown {
                if pinned != nil {
                    Text("At \(r.date.formatted(.dateTime.hour().minute()))").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                    Button("Back to now") { pinned = nil }.buttonStyle(FocusButtonStyle(.plain, small: true))
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(Self.ago(c.nowSeconds() - r.at)).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).monospacedDigit()
                    }
                }
            }
        }
    }
    func decision(_ r: Reading) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            windowLine(r)
            verdict(r)
            steps(r)
        }
    }

    static func ago(_ s: Double) -> String { s < 5 ? "Checked just now" : "Checked \(Int(s)) s ago" }

    func windowLine(_ r: Reading) -> some View {
        HStack(spacing: Space.s) {
            AppIcon(name: r.source == .sensitive ? "Private window" : r.app, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.appText).font(Tokens.text(.callout, .semibold)).lineLimit(1)
                Text(r.titleText).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /// The call, large, with Focus's own one-line reason.
    func verdict(_ r: Reading) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            RingView(r.ring, color: r.tint).frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(r.label).font(Tokens.rounded(.title2, .semibold))
                Text(r.reason).font(Tokens.text(.callout)).foregroundStyle(Tokens.ink).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.l).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(r.call == .on ? Tokens.accentSoft : Tokens.control))
        .accessibilityElement(children: .combine)
    }

    /// Read, Compared, and the outcome: three labels on a line. The sentences live in the tooltips.
    func steps(_ r: Reading) -> some View {
        // On one line when it fits; stacked when the card is narrow or the text is large. A label never breaks in the middle.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.xs) {
                stepDot("Read", help: readHelp(r), filled: false, r)
                connector
                stepDot("Compared", help: compareHelp, filled: false, r)
                connector
                stepDot(r.outcomeTitle, help: r.outcomeText, filled: true, r)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                stepDot("Read", help: readHelp(r), filled: false, r)
                stepDot("Compared", help: compareHelp, filled: false, r)
                stepDot(r.outcomeTitle, help: r.outcomeText, filled: true, r)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    func readHelp(_ r: Reading) -> String { r.sawScreen ? "The app, window title, address and the words on screen." : "The app, the window title and the page or file it shows." }
    var compareHelp: String { "With \u{201C}\(c.taskName)\u{201D} and what you wrote about it." }
    var connector: some View { Capsule().fill(Tokens.track).frame(width: 18, height: 2) }
    func stepDot(_ title: String, help: String, filled: Bool, _ r: Reading) -> some View {
        HStack(spacing: Space.xs) {
            Group {
                if filled {
                    switch r.call {
                    case .on: Circle().fill(Tokens.accent)
                    case .unsure: Circle().strokeBorder(Tokens.ink, style: StrokeStyle(lineWidth: 2, dash: [2, 2]))
                    case .off: Circle().strokeBorder(Tokens.ink, lineWidth: 2)
                    }
                } else { Circle().strokeBorder(Tokens.accent, lineWidth: 2) }
            }.frame(width: 12, height: 12)
            Text(title).font(Tokens.text(.caption, .semibold)).lineLimit(1).fixedSize()
        }
        .help(help).accessibilityElement(children: .ignore).accessibilityLabel("\(title). \(help)")
    }

    var allReadings: some View {
        DisclosureGroup(isExpanded: $showAll) {
            // Columns grow with the Text size setting, so a time or a label never wraps inside its column.
            let k = TextScale.shared.factor
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(c.readings.prefix(12))) { r in
                    HStack(spacing: Space.s) {
                        Text(r.date.formatted(.dateTime.hour().minute())).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).monospacedDigit().lineLimit(1).frame(width: 64 * k, alignment: .leading)
                        Text(r.appText).font(Tokens.text(.body)).lineLimit(1).frame(width: 110 * k, alignment: .leading)
                        HStack(spacing: Space.xs) { RingView(r.ring, color: r.tint).frame(width: 14, height: 14); Text(r.label).font(Tokens.text(.caption, .semibold)).lineLimit(1) }.frame(width: 100 * k, alignment: .leading)
                        Text(r.reason).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).lineLimit(1)
                        Spacer(minLength: 6)
                        if r.source == .rule { Text(r.byWords ? "Matching words" : "Your rule").font(Tokens.text(.caption2)).foregroundStyle(Tokens.ink2).padding(.horizontal, Space.xs).padding(.vertical, 1).overlay { Capsule().strokeBorder(Tokens.line) } }
                    }
                    .padding(.vertical, Space.xs).contentShape(Rectangle()).onTapGesture { pinned = r.id }
                    Divider().overlay(Tokens.line)
                }
                Text("Kept only while this session runs.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).padding(.top, Space.xs)
            }.padding(.top, Space.xs)
        } label: {
            Text("All readings").font(Tokens.text(.caption, .semibold))
        }
    }
}

/// The last readings as a strip you can touch. Shape carries the call, not color: a tall solid bar is on task, a tall dashed one is not sure,
/// a short dark one is off topic. Tapping a bar shows the reason behind that reading in the card above.
struct ReadingsStrip: View {
    var readings: [Reading]
    @Binding var pinned: UUID?

    var body: some View {
        // 24 at most, so every bar keeps a 24 point target and the strip fits the card at the smallest window.
        let items = Array(readings.prefix(24).reversed())
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent readings").font(Tokens.text(.caption, .semibold))
                Spacer()
                Text("Tap one to see why").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
            }
            HStack(alignment: .center, spacing: 2) {
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
        let shape = RoundedRectangle(cornerRadius: Tokens.radiusTiny, style: .continuous)
        ZStack {
            switch r.call {
            case .on: shape.fill(Tokens.accent).frame(width: 9, height: 26)
            case .unsure: shape.strokeBorder(Tokens.ink2, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2])).frame(width: 9, height: 26)
            case .off: shape.fill(Tokens.ink.opacity(0.5)).frame(width: 9, height: 12)
            }
        }
        .frame(width: Tokens.minHit, height: 30)
        .background(RoundedRectangle(cornerRadius: Tokens.radiusTiny, style: .continuous).fill(selected ? Tokens.control : .clear))
        .contentShape(Rectangle())
    }
}

/// How this session's readings split, as one bar and three counts. Shape-coded like the strip.
struct SessionTally: View {
    var stats: ReadStats
    var body: some View {
        Tile(padding: 20) {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("This session").font(Tokens.text(.callout, .semibold)).accessibilityAddTraits(.isHeader)
                if stats.total == 0 {
                    Text("No readings yet.").font(Tokens.text(.body)).foregroundStyle(Tokens.ink2)
                } else {
                    ReadingSplit(stats: stats)
                    VStack(spacing: Space.xs) {
                        row(.on, "On task", stats.onTask)
                        row(.unsure, "Not sure", stats.unsure)
                        row(.drift, "Off topic", stats.offTask)
                    }
                }
            }
        }
    }
    func row(_ ring: RingState, _ label: String, _ n: Int) -> some View {
        HStack(spacing: Space.xs) {
            RingView(ring, color: ring == .on ? Tokens.accent : Tokens.ink).frame(width: 14, height: 14)
            Text(label).font(Tokens.text(.body))
            Spacer()
            Text("\(n)").font(Tokens.text(.body, .semibold)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
