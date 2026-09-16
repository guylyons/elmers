import AppKit
import ElmersCore

enum DragSupport {
    /// Every representation of the first pasteboard item is offered under its own type, so a drop into
    /// another app receives the same formats a paste would (RTF stays RTF, files stay file URLs).
    static func itemProvider(for item: ClipboardItem) -> NSItemProvider {
        let provider = NSItemProvider()
        guard let representations = item.payload.items.first else { return provider }
        for (type, data) in representations where !type.hasPrefix("dyn.") && type.contains(".") {
            provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .all) { completion in
                completion(data, nil); return nil
            }
        }
        if let title = item.title { provider.suggestedName = title }
        return provider
    }
}
