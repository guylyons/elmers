import AppKit
import ElmersCore

enum DragSupport {
    /// A card drags the same pasteboard items a paste writes: every stored item, each with every
    /// representation, so RTF stays RTF and every file of a multi-file copy arrives as its original file URL.
    /// This goes through AppKit rather than SwiftUI's `onDrag`, which copies dragged files into a cache
    /// folder and hands the destination that copy.
    static func draggingItems(for item: ClipboardItem, frame: NSRect, image: NSImage?) -> [NSDraggingItem] {
        // Large content is read from the database here; an item that cannot be read whole is not dragged at all.
        guard let stored = try? item.payload.materializedItems() else { return [] }
        let items = PasteboardCodec.pasteboardItems(for: ClipboardPayload(items: stored))
        return items.enumerated().map { index, pasteboardItem in
            let dragging = NSDraggingItem(pasteboardWriter: pasteboardItem)
            // Stack the extra items slightly offset behind the card image, as Finder does for several files.
            let offset = CGFloat(min(index, 3)) * 4
            dragging.setDraggingFrame(frame.offsetBy(dx: offset, dy: -offset), contents: index == 0 ? image : nil)
            return dragging
        }
    }
}
