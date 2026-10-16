import SwiftUI

struct HistoryView: View {
    @Bindable var store: DataStore
    @State private var selected: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            PageHeader(title: "History", subtitle: "Every session, kept on this Mac. Delete any of them at any time.")
            if store.sessions.isEmpty {
                EmptyState(symbol: "clock", title: "No sessions yet", text: "Finished sessions show up here, each with a timeline you can read at a glance: on task, not sure and off topic.")
            } else {
                HStack(alignment: .top, spacing: Space.xl) {
                    Scroller {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Self.days(store.sessions), id: \.day) { group in
                                Text(Self.dayTitle(group.day)).font(Tokens.text(.caption, .semibold)).foregroundStyle(Tokens.ink2)
                                    .padding(.horizontal, Space.s).padding(.top, Space.m).padding(.bottom, Space.xxs).accessibilityAddTraits(.isHeader)
                                ForEach(group.sessions) { s in row(s) }
                            }
                        }
                        .padding(.horizontal, Space.xs).padding(.bottom, Space.xs).modifier(CardSurface())
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                    if let s = store.sessions.first(where: { $0.id == (selected ?? store.sessions.first?.id) }) { SessionDrawer(store: store, session: s).frame(width: 280) }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Two lines, so the task always has room: the task on top, the time and length under it, the timeline and slips on the right.
    /// (Five fixed columns beside the drawer left the task about 8 points, so every row read as "...".)
    func row(_ s: SessionRecord) -> some View {
        let on = (selected ?? store.sessions.first?.id) == s.id
        let slips = s.drifts == 0 ? "No slips" : (s.drifts == 1 ? "1 slip" : "\(s.drifts) slips")
        return SidebarRow(selected: on, action: { selected = s.id }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.task).font(Tokens.text(.body, .semibold)).lineLimit(1)
                Text("\(s.start.formatted(.dateTime.hour().minute())) \u{00B7} \(durationText(s.activeSeconds))").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).monospacedDigit().lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: Space.xxs) {
                MiniTimeline(segments: s.segments).frame(width: 96)
                Text(slips).font(Tokens.text(.caption)).foregroundStyle(s.drifts == 0 ? Tokens.ink2 : Tokens.ink).monospacedDigit()
            }
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

struct SessionDrawer: View {
    @Bindable var store: DataStore
    var session: SessionRecord
    @State private var note = ""
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(session.task).font(Tokens.rounded(.title3, .semibold))
                Text("\(session.start.formatted(.dateTime.weekday().day().month().hour().minute())) · \(durationText(session.activeSeconds)) · \(session.timed ? "Timed" : "Open")")
                    .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                Text(sessionSentence(session)).font(Tokens.text(.callout))
                MiniTimeline(segments: session.segments, height: 22)
                if let r = session.reads, r.total > 0 {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("What Focus read").font(Tokens.text(.caption, .semibold))
                        ReadingSplit(stats: r)
                        Text("\(r.total) checks: \(r.onTask) on task, \(r.unsure) not sure, \(r.offTask) off topic. \(r.rule) were settled without the model (your rules and matching words)\(r.skipped > 0 ? " and \(r.skipped) were left alone." : ".")")
                            .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                FlowRow(spacing: Space.s) { legend("On task", .on); legend("Unsure", .unsure); legend("Off topic", .off) }.font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Note").font(Tokens.text(.caption, .semibold))
                    TextField("Add a note for next time", text: $note, axis: .vertical).font(Tokens.text(.body)).lineLimit(2...4).padding(.vertical, Space.s).wellField(height: nil)
                        .onChange(of: note) { _, v in store.setNote(v, for: session.id) }
                }
                Button("Delete session") { store.deleteSession(session.id) }.buttonStyle(FocusButtonStyle(.plain, small: true))
            }
        }
        .onAppear { note = session.note }
        .id(session.id)
    }
    func legend(_ t: String, _ k: TimelineSegment.Kind) -> some View { HStack(spacing: Space.xxs) { MiniTimeline(segments: [TimelineSegment(k, 1)], height: 8).frame(width: 14); Text(t).fixedSize() } }
}
