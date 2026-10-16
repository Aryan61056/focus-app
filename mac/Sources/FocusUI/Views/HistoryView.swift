import SwiftUI

struct HistoryView: View {
    @Bindable var store: DataStore
    @State private var selected: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "History", subtitle: "Every session, kept on this Mac. Delete any of them at any time.")
            if store.sessions.isEmpty {
                EmptyState(symbol: "clock", title: "No sessions yet", text: "Finished sessions show up here, each with a timeline you can read at a glance: on task, not sure and off topic.")
            } else {
                HStack(alignment: .top, spacing: 22) {
                    Scroller {
                        VStack(alignment: .leading, spacing: 0) {
                            header
                            ForEach(Self.days(store.sessions), id: \.day) { group in
                                Text(Self.dayTitle(group.day)).font(Tokens.text(12, .semibold)).foregroundStyle(Tokens.ink2)
                                    .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 4).accessibilityAddTraits(.isHeader)
                                ForEach(group.sessions) { s in row(s) }
                            }
                        }
                        .padding(8).modifier(CardSurface(radius: 16))
                    }
                    if let s = store.sessions.first(where: { $0.id == (selected ?? store.sessions.first?.id) }) { SessionDrawer(store: store, session: s).frame(width: 310) }
                }
            }
            Spacer(minLength: 0)
        }
    }

    var header: some View {
        HStack(spacing: 12) {
            Text("Time").frame(width: 76, alignment: .leading)
            Text("Task").frame(maxWidth: .infinity, alignment: .leading)
            Text("Length").frame(width: 70, alignment: .trailing)
            Text("Timeline").frame(width: 110, alignment: .leading)
            Text("Slips").frame(width: 40, alignment: .trailing)
        }
        .font(Tokens.text(11.5, .medium)).foregroundStyle(Tokens.ink2).padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 2)
        .accessibilityHidden(true)
    }

    func row(_ s: SessionRecord) -> some View {
        let on = (selected ?? store.sessions.first?.id) == s.id
        return SidebarRow(selected: on, action: { selected = s.id }) {
            Text(s.start.formatted(.dateTime.hour().minute())).font(Tokens.text(13)).foregroundStyle(Tokens.ink2).monospacedDigit().frame(width: 76, alignment: .leading)
            Text(s.task).font(Tokens.text(13.5, .semibold)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(durationText(s.activeSeconds)).font(Tokens.text(13)).monospacedDigit().frame(width: 70, alignment: .trailing)
            MiniTimeline(segments: s.segments).frame(width: 110)
            Text(s.drifts == 0 ? "\u{2013}" : "\(s.drifts)").font(Tokens.text(13)).foregroundStyle(s.drifts == 0 ? Tokens.ink2 : Tokens.ink).monospacedDigit()
                .frame(width: 40, alignment: .trailing).accessibilityLabel("\(s.drifts) slips")
        }
        .frame(height: 40)
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
            VStack(alignment: .leading, spacing: 12) {
                Text(session.task).font(Tokens.rounded(18, .semibold))
                Text("\(session.start.formatted(.dateTime.weekday().day().month().hour().minute())) · \(durationText(session.activeSeconds)) · \(session.timed ? "Timed" : "Open")")
                    .font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
                if let goal = session.goal {
                    Label(goal, systemImage: session.goalDone == true ? "checkmark.circle.fill" : "arrow.forward.circle")
                        .font(Tokens.text(13)).foregroundStyle(Tokens.ink2).help(session.goalDone == true ? "Marked done" : "Carried forward or not marked yet")
                }
                Text(sessionSentence(session)).font(Tokens.text(14))
                MiniTimeline(segments: session.segments, height: 22)
                if let r = session.reads, r.total > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What Focus read").font(Tokens.text(12.5, .semibold))
                        ReadingSplit(stats: r)
                        Text("\(r.total) checks: \(r.onTask) on task, \(r.unsure) not sure, \(r.offTask) off topic. \(r.rule) were settled without the model (your rules and matching words)\(r.skipped > 0 ? " and \(r.skipped) were left alone." : ".")")
                            .font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 14) { legend("On task", .on); legend("Unsure", .unsure); legend("Off topic", .off) }.font(Tokens.text(12)).foregroundStyle(Tokens.ink2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Note").font(Tokens.text(12.5, .semibold))
                    TextField("Add a note for next time", text: $note, axis: .vertical).lineLimit(2...4).padding(.vertical, 10).wellField(height: nil)
                        .onChange(of: note) { _, v in store.setNote(v, for: session.id) }
                }
                Button("Delete session") { store.deleteSession(session.id) }.buttonStyle(FocusButtonStyle(.plain, small: true))
            }
        }
        .onAppear { note = session.note }
        .id(session.id)
    }
    func legend(_ t: String, _ k: TimelineSegment.Kind) -> some View { HStack(spacing: 5) { MiniTimeline(segments: [TimelineSegment(k, 1)], height: 8).frame(width: 14); Text(t) } }
}
