import SwiftUI
import FocusBrain

// "Workspace" (owner, 2026-10-16): the pieces every screen shares. Visual first, labels of a few words, one green accent, and Focus's
// own work in plain sight: what it is reading, the checks it ran, and a short log of what it did.

/// The bar at the top of Today: Focus, the window it is reading, its three checks as dots, and how long ago it looked.
struct FocusBar: View {
    @Bindable var c: SessionController
    var reading: Reading?
    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "sparkles").font(Tokens.symbol(13, .semibold)).foregroundStyle(Tokens.accent).accessibilityHidden(true)
            Text("Focus").font(Tokens.text(.body, .semibold))
            Text(status).font(Tokens.text(.body)).foregroundStyle(Tokens.ink2).lineLimit(1)
            if c.isJudging && !c.isHeld { ThinkingDot() }
            Spacer(minLength: Space.s)
            if let r = reading, !c.isHeld {
                CheckDots(reading: r, task: c.taskName)
                TimelineView(.everySecond) { _ in
                    Text(Self.ago(c.nowSeconds() - r.at)).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).monospacedDigit()
                }
            }
        }
        .padding(.horizontal, Space.s).frame(minHeight: 36)
        .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(Tokens.well))
        .overlay { RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).strokeBorder(Tokens.line) }
        .accessibilityElement(children: .combine)
    }
    var status: String {
        if c.isHeld { return "paused, not reading" }
        if c.shadow { return reading.map { "practising on \($0.appText)" } ?? "practising" }
        guard let r = reading else { return "waiting for a window" }
        return "reading \(r.appText)"
    }
    static func ago(_ s: Double) -> String { s < 5 ? "now" : (s < 90 ? "\(Int(s)) s" : "\(Int(s / 60)) min") }
}

/// Read, compared, decided: three dots joined by a line. The last one carries the call by its shape. Each says what it did on hover.
struct CheckDots: View {
    var reading: Reading
    var task: String
    var body: some View {
        HStack(spacing: 3) {
            dot(filled: true).help(reading.sawScreen ? "Read the app, title, address and words on screen" : "Read the app, title and address")
            joint
            dot(filled: true).help("Compared with \u{201C}\(task)\u{201D}")
            joint
            outcome.help("\(reading.outcomeTitle). \(reading.outcomeText)")
        }
        .accessibilityElement().accessibilityLabel("Read, compared, \(reading.outcomeTitle)")
    }
    var joint: some View { Capsule().fill(Tokens.track).frame(width: 9, height: 1.5) }
    func dot(filled: Bool) -> some View { Circle().fill(Tokens.accent).frame(width: 7, height: 7) }
    @ViewBuilder var outcome: some View {
        switch reading.call {
        case .on: Circle().fill(Tokens.accent).frame(width: 7, height: 7)
        case .unsure: Circle().strokeBorder(Tokens.ink2, style: StrokeStyle(lineWidth: 1.5, dash: [1.6, 1.6])).frame(width: 8, height: 8)
        case .off: Circle().fill(Tokens.slip).frame(width: 7, height: 7)
        }
    }
}

