import AppKit
import SwiftUI

/// Observe mouse-down without participating in SwiftUI's single/double-tap arbitration.
/// The event continues to the hosting view for double-click and context-menu handling. A left-button
/// drag that leaves the drag threshold starts an AppKit drag session with the items `dragItems` returns.
struct CardMouseObserver: NSViewRepresentable {
    var onMouseDown: (NSEvent) -> Void
    var dragItems: ((NSRect, NSImage?) -> [NSDraggingItem])? = nil
    func makeNSView(context: Context) -> ObserverView { ObserverView(onMouseDown: onMouseDown, dragItems: dragItems) }
    func updateNSView(_ view: ObserverView, context: Context) { view.onMouseDown = onMouseDown; view.dragItems = dragItems }

    final class ObserverView: NSView, NSDraggingSource {
        var onMouseDown: (NSEvent) -> Void
        var dragItems: ((NSRect, NSImage?) -> [NSDraggingItem])?
        private var monitor: Any?
        private var dragMonitor: Any?
        private var pressedAt: NSPoint?
        private static weak var handledEvent: NSEvent?
        /// AppKit's own drag threshold for a mouse-down that may become a drag.
        private static let dragThreshold: CGFloat = 4
        init(onMouseDown: @escaping (NSEvent) -> Void, dragItems: ((NSRect, NSImage?) -> [NSDraggingItem])?) {
            self.onMouseDown = onMouseDown
            self.dragItems = dragItems
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            if let dragMonitor { NSEvent.removeMonitor(dragMonitor); self.dragMonitor = nil }
            pressedAt = nil
            guard window != nil else { return }
            dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
                guard let self, let start = self.pressedAt, event.window === self.window else { return event }
                if event.type == .leftMouseUp { self.pressedAt = nil; return event }
                guard hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) >= Self.dragThreshold else { return event }
                self.pressedAt = nil
                return self.beginDrag(with: event) ? nil : event
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, Self.handledEvent !== event, event.window === self.window, !self.isHiddenOrHasHiddenAncestor else { return event }
                let hit = self.convert(self.bounds, to: nil).contains(event.locationInWindow)
                guard hit else { return event }
                // A selection redraw can update other cards' geometry during this monitor chain.
                // Each physical event belongs to exactly one card, regardless of that re-layout.
                Self.handledEvent = event
                if event.type == .leftMouseDown, event.clickCount == 1 { self.pressedAt = event.locationInWindow }
                self.onMouseDown(event)
                return event
            }
        }
        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        }

        /// Starts the drag with a snapshot of the card as its image. Returns false when there is nothing to drag.
        private func beginDrag(with event: NSEvent) -> Bool {
            guard let dragItems, let content = window?.contentView else { return false }
            let items = dragItems(bounds, snapshot(of: content))
            guard !items.isEmpty else { return false }
            beginDraggingSession(with: items, event: event, source: self)
            return true
        }
        private func snapshot(of content: NSView) -> NSImage? {
            let rect = content.convert(convert(bounds, to: nil), from: nil)
            guard let rep = content.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
            content.cacheDisplay(in: rect, to: rep)
            let image = NSImage(size: bounds.size)
            image.addRepresentation(rep)
            return image
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? [.copy, .generic] : .copy
        }
    }
}
