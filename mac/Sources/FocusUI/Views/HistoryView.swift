import SwiftUI

/// History: a few totals, then every session as a timeline as long as the session, grouped by day. The selected session's details,
/// what Focus did in it and your note sit in the Focus panel on the right.
struct HistoryView: View {
    @Bindable var store: DataStore
    @State private var selected: UUID?
    var body: some View {
        if store.sessions.isEmpty {
            EmptyState(symbol: "clock", title: "No sessions yet", text: "Finished sessions show up here as timelines.")
                .padding(Space.xl).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            PanelLayout {
                VStack(alignment: .leading, spacing: Space.l) {
                    Totals(items: Self.totals(store.sessions, now: .now))
                    VStack(alignment: .leading, spacing: 0) {
                        let longest = store.sessions.map(\.activeSeconds).max() ?? 1
                        ForEach(Self.days(store.sessions), id: \.day) { group in
                            Text(Self.dayTitle(group.day)).font(Tokens.text(.caption, .semibold)).foregroundStyle(Tokens.ink2)
                                .padding(.horizontal, Space.s).padding(.top, Space.m).padding(.bottom, Space.xxs).accessibilityAddTraits(.isHeader)
                            ForEach(group.sessions) { s in row(s, longest: longest) }
                        }
                    }
                }
                .padding(.horizontal, Space.xl).padding(.top, Space.l).padding(.bottom, Space.xl)
            } side: {
                FocusPanelColumn {
                    if let s = store.sessions.first(where: { $0.id == (selected ?? store.sessions.first?.id) }) { SessionDrawer(store: store, session: s) }
                }
            }
        }
    }

    /// The last seven days in three numbers.
    static func totals(_ sessions: [SessionRecord], now: Date) -> [(value: String, label: String)] {
        let week = sessions.filter { now.timeIntervalSince($0.start) < 7 * 86400 }
        let on = week.reduce(0) { $0 + $1.activeSeconds }
        return [(durationText(on), "focused this week"), ("\(week.count)", week.count == 1 ? "session" : "sessions"), ("\(week.reduce(0) { $0 + $1.drifts })", "slips")]
    }

