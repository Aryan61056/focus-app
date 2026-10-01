import SwiftUI

struct HistoryView: View {
    @Bindable var store: DataStore
    @State private var selected: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("History").font(Tokens.rounded(26, .semibold))
                Text("Every session, kept on this Mac. Delete any of them at any time.").font(Tokens.text(13.5)).foregroundStyle(Tokens.ink2)
            }
            if store.sessions.isEmpty {
                EmptyState(title: "No sessions yet", text: "Finished sessions show up here with a timeline you can read at a glance.")
            } else {
                HStack(alignment: .top, spacing: 20) {
                    Scroller {
                        VStack(spacing: 0) {
                            ForEach(store.sessions) { s in
                                let on = (selected ?? store.sessions.first?.id) == s.id
                                Button { selected = s.id } label: {
                                    HStack(spacing: 12) {
                                        Text(s.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())).font(Tokens.text(13)).frame(width: 112, alignment: .leading)
                                        Text(s.task).font(Tokens.text(13.5, .semibold)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                        Text(durationText(s.activeSeconds)).font(Tokens.text(13)).monospacedDigit().frame(width: 70, alignment: .trailing)
                                        MiniTimeline(segments: s.segments).frame(width: 100)
                                        Text("\(s.drifts)").font(Tokens.text(13)).monospacedDigit().frame(width: 36, alignment: .trailing).accessibilityLabel("\(s.drifts) slips")
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 11)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(on ? Tokens.control : .clear)).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                                Divider().overlay(Tokens.line)
                            }
                        }
                    }
                    if let s = store.sessions.first(where: { $0.id == (selected ?? store.sessions.first?.id) }) { SessionDrawer(store: store, session: s).frame(width: 300) }
                }
            }
            Spacer(minLength: 0)
        }
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
                Text(sessionSentence(session)).font(Tokens.text(14))
                MiniTimeline(segments: session.segments, height: 22)
                if let r = session.reads, r.total > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What Focus read").font(Tokens.text(12.5, .semibold))
                        ReadingSplit(stats: r)
                        Text("\(r.total) checks: \(r.onTask) on task, \(r.unsure) not sure, \(r.offTask) off topic. \(r.rule) were settled by your rules.")
                            .font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 14) { legend("On task", .on); legend("Unsure", .unsure); legend("Off topic", .off) }.font(Tokens.text(12)).foregroundStyle(Tokens.ink2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Note").font(Tokens.text(12.5, .semibold))
                    TextField("Add a note for next time", text: $note, axis: .vertical).textFieldStyle(.plain).lineLimit(2...4).padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Tokens.control)).onChange(of: note) { _, v in store.setNote(v, for: session.id) }
                }
                Button("Delete session") { store.deleteSession(session.id) }.buttonStyle(FocusButtonStyle(.plain, small: true))
            }
        }
        .onAppear { note = session.note }
        .id(session.id)
    }
    func legend(_ t: String, _ k: TimelineSegment.Kind) -> some View { HStack(spacing: 5) { MiniTimeline(segments: [TimelineSegment(k, 1)], height: 8).frame(width: 14); Text(t) } }
}
