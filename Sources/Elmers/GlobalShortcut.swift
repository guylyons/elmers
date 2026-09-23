import Carbon
import ElmersCore

/// One system-wide shortcut. Several can be registered at once (history, Paste Stack, the Stack's ⌘V); each handler
/// answers only to its own hot key ID.
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let identifier: UInt32
    private static var nextIdentifier: UInt32 = 1
    var onActivate: (() -> Void)?
    init() { identifier = Self.nextIdentifier; Self.nextIdentifier += 1 }
    @discardableResult func register(_ binding: KeyStroke? = ShortcutSettings().activation) -> Bool {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
        guard let binding else { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard pressed.id == shortcut.identifier else { return OSStatus(eventNotHandledErr) }
            shortcut.onActivate?()
            return noErr
        }, 1, &eventType, context, &handler)
        guard installed == noErr else { return false }
        let id = EventHotKeyID(signature: 0x454C4D52, id: identifier)
        var modifiers: UInt32 = 0
        if binding.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if binding.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if binding.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if binding.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        return RegisterEventHotKey(UInt32(binding.keyCode), modifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }
    deinit { if let hotKey { UnregisterEventHotKey(hotKey) }; if let handler { RemoveEventHandler(handler) } }
}