/// Focus's call, large: its ring, two words, and one line of why. The full reason is a tooltip, so the screen stays quiet.
struct VerdictView: View {
    var reading: Reading
    var body: some View {
        HStack(alignment: .center, spacing: Space.m) {
            RingView(reading.ring, color: reading.call == .off ? Tokens.slip : (reading.call == .on ? Tokens.accent : Tokens.ink2)).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(reading.label).font(Tokens.rounded(.title2, .semibold))
                Text(basis).font(Tokens.text(.callout)).foregroundStyle(Tokens.ink2).lineLimit(1).help(reading.reason)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
    /// A few words: how it decided, then its reason, shortened.
    var basis: String {
        if reading.failed { return "Could not read it, did nothing" }
        switch reading.source {
        case .sensitive: return "Private window, not read"
        case .skipped: return "Never judged"
        case .rule: return reading.byWords ? Self.matched(reading.reason) : "Your rule"
        case .model: return reading.reason
        }
    }
    /// "…shares words with your task: calc." becomes "Matches calc".
    static func matched(_ reason: String) -> String {
        guard let i = reason.lastIndex(of: ":") else { return "Matching words" }
        let w = reason[reason.index(after: i)...].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return w.isEmpty ? "Matching words" : "Matches \(w)"
    }
}

/// The session as one band: each reading holds until the next. Solid green is on task, a dashed outline is not sure, a lower amber
/// block is off topic, so the call is never color alone. Tap a stretch to see Focus's reason for it.
struct SessionTimeline: View {
    struct Stretch: Identifiable, Equatable {
        var id: UUID?
        var from: Double, to: Double
        var call: Reading.Call?
    }
    var readings: [Reading]
    var start: Double
    var now: Double
    /// The planned end of a timed session; nil for Open, which fills to now.
    var end: Double?
    @Binding var pinned: UUID?

    /// Pure, so it is tested: stretches from the readings (newest first, as the controller keeps them), oldest first, clipped to the session.
    static func stretches(_ readings: [Reading], start: Double, now: Double) -> [Stretch] {
        let old = readings.filter { $0.at >= start - 1 && $0.at <= now }.sorted { $0.at < $1.at }
        var out: [Stretch] = []
        if let first = old.first, first.at > start + 1 { out.append(Stretch(id: nil, from: start, to: first.at, call: nil)) }
        for (i, r) in old.enumerated() {
            let to = i + 1 < old.count ? old[i + 1].at : now
            guard to > r.at else { continue }
            if let last = out.last, last.call == r.call, last.id != nil, last.to == r.at {
                out[out.count - 1].to = to   // the same call again: one stretch, keeping the first reading's reason
            } else {
                out.append(Stretch(id: r.id, from: max(start, r.at), to: to, call: r.call))
            }
        }
        return out
    }

    var body: some View {
        let parts = Self.stretches(readings, start: start, now: now)
        // An open session fills to now, so the right edge is always "now"; a timed one is drawn against its planned length.
        let span = max(1, (end ?? now) - start)
        VStack(alignment: .leading, spacing: Space.xxs) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Tokens.radiusTiny).strokeBorder(Tokens.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    ForEach(parts) { p in
                        let x = (p.from - start) / span * g.size.width, w = max(3, (p.to - p.from) / span * g.size.width - 2)
                        Button { pinned = (p.id == readings.first?.id) ? nil : p.id } label: { block(p, selected: p.id != nil && p.id == pinned, height: g.size.height) }
                            .buttonStyle(.plain).disabled(p.id == nil)
                            .frame(width: w, height: g.size.height).offset(x: x)
                            .help(label(p)).accessibilityLabel(label(p))
                    }
                }
            }
            .frame(height: 36)
            HStack {
                Text(clock(start)); Spacer(); if end != nil { Text("now \(clock(now))"); Spacer(); Text(clock(end!)) } else { Text("now") }
            }
            .font(Tokens.text(.caption2)).foregroundStyle(Tokens.ink2).monospacedDigit()
        }
        .accessibilityElement(children: .contain).accessibilityLabel("This session")
    }

    @ViewBuilder func block(_ p: Stretch, selected: Bool, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.radiusTiny, style: .continuous)
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            switch p.call {
            case .on?: shape.fill(Tokens.accentSoft).overlay { shape.strokeBorder(Tokens.accent.opacity(selected ? 1 : 0.35), lineWidth: selected ? 2 : 1) }.frame(height: height)
            case .unsure?: shape.fill(Tokens.window2).overlay { shape.strokeBorder(Tokens.ink2, style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: [3, 2])) }.frame(height: height)
            case .off?: shape.fill(Tokens.slipSoft).overlay { shape.strokeBorder(Tokens.slip, lineWidth: selected ? 2 : 1) }.frame(height: height * 0.62)
            case nil: shape.fill(Tokens.control).frame(height: height * 0.3)
            }
        }
        .contentShape(Rectangle())
    }
    func label(_ p: Stretch) -> String {
        let what: String = { switch p.call { case .on?: return "On task"; case .unsure?: return "Not sure"; case .off?: return "Off topic"; case nil: return "Before the first window" } }()
        return "\(what), \(SessionCounts.minutes(p.to - p.from)) from \(clock(p.from))"
    }
    /// Wall-clock time of a point on the session's clock.
    func clock(_ t: Double) -> String { Date().addingTimeInterval(t - now).formatted(.dateTime.hour().minute()) }
}

