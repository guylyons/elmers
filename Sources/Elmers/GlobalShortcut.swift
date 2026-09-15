import Carbon
import ElmersCore

final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onActivate: (() -> Void)?
    @discardableResult func register(_ binding: KeyStroke? = ShortcutSettings().activation) -> Bool {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
        guard let binding else { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            shortcut.onActivate?()
            return noErr
        }, 1, &eventType, context, &handler)
        guard installed == noErr else { return false }
        let id = EventHotKeyID(signature: 0x454C4D52, id: 1)
        var modifiers: UInt32 = 0
        if binding.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if binding.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if binding.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if binding.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        return RegisterEventHotKey(UInt32(binding.keyCode), modifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }
    deinit { if let hotKey { UnregisterEventHotKey(hotKey) }; if let handler { RemoveEventHandler(handler) } }
}
