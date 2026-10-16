import SwiftUI
import FocusJudge

struct ReviewView: View {
    @Bindable var c: SessionController
    @Bindable var store: DataStore
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            let a = store.agreement
            PageHeader(title: "Review", subtitle: "Moments Focus would have nudged you about, and why. It can be wrong; your answers teach it what counts.") {
                if a.answered > 0 { Text("Agreed with you on \(a.agreed) of \(a.answered)").font(Tokens.text(.body)).foregroundStyle(Tokens.ink2) }
            }
            if c.prefs.practiceActive {
                Panel(tinted: true) {
                    HStack(spacing: Space.m) {
                        RingView(.unsure, color: Tokens.ink).frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text("Practice mode").font(Tokens.text(.callout, .semibold))
                            Text("Focus is watching but will not interrupt you yet. \(c.prefs.practiceSessionsLeft) more session\(c.prefs.practiceSessionsLeft == 1 ? "" : "s").").font(Tokens.text(.body)).foregroundStyle(Tokens.ink2)
                        }
                        Spacer()
                        Button("Turn nudges on now") { c.prefs.turnNudgesOnNow() }.buttonStyle(FocusButtonStyle(.plain))
                    }
                }
            }
            let open = store.review.filter { $0.answer == nil }
            SectionTitle(text: open.isEmpty ? "All caught up" : "\(open.count) moment\(open.count == 1 ? "" : "s") to look at")
            if open.isEmpty {
                EmptyState(symbol: "checkmark", title: "Nothing to review", text: "When practice mode sees something it would have nudged about, it lands here. Nothing is shown or sent while you work.")
            } else {
                Scroller {
                    VStack(spacing: 0) {
                        ForEach(Array(open.enumerated()), id: \.element.id) { i, m in
                            if i > 0 { Divider().overlay(Tokens.line) }
                            moment(m)
                        }
                    }
                    .padding(.horizontal, Space.m).modifier(CardSurface())
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Focus's own reason leads, because the call is what you are judging; where and when sit under it.
    func moment(_ m: ReviewMoment) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            RingView(.drift, color: Tokens.ink).frame(width: 20, height: 20).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(m.reason ?? "Focus read this window as off topic.").font(Tokens.text(.body, .medium))
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 460, alignment: .leading)
                Text("\(store.project(m.projectId)?.name ?? "Session") \u{00B7} \(m.siteKey.replacingOccurrences(of: "|", with: ", ")) \u{00B7} \(m.at.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                    .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Space.s)
            HStack(spacing: Space.xs) {
                Button("Right call") { store.answerReview(m.id, "right") }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                Button("That was fine") {
                    store.apply(LearnedRule(scope: "project", kind: "allow", keyType: "site", key: m.siteKey), to: m.projectId)
                    store.answerReview(m.id, "fine")
                }.buttonStyle(FocusButtonStyle(.plain, small: true))
            }
            .fixedSize()
        }
        .padding(.vertical, Space.m).padding(.horizontal, Space.xs)
    }
}