/// Minutes on task, not sure and off topic so far, from the same stretches the timeline draws. Numbers, not sentences.
struct SessionCounts: View {
    var stretches: [SessionTimeline.Stretch]
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xxl) {
            count(.on, "on task"); count(.unsure, "not sure"); count(.off, "off topic")
        }
    }
    func count(_ call: Reading.Call, _ label: String) -> some View {
        let s = stretches.filter { $0.call == call }.reduce(0) { $0 + $1.to - $1.from }
        return VStack(alignment: .leading, spacing: 1) {
            Text(Self.minutes(s)).font(Tokens.rounded(.title3, .semibold)).monospacedDigit()
            Text(label).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
        }
        .accessibilityElement(children: .combine)
    }
    /// The same units as History and Insights ("8 s", "12 min", "1 h 5 min"), never a bare "m".
    static func minutes(_ s: Double) -> String { s < 60 ? "\(Int(s)) s" : (s < 3600 ? "\(Int(s / 60)) min" : "\(Int(s / 3600)) h \(Int(s.truncatingRemainder(dividingBy: 3600) / 60)) min") }
}

/// What Focus did, newest first, a few words each: the AI's work, shown as support rather than surveillance.
struct ActivityLog: View {
    struct Entry: Identifiable, Equatable {
        enum Kind: Equatable { case counted, unsure, offTopic, back, skipped, privateWindow, failed }
        var id: UUID
        var kind: Kind
        var title: String
        var detail: String
        var date: Date
    }
    var readings: [Reading]
    var limit = 6

    /// Pure, so it is tested. Readings arrive newest first; a run of the same window with the same call is one entry.
    static func entries(_ readings: [Reading], limit: Int = 6) -> [Entry] {
        let old = readings.sorted { $0.at < $1.at }
        var out: [Entry] = []
        var last: Reading?
        for r in old {
            if let l = last, l.key == r.key, l.call == r.call, l.source == r.source { continue }
            out.append(entry(r, after: last)); last = r
        }
        return Array(out.reversed().prefix(limit))
    }
    static func entry(_ r: Reading, after prev: Reading?) -> Entry {
        let app = r.appText
        if r.failed { return Entry(id: r.id, kind: .failed, title: "Couldn't read \(app)", detail: "did nothing", date: r.date) }
        switch r.source {
        case .sensitive: return Entry(id: r.id, kind: .privateWindow, title: "Left a private window", detail: "not read", date: r.date)
        case .skipped: return Entry(id: r.id, kind: .skipped, title: "Skipped \(app)", detail: "never judged", date: r.date)
        default: break
        }
        switch r.call {
        case .on where prev?.call == .off: return Entry(id: r.id, kind: .back, title: "You came back", detail: app, date: r.date)
        case .on: return Entry(id: r.id, kind: .counted, title: "Counted \(app)", detail: r.source == .rule ? (r.byWords ? "matching words" : "your rule") : "on task", date: r.date)
        case .unsure: return Entry(id: r.id, kind: .unsure, title: "Unsure, let it be", detail: app, date: r.date)
        case .off: return Entry(id: r.id, kind: .offTopic, title: "Read \(app) as off topic", detail: r.source == .rule ? "your rule" : "watching", date: r.date)
        }
    }

