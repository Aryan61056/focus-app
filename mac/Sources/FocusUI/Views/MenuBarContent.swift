import SwiftUI
import FocusBrain

/// The nine quick functions live here, in a plain menu list, so nothing crowds the notch (owner decision 2026-10-01).
public struct MenuBarContent: View {
    @Bindable var c: SessionController
    var openApp: () -> Void
    public init(controller: SessionController, openApp: @escaping () -> Void) { self.c = controller; self.openApp = openApp }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if c.isActive {
                HStack(spacing: 10) {
                    TimelineView(.everySecond) { _ in LiveRing(c.ringState, color: c.ringColor).frame(width: 30, height: 30) }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c.taskName).font(Tokens.fixed(.callout, .semibold, rounded: true)).lineLimit(1)
                        Text("\(c.presenceLabel) · \(c.mode == .timed ? "Timed" : "Open") session").font(Tokens.fixed(.caption, .regular)).foregroundStyle(Tokens.ink2)
                    }
                    Spacer()
                    TimelineView(.everySecond) { _ in
                        let t = c.clockText()
                        Text(t).font(Tokens.fixed(.callout, .semibold, rounded: true)).monospacedDigit()
                    }
                }.padding(10)
                if let r = c.latest, !c.isPaused {
                    HStack(spacing: 8) {
                        RingView(r.ring, color: r.tint).frame(width: 14, height: 14)
                        Text("Reading \(r.appText): \(r.call == .on ? "matches the task" : (r.call == .off ? "looks off topic" : "not sure"))").font(Tokens.fixed(.caption, .regular)).foregroundStyle(Tokens.ink2).lineLimit(1)
                    }.padding(.horizontal, 10).padding(.bottom, 6)
                }
                // A question waiting for an answer comes first, so it can be answered here as well as on the banner.
                if c.checkIn != nil {
                    Divider().padding(.vertical, 4)
                    prompt(NudgeCopy.checkInTitle(task: c.taskName))
                    item("Back to task") { c.answerCheckIn(onTask: false) }
                    item("Yes, this is part of it") { c.answerCheckIn(onTask: true) }
                } else if let p = c.rhythmPrompt {
                    Divider().padding(.vertical, 4)
                    prompt(CueCopy.rhythmTitle(p.kind, task: c.taskName))
                    switch p.kind {
                    case .checkIn:
                        item("Yes, keep going") { c.rhythmKeepGoing() }
                        item("Take a \(c.rhythmBreakMinutes) minute break") { c.rhythmTakeBreak() }
                    case .breakDue:
                        item("Start the break") { c.rhythmTakeBreak() }
                        item("Five more minutes") { c.rhythmKeepGoing() }
                    }
                }
                Divider().padding(.vertical, 4)
                item(c.isPaused ? "Resume" : "Pause") { c.act(c.isPaused ? .resume : .pause) }
                Menu("Take a break") { ForEach([5, 10, 15], id: \.self) { m in Button("\(m) minutes") { c.act(.breakTime, minutes: m) } } }.menuStyle(.borderlessButton).padding(.horizontal, 10).frame(height: 30)
                Menu("Snooze") { ForEach([15, 30, 60], id: \.self) { m in Button("\(m) minutes") { c.act(.snooze, minutes: m) } } }.menuStyle(.borderlessButton).padding(.horizontal, 10).frame(height: 30)
                Divider().padding(.vertical, 4)
                item("Set next step") { c.manualNextStep = true; openApp() }
                item("That was fine") { c.claimOnTask() }
                item("Back to task") { c.act(.backToTask) }
                Divider().padding(.vertical, 4)
                if c.mode == .timed { item("Extend 5 minutes") { c.act(.extend, minutes: 5) } }
                item("End session") { c.end() }
            } else {
                Text("No session running").font(Tokens.fixed(.callout, .semibold, rounded: true)).padding(10)
                item("Start a session") { c.requestStart(); openApp() }
            }
            if c.visibleUpdate != nil {
                Divider().padding(.vertical, 4)
                item("Restart to update") { c.installUpdate() }
            }
            Divider().padding(.vertical, 4)
            item("Open Focus", openApp)
        }
        .padding(8).frame(width: 296)
    }

    func prompt(_ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle").font(.system(size: 10, weight: .semibold)).foregroundStyle(Tokens.accent)
            Text(title).font(Tokens.fixed(.caption, .semibold)).foregroundStyle(Tokens.ink2).lineLimit(2)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
    }

    func item(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { Text(title); Spacer() }.padding(.horizontal, 10).frame(height: 30).contentShape(Rectangle()) }
            .buttonStyle(MenuRowStyle()).font(Tokens.fixed(.body, .regular))
    }
}

/// A menu row that lights under the pointer, as a real menu does, so you can see what a click will hit.
struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration) }
    struct Inner: View {
        let configuration: Configuration
        @State private var hover = false
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 6).fill(configuration.isPressed ? Tokens.controlHover : (hover ? Tokens.control : .clear)))
                .animation(Motion.hover, value: hover)
                .onHover { hover = $0 }
        }
    }
}
