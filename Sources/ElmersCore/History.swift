import Foundation

public struct History: Codable, Sendable {
    public private(set) var items: [ClipboardItem] = []
    public private(set) var boards: [Pinboard] = []
    public init() {}
    init(items: [ClipboardItem], boards: [Pinboard]) { self.items = items; self.boards = boards }

    @discardableResult public mutating func capture(_ payload: ClipboardPayload, source: String, sourceBundleID: String? = nil, at date: Date = Date(), screenshot: ScreenshotOrigin? = nil, imageDigest: String? = nil) -> ClipboardItem {
        let fingerprint = payload.fingerprint
        var item: ClipboardItem
        if let index = items.firstIndex(where: { $0.fingerprint == fingerprint ||
            (imageDigest != nil && $0.imageDigest == imageDigest &&
             ($0.screenshot != nil) != (screenshot != nil) && abs($0.copiedAt.timeIntervalSince(date)) <= 10 &&
             $0.kind.isImage && payload.kind.isImage) }) {
            item = items.remove(at: index)
            if item.fingerprint != fingerprint, let incoming = payload.items.first {
                let origin = item.screenshot
                let recognized = item.recognizedText
                // The stored item's large representations may still be in the database. If they cannot be read,
                // merging would drop them, so the clipboard copy replaces the item instead, or it is left as is.
                if var representations = (try? item.payload.materializedItems())?.first {
                    // Prefer clipboard formats on conflicts and retain other useful encodings if within the capture bound.
                    representations.merge(incoming) { old, new in screenshot == nil ? new : old }
                    let merged = ClipboardPayload(items: [representations])
                    if merged.byteCount <= ScreenshotImage.maximumBytes { item.payload = merged } else if screenshot == nil { item.payload = payload }
                } else if screenshot == nil { item.payload = payload }
                item.screenshot = origin; item.recognizedText = recognized
            }
            item.copiedAt = max(item.copiedAt, date); item.source = source; item.sourceBundleID = sourceBundleID
        } else { item = ClipboardItem(payload: payload, source: source, sourceBundleID: sourceBundleID, at: date) }
        if let screenshot { item.screenshot = screenshot }
        if let imageDigest { item.imageDigest = imageDigest }
        // Background image decoding can complete after a newer text capture.
        let insertion = items.firstIndex { $0.copiedAt <= item.copiedAt } ?? items.endIndex
        items.insert(item, at: insertion)
        return item
    }
    public func filtered(query: String = "", kind: ContentKind? = nil, boardID: UUID? = nil) -> [ClipboardItem] {
        // Type words are consumed by the search field before the query reaches here (see SearchQuery).
        let tokens = query.split(whereSeparator: \.isWhitespace).map { Array(ClipboardItem.fold(String($0)).utf8) }
        return items.filter { item in
            (kind == nil || item.kind == kind || (kind == .image && item.kind.isImage)) && (boardID == nil || item.boardIDs.contains(boardID!)) &&
            tokens.allSatisfy { token in Self.contains(item.searchKey, token) }
        }
    }
    /// Byte search of a folded token in a folded key. The key joins fields with NUL, so a token never spans two.
    static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty else { return true }
        return haystack.withUnsafeBytes { key in needle.withUnsafeBytes { word in
            memmem(key.baseAddress, key.count, word.baseAddress, word.count) != nil
        } }
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
    public mutating func setRecognizedText(_ id: UUID, _ text: String?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].recognizedText = text
    }
    public mutating func setLinkPreview(_ id: UUID, _ preview: LinkPreview?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].linkPreview = preview
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
