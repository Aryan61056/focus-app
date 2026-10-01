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
                    RingView(c.ringState, color: c.ringColor).frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c.taskName).font(Tokens.rounded(15)).lineLimit(1)
                        Text("\(c.presenceLabel) · \(c.mode == .timed ? "Timed" : "Open") session").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
                    }
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { _ in Text(c.clockText()).font(Tokens.rounded(15)).monospacedDigit() }
                }.padding(10)
                Divider().padding(.vertical, 4)
                item(c.isPaused ? "Resume" : "Pause") { c.act(c.isPaused ? .resume : .pause) }
                Menu("Take a break") { ForEach([5, 10, 15], id: \.self) { m in Button("\(m) minutes") { c.act(.breakTime, minutes: m) } } }.menuStyle(.borderlessButton).padding(.horizontal, 10).frame(height: 30)
                Menu("Snooze") { ForEach([15, 30, 60], id: \.self) { m in Button("\(m) minutes") { c.act(.snooze, minutes: m) } } }.menuStyle(.borderlessButton).padding(.horizontal, 10).frame(height: 30)
                Divider().padding(.vertical, 4)
                item("Next step") { c.act(.nextStep) }
                item("That was fine") { c.act(.thatWasFine) }
                item("Back to task") { c.act(.backToTask) }
                Divider().padding(.vertical, 4)
                if c.mode == .timed { item("Extend 5 minutes") { c.act(.extend, minutes: 5) } }
                item("End session") { c.end() }
            } else {
                Text("No session running").font(Tokens.rounded(15)).padding(10)
            }
            Divider().padding(.vertical, 4)
            item("Open Focus", openApp)
        }
        .padding(8).frame(width: 296)
    }

    func item(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { Text(title); Spacer() }.padding(.horizontal, 10).frame(height: 30).contentShape(Rectangle()) }
            .buttonStyle(.plain).font(Tokens.text(13.5))
    }
}