    var body: some View {
        let items = Self.entries(readings, limit: limit)
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                Text("Nothing yet").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).padding(.vertical, Space.xs)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { i, e in
                if i > 0 { Divider().overlay(Tokens.line) }
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    icon(e.kind).frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.title).font(Tokens.text(.body)).lineLimit(2)
                        Text("\(e.detail) \u{00B7} \(e.date.formatted(.dateTime.hour().minute()))").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).lineLimit(2)
                    }
                }
                .padding(.vertical, Space.xs)
                .accessibilityElement(children: .combine)
            }
        }
    }
    func icon(_ k: Entry.Kind) -> some View {
        let (name, color): (String, Color) = {
            switch k {
            case .counted: return ("checkmark.circle", Tokens.accent)
            case .back: return ("arrow.uturn.backward.circle", Tokens.accent)
            case .unsure: return ("circle.dashed", Tokens.ink2)
            case .offTopic: return ("circle.bottomhalf.filled", Tokens.slip)
            case .skipped: return ("checkmark.shield", Tokens.ink2)
            case .privateWindow: return ("lock", Tokens.ink2)
            case .failed: return ("exclamationmark.circle", Tokens.ink2)
            }
        }()
        return Image(systemName: name).font(Tokens.symbol(13)).foregroundStyle(color).accessibilityHidden(true)
    }
}

/// One group in the Focus panel: a small heading (with the sparkle when it is the AI's work), its content, a hairline under it.
struct PanelSection<Content: View>: View {
    var title: String
    var ai = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: 5) {
                if ai { Image(systemName: "sparkles").font(Tokens.symbol(11, .semibold)).foregroundStyle(Tokens.accent).accessibilityHidden(true) }
                Text(title).font(Tokens.text(.caption, .semibold)).foregroundStyle(ai ? Tokens.ink : Tokens.ink2)
            }
            .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// True while a page's Focus panel sits under the page instead of beside it (a narrow window), where the page's own scroll carries both.
private struct PanelStackedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues { var panelStacked: Bool { get { self[PanelStackedKey.self] } set { self[PanelStackedKey.self] = newValue } } }

/// The right-hand column. Its own surface, a step off the page, like the sidebar on the left.
struct FocusPanelColumn<Content: View>: View {
    @Environment(\.panelStacked) private var stacked
    @ViewBuilder var content: Content
    var body: some View {
        let column = VStack(alignment: .leading, spacing: Space.l) { content }
        if stacked {
            // Under the page there is no height of its own to scroll in: it is as tall as it needs to be, and its text lines up with the page's.
            column.padding(.horizontal, Space.xl).padding(.vertical, Space.m).frame(maxWidth: .infinity, alignment: .leading)
                .background(Tokens.sidebar.opacity(SnapshotMode.on ? 1 : 0.6))
        } else {
            ScrollView { column.padding(Space.m).frame(maxWidth: .infinity, alignment: .leading) }
                .scrollIndicators(.never)
                .background(Tokens.sidebar.opacity(SnapshotMode.on ? 1 : 0.6))
        }
    }
}

