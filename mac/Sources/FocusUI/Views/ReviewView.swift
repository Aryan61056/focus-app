import SwiftUI
import FocusJudge

struct ReviewView: View {
    @Bindable var c: SessionController
    @Bindable var store: DataStore
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Moments Focus would have nudged you about, and why. Your answers teach it what counts.").font(Tokens.text(13.5)).foregroundStyle(Tokens.ink2)
                    Spacer()
                    let a = store.agreement
                    if a.answered > 0 { Text("Agreed with you on \(a.agreed) of \(a.answered)").font(Tokens.text(13)).foregroundStyle(Tokens.ink2) }
                }
            }
            if c.prefs.practiceActive {
                Panel(tinted: true) {
                    HStack(spacing: 14) {
                        RingView(.unsure, color: Tokens.ink).frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Practice mode").font(Tokens.text(14, .semibold))
                            Text("Focus is watching but will not interrupt you yet. \(c.prefs.practiceSessionsLeft) more session\(c.prefs.practiceSessionsLeft == 1 ? "" : "s").").font(Tokens.text(13)).foregroundStyle(Tokens.ink2)
                        }
                        Spacer()
                        Button("Turn nudges on now") { c.prefs.turnNudgesOnNow() }.buttonStyle(FocusButtonStyle(.plain))
                    }
                }
            }
            let open = store.review.filter { $0.answer == nil }
            SectionTitle(text: open.isEmpty ? "All caught up" : "\(open.count) moment\(open.count == 1 ? "" : "s") to look at")
            if open.isEmpty {
                EmptyState(title: "Nothing to review", text: "When practice mode sees something it would have nudged about, it lands here. Nothing is shown or sent while you work.")
            } else {
                Scroller { VStack(spacing: 0) { ForEach(open) { m in moment(m); Divider().overlay(Tokens.line) } } }
            }
            Spacer(minLength: 0)
        }
    }

    func moment(_ m: ReviewMoment) -> some View {
        HStack(spacing: 16) {
            Text(m.at.formatted(.dateTime.weekday(.abbreviated).hour().minute())).font(Tokens.text(13)).foregroundStyle(Tokens.ink2).frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.project(m.projectId)?.name ?? "Session").font(Tokens.text(13.5, .semibold))
                Text(m.siteKey.replacingOccurrences(of: "|", with: ", ")).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
                HStack(spacing: 6) { RingView(.drift, color: Tokens.ink).frame(width: 13, height: 13); Text("Would have nudged").font(Tokens.text(12)) }
                    .padding(.horizontal, 9).frame(height: 22).background(Capsule().fill(Tokens.control))
                if let why = m.reason { (Text("Why Focus flagged it: ").foregroundStyle(Tokens.ink2) + Text(why)).font(Tokens.text(13)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 440, alignment: .leading).padding(.top, 3) }
            }
            Spacer()
            Button("Right call") { store.answerReview(m.id, "right") }.buttonStyle(FocusButtonStyle(.secondary, small: true))
            Button("That was fine") {
                store.apply(LearnedRule(scope: "project", kind: "allow", keyType: "site", key: m.siteKey), to: m.projectId)
                store.answerReview(m.id, "fine")
            }.buttonStyle(FocusButtonStyle(.plain, small: true))
        }
        .padding(.vertical, 14).padding(.horizontal, 6)
    }
}
