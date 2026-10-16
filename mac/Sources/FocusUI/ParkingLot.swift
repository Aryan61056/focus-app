import SwiftUI
import AppKit
import Carbon.HIToolbox

/// User-authored text only. No readings or model output enter this store.
public struct ParkedThought: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var text: String
    public var completed = false
    public var createdAt = Date()
    public init(text: String) { self.text = text }
}

public enum ParkingShortcut: String, CaseIterable, Identifiable, Sendable {
    case controlOptionP, controlOptionT, commandControlP
    public var id: Self { self }
    public var label: String {
        switch self { case .controlOptionP: return "⌃⌥P"; case .controlOptionT: return "⌃⌥T"; case .commandControlP: return "⌃⌘P" }
    }
    public var key: String { self == .controlOptionT ? "t" : "p" }
    public var keyCode: UInt32 { UInt32(self == .controlOptionT ? kVK_ANSI_T : kVK_ANSI_P) }
    public var carbonModifiers: UInt32 { UInt32(controlKey | (self == .commandControlP ? cmdKey : optionKey)) }
    public var modifiers: SwiftUI.EventModifiers { self == .commandControlP ? [.control, .command] : [.control, .option] }
}

/// One reusable native panel. Closing releases the typed draft; Return saves before dismissing.
@MainActor public final class ParkingPanelController: NSObject, NSWindowDelegate {
    private let controller: SessionController
    private var panel: ParkingPanel?
    private var previousApp: NSRunningApplication?
    public init(controller: SessionController) { self.controller = controller }
    public func show() {
        if let panel, panel.isVisible { panel.makeKeyAndOrderFront(nil); return }
        previousApp = NSWorkspace.shared.frontmostApplication
        let panel = ParkingPanel(contentRect: NSRect(x: 0, y: 0, width: 490, height: 172), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "Park a thought"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true; panel.level = .floating; panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true; panel.delegate = self
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true; panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = NSHostingView(rootView: ParkingInput { [weak self] text in
            guard let self else { return false }
            if let text, self.controller.store?.park(text) != true { return false }
            self.dismiss(); return true
        })
        self.panel = panel; panel.center(); NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
    }
    public func dismiss() {
        panel?.orderOut(nil); panel?.contentView = nil; panel = nil
        if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp.activate() }
        previousApp = nil
    }
    public func windowShouldClose(_ sender: NSWindow) -> Bool { dismiss(); return false }
}
private final class ParkingPanel: NSPanel { override var canBecomeKey: Bool { true } }

private struct ParkingInput: View {
    var finish: (String?) -> Bool
    @State private var text = ProcessInfo.processInfo.environment["FOCUS_DEMO"] == "1" && (ProcessInfo.processInfo.environment["FOCUS_DEMO_ACTIONS"] ?? "").contains("park-long") ? String(repeating: "Synthetic thought ", count: 120) : ""
    @State private var appeared = false
    @State private var saveFailed = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Park a thought").font(Tokens.rounded(20))
            TextField("Thought", text: $text, prompt: Text("Save it for later").foregroundStyle(Tokens.ink2)).textFieldStyle(.plain)
                .padding(10).background(Tokens.well, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Tokens.accent : Tokens.line, lineWidth: focused ? 2 : 1) }
                .focused($focused).onSubmit(save).accessibilityLabel("Thought to save for later")
            HStack {
                Text(saveFailed ? "Couldn’t save. Try again." : (text.count > 2000 ? "Keep this under 2,000 characters." : "Return to save · Esc to cancel")).font(Tokens.text(12)).foregroundStyle(Tokens.ink)
                Spacer()
                Button("Save", action: save).keyboardShortcut(.defaultAction).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000)
                    .help("Save your thought and return to what you were doing")
            }
        }
        .padding(24).frame(width: 490, height: 172, alignment: .topLeading)
        .background(Tokens.window2.opacity(0.92), in: RoundedRectangle(cornerRadius: 20))
        .glassSurface(RoundedRectangle(cornerRadius: 20), fallback: Tokens.window2)
        .opacity(appeared ? 1 : 0).scaleEffect(reduceMotion || appeared ? 1 : 0.96)
        .motion(Motion.notchSettle, value: appeared)
        .task { appeared = true; await Task.yield(); focused = true }
        .onExitCommand { _ = finish(nil) }
    }
    func save() { guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 2000 else { return }; saveFailed = !finish(text) }
}

struct ParkingLotCard: View {
    @Bindable var store: DataStore
    @State private var showAll = ProcessInfo.processInfo.environment["FOCUS_DEMO"] == "1" && (ProcessInfo.processInfo.environment["FOCUS_DEMO_ACTIONS"] ?? "").contains("parked-all")
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("For later").font(Tokens.rounded(18))
                    Spacer()
                    Menu {
                        Button("Clear completed") { store.clearThoughts(completedOnly: true) }.disabled(!store.thoughts.contains { $0.completed })
                        Button("Clear all", role: .destructive) { store.clearThoughts() }
                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().help("Manage saved thoughts").accessibilityLabel("Manage saved thoughts")
                }
                if showAll {
                    ScrollView { VStack(alignment: .leading, spacing: 12) { rows } }.frame(height: 220)
                } else { rows }
                if store.thoughts.count > 3 { Button(showAll ? "Show less" : "Show all \(store.thoughts.count)") { showAll.toggle() }.buttonStyle(FocusButtonStyle(.plain, small: true)) }
            }
        }.motion(Motion.notchSettle, value: store.thoughts).motion(Motion.notchSettle, value: showAll)
    }
    var rows: some View {
        ForEach(Array(store.thoughts.prefix(showAll ? store.thoughts.count : 3))) { thought in
                    Toggle(isOn: Binding(get: { thought.completed }, set: { store.completeThought(thought.id, completed: $0) })) {
                        Text(thought.text).lineLimit(3).help(thought.text).strikethrough(thought.completed).font(Tokens.text(14)).foregroundStyle(thought.completed ? Tokens.ink2 : Tokens.ink)
                    }.toggleStyle(.checkbox).help("Mark this thought complete").transition(.rise(reduce: reduceMotion))
                }
    }

}
