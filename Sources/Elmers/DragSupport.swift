import AppKit
import ElmersCore

enum DragSupport {
    /// Elmers-private type naming the dragged items, so a drop on a pinboard pill pins them and a drop inside a
    /// pinboard reorders them. Other apps ignore it.
    static let itemIDsType = NSPasteboard.PasteboardType("app.elmers.item-ids")
    /// A card drags the same pasteboard items a paste writes: every stored item, each with every
    /// representation, so RTF stays RTF and every file of a multi-file copy arrives as its original file URL.
    /// This goes through AppKit rather than SwiftUI's `onDrag`, which copies dragged files into a cache
    /// folder and hands the destination that copy.
    static func draggingItems(for item: ClipboardItem, frame: NSRect, image: NSImage?) -> [NSDraggingItem] {
        // Large content is read from the database here; an item that cannot be read whole is not dragged at all.
        guard let stored = try? item.payload.materializedItems() else { return [] }
        let items = PasteboardCodec.pasteboardItems(for: ClipboardPayload(items: stored))
        items.first?.setString(item.id.uuidString, forType: itemIDsType)
        return items.enumerated().map { index, pasteboardItem in
            let dragging = NSDraggingItem(pasteboardWriter: pasteboardItem)
            // Stack the extra items slightly offset behind the card image, as Finder does for several files.
            let offset = CGFloat(min(index, 3)) * 4
            dragging.setDraggingFrame(frame.offsetBy(dx: offset, dy: -offset), contents: index == 0 ? image : nil)
            return dragging
        }
    }
    /// The Elmers items a drop carries, if it came from a card.
    static func droppedItemIDs(_ providers: [NSItemProvider], completion: @escaping @MainActor ([UUID]) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(itemIDsType.rawValue) }) else { return false }
        _ = provider.loadDataRepresentation(forTypeIdentifier: itemIDsType.rawValue) { data, _ in
            let ids = data.flatMap { String(data: $0, encoding: .utf8) }?.split(separator: "\n").compactMap { UUID(uuidString: String($0)) } ?? []
            Task { @MainActor in completion(ids) }
        }
        return true
    }
    /// The pinboard a drop carries, if a pill was dragged.
    static func droppedBoardID(_ providers: [NSItemProvider], completion: @escaping @MainActor (UUID) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { string, _ in
            guard let id = (string as? String).flatMap(UUID.init(uuidString:)) else { return }
            Task { @MainActor in completion(id) }
        }
        return true
    }
}
