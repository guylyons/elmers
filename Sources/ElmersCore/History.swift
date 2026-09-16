import Foundation

public struct History: Codable, Sendable {
    public private(set) var items: [ClipboardItem] = []
    public private(set) var boards: [Pinboard] = []
    public init() {}

    @discardableResult public mutating func capture(_ payload: ClipboardPayload, source: String, sourceBundleID: String? = nil, at date: Date = Date()) -> ClipboardItem {
        let fingerprint = payload.fingerprint
        var item: ClipboardItem
        if let index = items.firstIndex(where: { $0.fingerprint == fingerprint }) {
            item = items.remove(at: index)
            item.copiedAt = date; item.source = source; item.sourceBundleID = sourceBundleID
        } else { item = ClipboardItem(payload: payload, source: source, sourceBundleID: sourceBundleID, at: date) }
        items.insert(item, at: 0)
        return item
    }
    public func filtered(query: String = "", kind: ContentKind? = nil, boardID: UUID? = nil) -> [ClipboardItem] {
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return items.filter { item in
            (kind == nil || item.kind == kind) && (boardID == nil || item.boardIDs.contains(boardID!)) &&
            tokens.allSatisfy { token in
                [item.text, item.source, item.title ?? ""].contains {
                    $0.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                }
            }
        }
    }
    @discardableResult public mutating func createBoard(name: String) -> Pinboard {
        let board = Pinboard(name: name.trimmingCharacters(in: .whitespacesAndNewlines), colorIndex: boards.count % Pinboard.colorCount)
        boards.append(board); return board
    }
    public mutating func renameBoard(_ id: UUID, to name: String) {
        guard let index = boards.firstIndex(where: { $0.id == id }), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        boards[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public mutating func deleteBoard(_ id: UUID) {
        boards.removeAll { $0.id == id }
        for index in items.indices { items[index].boardIDs.remove(id) }
    }
    public mutating func pin(_ id: UUID, to boardID: UUID) {
        guard boards.contains(where: { $0.id == boardID }), let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].boardIDs.insert(boardID)
    }
    public mutating func unpin(_ id: UUID, from boardID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].boardIDs.remove(boardID)
    }
    public mutating func delete(_ id: UUID) { items.removeAll { $0.id == id } }
    public mutating func renameItem(_ id: UUID, title: String?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].title = title
    }
    public mutating func editItem(_ id: UUID, payload: ClipboardPayload) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].payload = payload
    }
    public mutating func replaceItem(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        items.append(item)
        items.sort { $0.copiedAt > $1.copiedAt }
    }
    public mutating func restoreItems(_ restored: [ClipboardItem]) {
        for item in restored where !items.contains(where: { $0.id == item.id }) { items.append(item) }
        items.sort { $0.copiedAt > $1.copiedAt }
    }
    public mutating func restoreBoard(_ board: Pinboard, at index: Int, pinnedIDs: Set<UUID>) {
        guard !boards.contains(where: { $0.id == board.id }) else { return }
        boards.insert(board, at: min(max(index, 0), boards.count))
        for itemIndex in items.indices where pinnedIDs.contains(items[itemIndex].id) { items[itemIndex].boardIDs.insert(board.id) }
    }
    public mutating func recolorBoard(_ id: UUID, color: Int) {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { return }
        boards[index].colorIndex = max(0, color) % Pinboard.colorCount
    }
    public mutating func moveBoard(_ id: UUID, before targetID: UUID) {
        guard id != targetID, let old = boards.firstIndex(where: { $0.id == id }) else { return }
        let board = boards.remove(at: old)
        let target = boards.firstIndex(where: { $0.id == targetID }) ?? boards.count
        boards.insert(board, at: target)
    }
    public mutating func prune(before date: Date, limit: Int) {
        var kept = 0
        items.removeAll { item in
            if !item.boardIDs.isEmpty { return false }
            if item.copiedAt < date { return true }
            kept += 1
            return kept > max(0, limit)
        }
    }
}
