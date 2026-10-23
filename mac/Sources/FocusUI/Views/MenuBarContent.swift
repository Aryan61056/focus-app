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
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.taskName).font(Tokens.fixed(.callout, .semibold, rounded: true)).lineLimit(1)
                        Text("\(c.presenceLabel) · \(c.mode == .timed ? "Timed" : "Open")").font(Tokens.fixed(.caption, .regular)).foregroundStyle(Tokens.ink2)
                    }
                    Spacer()
                    TimelineView(.everySecond) { _ in
                        let t = c.clockText()
                        Text(t).font(Tokens.fixed(.title3, .semibold, rounded: true)).monospacedDigit()
                    }
                }.padding(10)
                // What Focus is reading, as the app and its call: the sparkle marks the AI's work, the small ring says the call by shape.
                if let r = c.latest, !c.isPaused {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle").font(.system(size: 9, weight: .semibold)).foregroundStyle(Tokens.accent)
                        Text(r.appText).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 6)
                        RingView(r.ring, color: r.tint).frame(width: 11, height: 11)
                        Text(r.call == .on ? "On task" : (r.call == .off ? "Off topic" : "Not sure")).foregroundStyle(Tokens.ink)
                    }
                    .font(Tokens.fixed(.caption, .regular)).foregroundStyle(Tokens.ink2)
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Tokens.control))
                    .padding(.horizontal, 4).padding(.bottom, 6)
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
                // The session's controls as four tiles, the way Control Center lays out its toggles.
                HStack(spacing: 6) {
                    tile(c.isPaused ? "Resume" : "Pause", c.isPaused ? "play.fill" : "pause.fill") { c.act(c.isPaused ? .resume : .pause) }
                    tileMenu("Break", "cup.and.saucer.fill", [5, 10, 15]) { c.act(.breakTime, minutes: $0) }
                    tileMenu("Snooze", "moon.zzz.fill", [15, 30, 60]) { c.act(.snooze, minutes: $0) }
                    tile("End", "stop.fill") { c.end() }
                }
                .padding(.horizontal, 4).padding(.vertical, 6)
                Divider().padding(.vertical, 4)
                BackToTaskRow(c: c)
                OtherPlacesRows(c: c)
                item("This is part of it") { c.claimOnTask() }
                item("I'm stuck") { c.requestNextActions(); openApp() }
                if c.mode == .timed { item("Add 5 minutes") { c.act(.extend, minutes: 5) } }
            } else {
                Text("No session running").font(Tokens.fixed(.callout, .semibold, rounded: true)).padding(10)
                if c.shortSessionOffer {
                    item("Keep going") { c.keepGoing() }
                    item("Finish five minutes") { c.finishFiveMinutes() }
                    Divider().padding(.vertical, 4)
                }
                item("Start a session") { c.requestStart(); openApp() }
                item("Just five minutes") { c.startDraft.length = .minutes; c.startDraft.minutes = 5; c.startDraft.lengthTouched = true; c.requestStart(); openApp() }
            }
            if c.updateSource != nil, !c.isActive {
                Divider().padding(.vertical, 4)
                item(c.updateBuild == .building ? "Updating\u{2026}" : c.visibleUpdate != nil ? "Restart to update" : "Update Hushd") { c.updateNow() }
            }
            Divider().padding(.vertical, 4)
            item("Park a thought") { c.onParkThought?() }
            item(c.phoneState == .none ? "Connect your iPhone\u{2026}" : "Your iPhone\u{2026}") { c.onOpenPhone?() }
            item("Open Hushd", openApp)
        }
        .padding(8).frame(width: 296)
    }

    /// One control tile: a symbol over a one-word label.
    func tile(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { TileFace(title: title, symbol: symbol) }.buttonStyle(MenuRowStyle(radius: 10))
    }

    /// A tile that opens a short menu of lengths.
    func tileMenu(_ title: String, _ symbol: String, _ minutes: [Int], _ pick: @escaping (Int) -> Void) -> some View {
        Menu { ForEach(minutes, id: \.self) { m in Button("\(m) minutes") { pick(m) } } } label: { TileFace(title: title, symbol: symbol) }
            .menuStyle(.button).buttonStyle(MenuRowStyle(radius: 10)).menuIndicator(.hidden)
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
    var radius: CGFloat = 6
    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration, radius: radius) }
    struct Inner: View {
        let configuration: Configuration
        var radius: CGFloat
        @State private var hover = false
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(configuration.isPressed ? Tokens.controlHover : (hover ? Tokens.control : .clear)))
                .animation(Motion.hover, value: hover)
                .onHover { hover = $0 }
        }
    }
}

/// A control tile's face: the symbol on a soft tile, the word under it.
struct TileFace: View {
    var title: String
    var symbol: String
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tokens.ink)
                .frame(width: 34, height: 34).background(Circle().fill(Tokens.control))
            Text(title).font(Tokens.fixed(.caption2, .medium)).foregroundStyle(Tokens.ink2).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6).contentShape(Rectangle())
    }
}
