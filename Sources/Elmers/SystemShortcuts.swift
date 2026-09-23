import Carbon.HIToolbox
import ElmersCore

/// Key combinations macOS reserves system-wide (System Settings › Keyboard › Keyboard Shortcuts), read through
/// Carbon's symbolic hot key table. Paste 6.3.11 refuses to record these.
enum SystemShortcuts {
    static let usedMessage = "This combination cannot be used because it is already used by a system-wide keyboard shortcut.\nIf you really want to use this key combination, most shortcuts can be changed in the Keyboard & Mouse panel in System Settings."
    /// Paste's note for Option-only shortcuts, which the system cannot deliver reliably before macOS 15.2.
    static let optionMessage = "Shortcuts using the Option key without Command or Control may not work correctly before macOS 15.2. Please consider updating to the latest version of macOS."

    static func isReserved(_ stroke: KeyStroke) -> Bool {
        var table: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&table) == noErr, let entries = table?.takeRetainedValue() as? [[String: Any]] else { return false }
        return entries.contains { entry in
            guard (entry[kHISymbolicHotKeyEnabled] as? Bool) == true, let code = entry[kHISymbolicHotKeyCode] as? Int,
                  let flags = entry[kHISymbolicHotKeyModifiers] as? Int else { return false }
            return UInt16(code) == stroke.keyCode && modifiers(carbon: flags) == stroke.modifiers
        }
    }
    static func needsOptionWarning(_ stroke: KeyStroke) -> Bool {
        guard stroke.modifiers.contains(.option), stroke.modifiers.isDisjoint(with: [.command, .control]) else { return false }
        if #available(macOS 15.2, *) { return false }
        return true
    }
    private static func modifiers(carbon flags: Int) -> KeyModifiers {
        var result: KeyModifiers = []
        if flags & cmdKey != 0 { result.insert(.command) }
        if flags & shiftKey != 0 { result.insert(.shift) }
        if flags & optionKey != 0 { result.insert(.option) }
        if flags & controlKey != 0 { result.insert(.control) }
        return result
    }
}
