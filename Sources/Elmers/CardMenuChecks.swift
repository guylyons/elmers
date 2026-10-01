#if DEBUG
import AppKit
import ElmersCore

/// The card menu, read from each card's real `NSMenu` as a right-click builds it: an image offers no Paste as Plain
/// Text (it has no text, and choosing it did nothing), and every card with content offers a Share submenu of sharing
/// services (a SwiftUI ShareLink there presented nothing).
@MainActor
enum CardMenuChecks {
    static func run(model: AppModel, controller: PanelController) {
        func fail(_ message: String) -> Never { print("FAIL: \(message)"); fflush(stdout); exit(1) }
        let image = NSImage(size: NSSize(width: 64, height: 48), flipped: false) { rect in NSColor.systemTeal.setFill(); rect.fill(); return true }
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { fail("could not draw the image fixture") }
        model.newText("https://example.com/card-menu-check")
        model.captureForChecks(.init(items: [["public.png": png]]), source: "Preview")
        model.newText("card menu check text")
        controller.show()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard model.visibleItems.prefix(3).map(\.kind) == [.text, .image, .link] else { fail("fixture order \(model.visibleItems.prefix(3).map(\.kind))") }
            /// The menu a right-click on the `index`th card builds.
            @MainActor func menu(forCard index: Int) -> NSMenu {
                let side = model.panelMetrics.cardSide
                let location = NSPoint(x: PanelController.inset + 24 + side / 2 + CGFloat(index) * (side + 24), y: PanelController.inset + 8 + side / 2)
                guard let root = controller.panel.contentView,
                      let event = NSEvent.mouseEvent(with: .rightMouseDown, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                     windowNumber: controller.panel.windowNumber, context: nil, eventNumber: 7, clickCount: 1, pressure: 1) else { fail("no right-click") }
                var view = root.hitTest(root.convert(location, from: nil)); var found: NSMenu?
                while let current = view, found == nil { found = current.menu(for: event); view = current.superview }
                guard let found else { fail("right-clicking card \(index) produced no menu") }
                found.update()
                return found
            }
            func item(_ title: String, in menu: NSMenu) -> NSMenuItem? { menu.items.first { $0.title == String(localized: String.LocalizationValue(title)) } }
            for (index, kind) in [(0, "text"), (1, "image"), (2, "link")] {
                model.select(model.visibleItems[index].id)
                let card = menu(forCard: index)
                guard let share = item("Share", in: card), let services = share.submenu, !services.items.isEmpty else {
                    fail("the \(kind) card has no Share submenu with services: \(card.items.map(\.title))")
                }
                if #available(macOS 15, *) {
                    guard let plain = item("Paste as Plain Text", in: card) else { fail("the \(kind) card has no Paste as Plain Text") }
                    guard plain.isEnabled == (kind != "image") else { fail("Paste as Plain Text on the \(kind) card is \(plain.isEnabled ? "enabled" : "disabled")") }
                }
            }
            print("PASS: card menus offer Share with services and no plain-text paste for images")
            fflush(stdout); exit(0)
        }
    }
}
#endif
