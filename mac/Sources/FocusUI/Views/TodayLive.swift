import SwiftUI
import FocusBrain

// Today while a session runs, for a three second glance: Focus's bar, its call, the session as one band, three numbers.
// Pause, Break and End live in the toolbar; what Focus did and Ask Focus live in the Focus panel on the right.

struct TodayLiveMain: View {
    @Bindable var c: SessionController
    /// The guided example shows the call without the screen picture or the session's history.
    var showPreview = true
    var isExample = false
    /// "I'm stuck", offered under the call while you work (nil on a break, or while its own card is open).
    var onStuck: (() -> Void)?
    @State private var pinned: UUID?
    @State private var width: CGFloat = 800

    /// The big picture only exists once screen reading is on; until then the Focus panel carries the invitation.
    var showPreviewColumn: Bool { showPreview && pinned == nil && c.prefs.readScreen }

    var shown: Reading? { pinned.flatMap { id in c.readings.first { $0.id == id } } ?? c.latest }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            FocusBar(c: c, reading: c.latest)
            if c.isHeld {
                HStack(spacing: Space.m) {
                    RingView(.paused, color: Tokens.ink2).frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Paused").font(Tokens.rounded(.title2, .semibold))
                        Text(c.heldLine).font(Tokens.text(.callout)).foregroundStyle(Tokens.ink2).lineLimit(2)
                    }
                }
            } else if let r = shown {
                if showPreviewColumn && width >= 720 {
                    HStack(alignment: .top, spacing: Space.xl) {
                        call(r).frame(maxWidth: .infinity, alignment: .leading)
                        PreviewCard(c: c).frame(width: min(400, width * 0.42))
                    }
                } else {
                    call(r)
                    if showPreviewColumn { PreviewCard(c: c) }
                }
            } else {
                HStack(spacing: Space.m) {
                    RingView(.unsure, color: Tokens.ink2).frame(width: 52, height: 52)
                    Text("Switch to your work").font(Tokens.rounded(.title3, .semibold)).foregroundStyle(Tokens.ink2)
                }
            }
            if !isExample {
                TimelineView(.everySecond) { _ in
                    let now = c.nowSeconds()
                    VStack(alignment: .leading, spacing: Space.l) {
                        SessionTimeline(readings: c.readings, start: c.startSeconds, now: now,
                                        end: c.mode == .timed && c.totalSeconds > 0 ? c.startSeconds + c.totalSeconds : nil, pinned: $pinned)
                        SessionCounts(stretches: SessionTimeline.stretches(c.readings, start: c.startSeconds, now: now))
                        SessionWindows(readings: c.readings, start: c.startSeconds, now: now).padding(.top, Space.s)
                    }
                }
                if c.readings.count > 1 { AllReadings(readings: c.readings, pinned: $pinned) }
            }
        }
        // A new reading with the same call only refreshes its words; a new call morphs the ring, label and tint with a settling spring.
        .motion(Motion.out(0.2), value: shown?.id)
        .motion(Motion.notchSettle, value: shown?.call)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: c.isActive) { _, on in if !on { pinned = nil } }
    }

    func call(_ r: Reading) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            VerdictView(reading: r)
            HStack(spacing: Space.s) {
                if pinned != nil {
                    Text("At \(r.date.formatted(.dateTime.hour().minute()))").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                    Button("Back to now") { pinned = nil }.buttonStyle(FocusButtonStyle(.plain, small: true))
                } else if let m = c.moment {
                    MomentLine(moment: m)
                } else if let note = statusNote {
                    Text(note).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                }
            }
            .motion(Motion.notchSettle, value: c.moment)
            HStack(alignment: .center, spacing: Space.s) {
                CanBeWrong()
                Spacer(minLength: Space.xs)
                if let onStuck {
                    Button(action: onStuck) { Label("I'm stuck", systemImage: "lifepreserver").lineLimit(1) }
                        .buttonStyle(FocusButtonStyle(.secondary, small: true)).fixedSize().help("Find a smaller next action")
                }
            }
        }
    }
    var statusNote: String? {
        if c.shadow { return c.shadowMarks == 0 ? "Practice: watching, not interrupting" : "Practice: \(c.shadowMarks) to review" }
        return nil
    }
}

/// Every reading of this session, folded away: time, window, call, reason. Tap one to see it above.
struct AllReadings: View {
    var readings: [Reading]
    @Binding var pinned: UUID?
    @State private var open = false
    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            // Columns grow with the Text size setting, so a time or a label never wraps inside its column.
            let k = TextScale.shared.factor
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(readings.prefix(12))) { r in
                    HStack(spacing: Space.s) {
                        Text(r.date.formatted(.dateTime.hour().minute())).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).monospacedDigit().lineLimit(1).frame(width: 64 * k, alignment: .leading)
                        Text(r.appText).font(Tokens.text(.body)).lineLimit(1).frame(width: 110 * k, alignment: .leading)
                        HStack(spacing: Space.xs) { RingView(r.ring, color: r.call == .off ? Tokens.slip : r.tint).frame(width: 14, height: 14); Text(r.label).font(Tokens.text(.caption, .semibold)).lineLimit(1) }.frame(width: 100 * k, alignment: .leading)
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

/// The Focus panel on Today. During a session: what Focus did, Ask Focus and the screen picture offer.
/// Between sessions: today's goal and how Focus decides.
struct TodayPanel: View {
    @Bindable var c: SessionController
    var body: some View {
        FocusPanelColumn {
            if c.isActive {
                PanelSection(title: "What Hushd did", ai: true) { ActivityLog(readings: c.readings) }
                if c.aiAvailable && !c.stuckShown && c.presence.reason != "break" { PanelSection(title: "Ask Hushd", ai: true) { AskPanel(c: c, compact: true) } }
                if !c.prefs.readScreen {
                    PanelSection(title: "Screen reading") {
                        Button { c.prefs.readScreen = true; c.onRequestPreviewAccess?() } label: { Label("Show the window here", systemImage: "eye") }
                            .buttonStyle(FocusButtonStyle(.secondary, small: true))
                            .help("Hushd shows the window it reads and uses the words on it. Nothing is saved.")
                    }
                }
            }
            if let st = c.store { GoalCluster(c: c, store: st) }
            HowDecidesButton()
            Label("Stays on this Mac", systemImage: "lock").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
        }
    }
}