/// A row of a few numbers with small labels under them, for screen headers (History, Review, Insights).
struct Totals: View {
    var items: [(value: String, label: String)]
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xxl) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, i in
                VStack(alignment: .leading, spacing: 1) {
                    Text(i.value).font(Tokens.rounded(.title3, .semibold)).monospacedDigit()
                    Text(i.label).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The line CLAUDE.md asks to keep in view wherever Focus's call is shown.
struct CanBeWrong: View {
    var body: some View {
        Text("Focus can be wrong. When it isn't sure, it does nothing.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
    }
}

/// A page with the Focus panel at its right: the page scrolls on its own and the panel keeps a fixed width. The panel gives up some of
/// that width before the page does, so a smaller window keeps a readable page. When the page would still be squeezed (a narrow window, or
/// the sidebar open in a small one) the panel goes under the page inside the same scroll, so nothing is hidden.
/// `main` is the page's content, not a scroll view: this layout supplies the scrolling in both arrangements.
struct PanelLayout<Main: View, Side: View>: View {
    var panelWidth: CGFloat = 264
    @ViewBuilder var main: Main
    @ViewBuilder var side: Side
    @State private var width: CGFloat = 1000

    /// Narrowest panel, and the narrowest this layout runs side by side: the page keeps about 415 points beside it.
    static var narrowestPanel: CGFloat { 224 }
    static var stackBelow: CGFloat { 640 }

    var body: some View {
        // A little wider at larger text sizes, so its lines and buttons still fit.
        let k = 1 + (TextScale.shared.factor - 1) * 0.6
        let panel = max(Self.narrowestPanel, min(panelWidth, width * 0.32)) * k
        Group {
            if width >= Self.stackBelow {
                HStack(spacing: 0) {
                    Scroller { main }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    Rectangle().fill(Tokens.line).frame(width: 1)
                    side.frame(width: panel).frame(maxHeight: .infinity, alignment: .top)
                }
            } else {
                Scroller {
                    VStack(spacing: 0) {
                        main.frame(maxWidth: .infinity, alignment: .top)
                        Rectangle().fill(Tokens.line).frame(height: 1)
                        side.environment(\.panelStacked, true)
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// The windows of this session by time: icon, a bar as long as the time, and the minutes. The bar's style is the call Focus made most
/// of that time (solid on task, dashed not sure, amber off topic). Private and never-judged windows are left out.
struct SessionWindows: View {
    struct Row: Identifiable, Equatable { var id: String { app }; var app: String; var seconds: Double; var call: Reading.Call }
    var readings: [Reading]
    var start: Double
    var now: Double

    /// Pure, so it is tested: time per app, longest first, at most `limit`.
    static func rows(_ readings: [Reading], start: Double, now: Double, limit: Int = 5) -> [Row] {
        let old = readings.filter { $0.at >= start - 1 && $0.at <= now }.sorted { $0.at < $1.at }
        var time: [String: [Reading.Call: Double]] = [:]
        for (i, r) in old.enumerated() where r.source != .sensitive && r.source != .skipped {
            let to = i + 1 < old.count ? old[i + 1].at : now
            time[r.appText, default: [:]][r.call, default: 0] += max(0, to - r.at)
        }
        var rows: [Row] = []
        for (app, calls) in time {
            let total: Double = calls.values.reduce(0, +)
            let main: Reading.Call = calls.max { $0.value < $1.value }?.key ?? .unsure
            if total >= 1 { rows.append(Row(app: app, seconds: total, call: main)) }
        }
        rows.sort { $0.seconds == $1.seconds ? $0.app < $1.app : $0.seconds > $1.seconds }
        return Array(rows.prefix(limit))
    }

    var body: some View {
        let rows = Self.rows(readings, start: start, now: now)
        if !rows.isEmpty {
            let most = rows.map(\.seconds).max() ?? 1
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Windows").font(Tokens.text(.caption, .semibold)).foregroundStyle(Tokens.ink2).accessibilityAddTraits(.isHeader)
                ForEach(rows) { r in
                    HStack(spacing: Space.s) {
                        AppIcon(name: r.app, size: 22)
                        Text(r.app).font(Tokens.text(.body)).lineLimit(1).frame(width: 140 * TextScale.shared.factor, alignment: .leading)
                        GeometryReader { g in bar(r).frame(width: max(4, g.size.width * r.seconds / most)) }.frame(height: 10)
                        Text(SessionCounts.minutes(r.seconds)).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).monospacedDigit()
                            .frame(width: 52 * TextScale.shared.factor, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
    @ViewBuilder func bar(_ r: Row) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.radiusTiny, style: .continuous)
        switch r.call {
        case .on: shape.fill(Tokens.accent.opacity(0.75))
        case .unsure: shape.strokeBorder(Tokens.ink2, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        case .off: shape.fill(Tokens.slip.opacity(0.8))
        }
    }
}
