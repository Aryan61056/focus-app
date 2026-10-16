import AppKit
import Carbon.HIToolbox

/// Carbon hot keys need no event tap or Accessibility permission. IDs keep independent actions separate.
@MainActor final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var combination: (UInt32, UInt32)?
    private let id: UInt32
    private static var nextID: UInt32 = 0
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handler: EventHandlerRef?
    init() { Self.nextID += 1; id = Self.nextID }
    @discardableResult func register(keyCode: UInt32 = UInt32(kVK_ANSI_F), modifiers: UInt32 = UInt32(controlKey | optionKey), _ action: @escaping () -> Void) -> Bool {
        if Self.handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var key = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
                guard status == noErr else { return status }
                let id = key.id
                Task { @MainActor in GlobalHotKey.actions[id]?() }
                return noErr
            }, 1, &spec, nil, &Self.handler)
            guard status == noErr else { return false }
        }
        if combination?.0 == keyCode && combination?.1 == modifiers { Self.actions[id] = action; return true }
        var replacement: EventHotKeyRef?
        guard RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x464F4355), id: id), GetApplicationEventTarget(), 0, &replacement) == noErr else {
            if let ref { UnregisterEventHotKey(ref) }; ref = nil; combination = nil; Self.actions[id] = nil
            return false
        }
        if let ref { UnregisterEventHotKey(ref) }
        ref = replacement; combination = (keyCode, modifiers); Self.actions[id] = action
        return true
    }
}
