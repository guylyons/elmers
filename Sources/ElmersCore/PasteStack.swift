import Foundation

/// Paste Stack's queue. Paste 6.3.11's help: while the Stack is open, "everything you copy will get into the stack in
/// order", ⌘V pastes the entries "in order from top to bottom", an arrows button changes the direction, a used
/// entry disappears, and entries can be deleted. Repeated copies stay separate entries; the Stack is independent of
/// history's duplicate merging.
public struct PasteStack: Equatable, Sendable {
    public struct Entry: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let payload: ClipboardPayload
        public let source: String
        public init(payload: ClipboardPayload, source: String) { id = UUID(); self.payload = payload; self.source = source }
    }
    /// In copy order, oldest first.
    public private(set) var entries: [Entry] = []
    /// False pastes the oldest entry first; true, the newest.
    public private(set) var reversed = false
    public init() {}

    public var isEmpty: Bool { entries.isEmpty }
    /// The entries in the order they will be pasted, as the Stack window lists them top to bottom.
    public var pasteOrder: [Entry] { reversed ? entries.reversed() : entries }
    public var next: Entry? { pasteOrder.first }

    @discardableResult public mutating func push(_ payload: ClipboardPayload, source: String) -> Entry {
        let entry = Entry(payload: payload, source: source)
        entries.append(entry)
        return entry
    }
    /// Removes the entry once it has been pasted; an entry that failed to paste stays for the next attempt.
    public mutating func consume(_ id: UUID) { entries.removeAll { $0.id == id } }
    public mutating func remove(_ id: UUID) { entries.removeAll { $0.id == id } }
    public mutating func reverse() { reversed.toggle() }
    public mutating func clear() { entries.removeAll() }
}
