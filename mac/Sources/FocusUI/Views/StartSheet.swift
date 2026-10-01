import SwiftUI
import FocusBrain

public struct StartSheet: View {
    @Bindable var c: SessionController
    @Binding var isPresented: Bool
    @State private var task = ""
    @State private var timed = false
    @State private var minutes = 50
    @FocusState private var focused: Bool

    public init(controller: SessionController, isPresented: Binding<Bool>) { self.c = controller; self._isPresented = isPresented }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What are you working on?").font(Tokens.rounded(22, .semibold))
            TextField("Lab report on pendulums", text: $task)
                .textFieldStyle(.plain).font(Tokens.text(16)).padding(.horizontal, 14).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Tokens.control))
                .focused($focused).onSubmit(start)
            HStack(spacing: 6) {
                chip("Open", on: !timed) { timed = false }
                chip("Timed", on: timed) { timed = true }
                if timed {
                    Picker("Length", selection: $minutes) { ForEach([25, 50, 90], id: \.self) { Text("\($0) min").tag($0) } }
                        .pickerStyle(.menu).labelsHidden().frame(width: 100)
                }
            }
            HStack {
                Button("Start") { start() }.buttonStyle(FocusButtonStyle(.primary, expand: true)).disabled(trimmed.isEmpty)
                    .keyboardShortcut(.defaultAction)
                Button("Cancel") { isPresented = false }.buttonStyle(FocusButtonStyle(.plain)).keyboardShortcut(.cancelAction)
            }
        }
        .padding(24).frame(width: 480)
        .onAppear { focused = true }
    }

    var trimmed: String { task.trimmingCharacters(in: .whitespacesAndNewlines) }

    func start() {
        guard !trimmed.isEmpty else { return }
        c.begin(task: trimmed, mode: timed ? .timed : .open, duration: timed ? Double(minutes * 60) : nil, autoTick: true)
        isPresented = false
    }

    func chip(_ label: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(label, action: action).buttonStyle(.plain).font(Tokens.text(12.5, .medium)).padding(.horizontal, 12).frame(height: 28)
            .background(Capsule().fill(on ? Tokens.accentSoft : Tokens.control))
            .overlay { if on { Capsule().strokeBorder(Tokens.accent, lineWidth: 1.5) } }
            .accessibilityAddTraits(on ? .isSelected : [])
    }
}
