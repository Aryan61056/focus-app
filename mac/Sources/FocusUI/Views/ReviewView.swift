import SwiftUI
import FocusJudge

/// Review: each moment Hushd would have nudged about, led by its call and its reason, with two answers. The Hushd panel says what the
/// answers do and how often Hushd has agreed with you. It can name the site: you opened Review to see it (nudges never do).
struct ReviewView: View {
    @Bindable var c: SessionController
    @Bindable var store: DataStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let open = store.review.filter { $0.answer == nil }
        PanelLayout {
            VStack(alignment: .leading, spacing: Space.l) {
                if c.prefs.practiceActive { practice }
                if open.isEmpty {
                    EmptyState(symbol: "checkmark", title: "All caught up", text: "Moments Hushd would have nudged about land here.")
                } else {
                    VStack(spacing: Space.s) {
                        ForEach(open) { m in
                            moment(m)
                                .transition(.asymmetric(insertion: .opacity, removal: reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top))))
                        }
                    }
                    .motion(Motion.notchSettle, value: open.map(\.id))
                }
            }
            .padding(.horizontal, Space.xl).padding(.top, Space.l).padding(.bottom, Space.xl).frame(maxWidth: 860, alignment: .leading)
        } side: {
            FocusPanelColumn {
                let a = store.agreement
                Totals(items: [("\(open.count)", "to answer"), ("\(a.agreed)/\(a.answered)", "agreed")])
                PanelSection(title: "Why review", ai: true) {
                    Text("Your answers teach each project what counts.").font(Tokens.text(.body)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                }
                CanBeWrong()
            }
        }
    }

    var practice: some View {
        HStack(spacing: Space.s) {
            RingView(.unsure, color: Tokens.ink2).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("Practice mode").font(Tokens.text(.body, .semibold))
                Text("Watching, not interrupting \u{00B7} \(c.prefs.practiceSessionsLeft) more session\(c.prefs.practiceSessionsLeft == 1 ? "" : "s")").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
            }
            Spacer()
            Button("Turn nudges on") { c.prefs.turnNudgesOnNow() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
        }
        .padding(Space.s)
        .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(Tokens.well))
    }

    /// Hushd's call and reason lead, because the call is what you are judging; where and when sit under it.
    func moment(_ m: ReviewMoment) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            RingView(.drift, color: Tokens.slip).frame(width: 22, height: 22).padding(.top, 1).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Read as off topic").font(Tokens.text(.callout, .semibold))
                Text(m.reason ?? "The window did not match the task.").font(Tokens.text(.body)).foregroundStyle(Tokens.ink2).lineLimit(2)
                Text("\(store.project(m.projectId)?.name ?? "Session") \u{00B7} \(m.siteKey.replacingOccurrences(of: "|", with: ", ")) \u{00B7} \(m.at.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                    .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).lineLimit(1).monospacedDigit()
                HStack(spacing: Space.xs) {
                    Button { store.answerReview(m.id, "right") } label: { Label("Right call", systemImage: "checkmark") }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                    Button {
                        store.apply(LearnedRule(scope: "project", kind: "allow", keyType: "site", key: m.siteKey), to: m.projectId)
                        store.answerReview(m.id, "fine")
                    } label: { Label("I was on task", systemImage: "xmark") }.buttonStyle(FocusButtonStyle(.plain, small: true))
                        .help("Hushd will count this site as on task for this project")
                }
                .padding(.top, Space.xs)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.m)
        .modifier(CardSurface())
        .accessibilityElement(children: .contain)
    }
}
