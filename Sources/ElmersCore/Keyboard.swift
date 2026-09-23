import Foundation

public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let command = Self(rawValue: 1)
    public static let shift = Self(rawValue: 2)
    public static let option = Self(rawValue: 4)
    public static let control = Self(rawValue: 8)
    public var label: String {
        (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "") + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
    }
}
public struct KeyStroke: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: KeyModifiers
    public init(_ code: UInt16, _ modifiers: KeyModifiers = []) { keyCode = code; self.modifiers = modifiers }
    public var label: String {
        let keys: [UInt16: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",36:"↩",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",48:"⇥",49:"Space",50:"`",51:"⌫",53:"Esc",123:"←",124:"→",125:"↓",126:"↑"]
        return modifiers.label + (keys[keyCode] ?? "Key \(keyCode)")
    }
}
public struct ShortcutSettings: Codable, Equatable, Sendable {
    public var activation: KeyStroke? = .init(9, [.command, .shift])
    public var stack: KeyStroke? = .init(8, [.command, .shift])
    public var nextBoard: KeyStroke? = .init(124, .command)
    public var previousBoard: KeyStroke? = .init(123, .command)
    public var quickPasteModifier: KeyModifiers = .command
    public var plainTextModifier: KeyModifiers = .shift
    public init() {}
    public var validationError: String? {
        if quickPasteModifier == plainTextModifier { return String(localized: "Quick Paste and Plain Text mode need different modifiers.") }
        let bindings = [activation, nextBoard, previousBoard].compactMap { $0 }
        if Set(bindings).count != bindings.count { return String(localized: "Choose a different shortcut for each action.") }
        var reserved = self
        reserved.activation = nil; reserved.nextBoard = nil; reserved.previousBoard = nil
        for binding in bindings {
            guard let command = KeyboardRouter.command(for: binding, context: .results, settings: reserved) else { continue }
            // Paste 6.3.11's wording when the menu already owns the combination.
            if let item = Self.menuItemTitle(command) { return String(localized: "This shortcut cannot be used because it is already used by the menu item ‘\(item)’.") }
            return String(localized: "This shortcut is already used by a clipboard command. Choose another combination.")
        }
        return nil
    }
    /// The app menu's items that carry a key equivalent (`AppMenu`), by the command they run.
    static func menuItemTitle(_ command: KeyboardCommand) -> String? {
        switch command {
        case .newText: return String(localized: "New Text Item")
        case .settings: return String(localized: "Settings…")
        case .pause: return String(localized: "Pause")
        case .quit: return String(localized: "Quit Elmers")
        default: return nil
        }
    }
}
public enum KeyboardContext { case results, search, editor }
public enum KeyboardCommand: Equatable {
    case move(Int, extend: Bool), first, last, selectAll, paste(plain: Bool), quickPaste(Int, plain: Bool)
    case copy, preview, open, rename, edit, writingTools, newText, delete, undo, redo, focusSearch, focusResults, filters
    case newBoard, nextBoard, previousBoard, pause, settings, quit, escape, showInHistory
}
public enum KeyboardRouter {
    public static func command(for stroke: KeyStroke, context: KeyboardContext, settings: ShortcutSettings = .init()) -> KeyboardCommand? {
        guard context != .editor else { return nil }
        let key = stroke.keyCode, modifiers = stroke.modifiers
        let plain = modifiers.contains(settings.plainTextModifier)
        if stroke == settings.nextBoard { return .nextBoard }
        if stroke == settings.previousBoard { return .previousBoard }
        let numbers: [UInt16] = [18,19,20,21,23,22,26,28,25]
        if let number = numbers.firstIndex(of: key), modifiers == settings.quickPasteModifier || modifiers == settings.quickPasteModifier.union(settings.plainTextModifier) { return .quickPaste(number, plain: plain) }
        if key == 53 && modifiers.isEmpty { return .escape }
        if key == 48 && (modifiers.isEmpty || modifiers == .shift) { return .move(modifiers == .shift ? -1 : 1, extend: false) }
        // Return pastes the selection even while the search field has focus.
        if [36,76].contains(key), modifiers.isEmpty || modifiers == settings.plainTextModifier { return .paste(plain: plain) }
        if modifiers == .command {
            switch key {
            case 3: return context == .search ? .filters : .focusSearch
            case 43: return .settings
            case 12: return .quit
            case 17: return .pause
            case 45: return .newText
            case 126: return .first
            case 125: return .last
            default: break
            }
        }
        if modifiers == [.command, .shift], key == 45 { return .newBoard }
        // Left/Right move the card selection even while typing a query, so type → arrow → Return works
        // without Tab. Option-arrows and Home/End still move the text cursor.
        if modifiers.isEmpty || modifiers == .shift {
            if key == 123 { return .move(-1, extend: modifiers == .shift) }
            if key == 124 { return .move(1, extend: modifiers == .shift) }
        }
        guard context == .results else { return nil }
        if modifiers == .command {
            switch key {
            case 0: return .selectAll
            case 8: return .copy
            case 31: return .open
            case 15: return .rename
            case 14: return .edit
            case 6: return .undo
            case 5: return .showInHistory
            default: return nil
            }
        }
        if modifiers == [.command, .shift], key == 6 { return .redo }
        if modifiers == [.command, .shift], key == 14 { return .writingTools }
        if modifiers.isEmpty {
            switch key { case 49: return .preview; case 51,117: return .delete; default: break }
        }
        return nil
    }
}