    /// The task and when on the left, the session's timeline as long as the session beside it, slips at the right.
    func row(_ s: SessionRecord, longest: Double) -> some View {
        let on = (selected ?? store.sessions.first?.id) == s.id
        let slips = s.drifts == 0 ? "No slips" : (s.drifts == 1 ? "1 slip" : "\(s.drifts) slips")
        let k = TextScale.shared.factor
        return SidebarRow(selected: on, action: { selected = s.id }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.task).font(Tokens.text(.body, .semibold)).lineLimit(1)
                Text("\(s.start.formatted(.dateTime.hour().minute())) \u{00B7} \(durationText(s.activeSeconds))").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).monospacedDigit().lineLimit(1)
            }
            .frame(minWidth: 110 * k, idealWidth: 180 * k, maxWidth: 180 * k, alignment: .leading)
            GeometryReader { g in
                MiniTimeline(segments: s.segments, height: 12).frame(width: max(24, g.size.width * min(1, s.activeSeconds / max(1, longest))))
                    .frame(maxHeight: .infinity)
            }
            .frame(height: 24)
            Text(slips).font(Tokens.text(.caption)).foregroundStyle(s.drifts == 0 ? Tokens.ink2 : Tokens.ink).monospacedDigit().lineLimit(1)
                .frame(width: 64 * k, alignment: .trailing)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(s.task), \(s.start.formatted(.dateTime.hour().minute())), \(durationText(s.activeSeconds)), \(slips)")
    }

    /// Sessions grouped by calendar day, newest first, so a long list reads as days instead of one column of times.
    static func days(_ sessions: [SessionRecord], calendar cal: Calendar = .current) -> [(day: Date, sessions: [SessionRecord])] {
        var out: [(day: Date, sessions: [SessionRecord])] = []
        for s in sessions {
            let d = cal.startOfDay(for: s.start)
            if let i = out.firstIndex(where: { $0.day == d }) { out[i].sessions.append(s) } else { out.append((d, [s])) }
        }
        return out.sorted { $0.day > $1.day }.map { ($0.day, $0.sessions.sorted { $0.start > $1.start }) }
    }
    static func dayTitle(_ d: Date, calendar cal: Calendar = .current) -> String {
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// One session in the Focus panel: when and how long, its timeline, what Focus did (as counts), your note, and delete.
struct SessionDrawer: View {
    @Bindable var store: DataStore
    var session: SessionRecord
    @State private var note = ""
    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(session.task).font(Tokens.rounded(.title3, .semibold)).lineLimit(2)
                let when = session.start.formatted(.dateTime.weekday().day().month().hour().minute())
                let how = "\(durationText(session.activeSeconds)) \u{00B7} \(session.timed ? "Timed" : "Open")"
                // One line when it fits; otherwise the day and time, then the length, so a separator never starts a line.
                ViewThatFits(in: .horizontal) {
                    Text("\(when) \u{00B7} \(how)").lineLimit(1)
                    VStack(alignment: .leading, spacing: 0) { Text(when); Text(how) }
                }
                .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                if let goal = session.goal {
                    Label(goal, systemImage: session.goalDone == true ? "checkmark.circle.fill" : "arrow.forward.circle")
                        .font(Tokens.text(.body)).foregroundStyle(Tokens.ink2).help(session.goalDone == true ? "Marked done" : "Carried forward or not marked yet")
                        .padding(.top, Space.xxs)
                }
                MiniTimeline(segments: session.segments, height: 16, animated: true).padding(.top, Space.xs)
                FlowRow(spacing: Space.s) { legend("On task", .on); legend("Unsure", .unsure); legend("Off topic", .off) }.font(Tokens.text(.caption2)).foregroundStyle(Tokens.ink2)
            }
            PanelSection(title: "What Focus did", ai: true) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    if let r = session.reads, r.total > 0 {
                        fact("checkmark.circle", Tokens.accent, r.onTask, "counted on task")
                        fact("circle.dashed", Tokens.ink2, r.unsure, "left alone, not sure")
                        fact("circle.bottomhalf.filled", Tokens.slip, r.offTask, "read as off topic")
                        if r.rule > 0 { fact("text.word.spacing", Tokens.ink2, r.rule, "settled without the model") }
                        if r.skipped > 0 { fact("checkmark.shield", Tokens.ink2, r.skipped, "never judged") }
                    }
                    fact("bell", Tokens.ink2, session.interrupts, session.interrupts == 1 ? "nudge" : "nudges")
                }
            }
            PanelSection(title: "Note") {
                TextField("For next time", text: $note, axis: .vertical).font(Tokens.text(.body)).lineLimit(2...4).padding(.vertical, Space.s).wellField(height: nil)
                    .onChange(of: note) { _, v in store.setNote(v, for: session.id) }
            }
            Button("Delete session") { store.deleteSession(session.id) }.buttonStyle(FocusButtonStyle(.plain, small: true))
        }
        .onAppear { note = session.note }
        .id(session.id)
    }
    func fact(_ symbol: String, _ color: Color, _ n: Int, _ label: String) -> some View {
        HStack(spacing: Space.xs) {
            Image(systemName: symbol).font(Tokens.symbol(13)).foregroundStyle(color).frame(width: 16).accessibilityHidden(true)
            Text("\(n)").font(Tokens.text(.body, .semibold)).monospacedDigit()
            Text(label).font(Tokens.text(.body)).foregroundStyle(Tokens.ink2).lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
    func legend(_ t: String, _ k: TimelineSegment.Kind) -> some View { HStack(spacing: Space.xxs) { MiniTimeline(segments: [TimelineSegment(k, 1)], height: 8).frame(width: 14); Text(t).fixedSize() } }
}
