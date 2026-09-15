import AppKit
import SwiftUI

/// Observe mouse-down without participating in SwiftUI's single/double-tap arbitration.
/// The event continues to the hosting view for double-click, context-menu, and drag handling.
struct CardMouseObserver: NSViewRepresentable {
    var onMouseDown: (NSEvent) -> Void
    func makeNSView(context: Context) -> ObserverView { ObserverView(onMouseDown: onMouseDown) }
    func updateNSView(_ view: ObserverView, context: Context) { view.onMouseDown = onMouseDown }

    final class ObserverView: NSView {
        var onMouseDown: (NSEvent) -> Void
        private var monitor: Any?
        private static weak var handledEvent: NSEvent?
        init(onMouseDown: @escaping (NSEvent) -> Void) {
            self.onMouseDown = onMouseDown
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, Self.handledEvent !== event, event.window === self.window, !self.isHiddenOrHasHiddenAncestor else { return event }
                let hit = self.convert(self.bounds, to: nil).contains(event.locationInWindow)
                guard hit else { return event }
                // A selection redraw can update other cards' geometry during this monitor chain.
                // Each physical event belongs to exactly one card, regardless of that re-layout.
                Self.handledEvent = event
                self.onMouseDown(event)
                return event
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
