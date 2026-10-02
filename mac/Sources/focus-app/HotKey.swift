import AppKit
import Carbon.HIToolbox

/// One global shortcut, Control-Option-F, with no permission needed (Carbon hot keys are not event taps).
/// Idle: opens the window with the start sheet, already showing the project you worked on last. During a session: pause or resume.
@MainActor
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    nonisolated(unsafe) private static var action: (() -> Void)?

    func register(_ action: @escaping () -> Void) {
        guard ref == nil else { return }
        Self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { GlobalHotKey.action?() }
            return noErr
        }, 1, &spec, nil, &handler)
        RegisterEventHotKey(UInt32(kVK_ANSI_F), UInt32(controlKey | optionKey), EventHotKeyID(signature: OSType(0x464F4355), id: 1), GetApplicationEventTarget(), 0, &ref)
    }
}
