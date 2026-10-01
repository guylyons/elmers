#if DEBUG
import AppKit
import ElmersCore

/// How the history row answers scroll input, on a mixed history (text of every length, links, colors and images):
/// how far one mouse-wheel notch or one trackpad swipe moves it, and what each event costs on the main thread
/// (handling, layout, display and the Core Animation commit). Prints RESULT lines; `--check-scroll-input`.
@MainActor
enum ScrollInputChecks {
    static func run(model: AppModel, controller: PanelController) {
        Task { @MainActor in
            let words = "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore "
            for index in 0..<120 {
                switch index % 6 {
                case 0: model.newText("scroll text \(index) " + String(repeating: words, count: 1 + index % 9))
                case 1: model.newText("https://example.com/articles/\(index)/a-fairly-long-path-for-the-footer")
                case 2: model.newText(String(format: "#%06X", (index * 2_654_435) & 0xFFFFFF))
                case 3: model.captureForChecks(.init(items: [["public.png": image(index)]]), source: "Preview")
                default: model.newText("note \(index)\n" + String(repeating: words + "\n", count: index % 5))
                }
            }
            controller.show()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let root = controller.panel.contentView, let scroll = scrollView(in: root) else { print("FAIL: no history scroll view"); fflush(stdout); exit(1) }
            /// Sends `count` scroll events to the row and reports the distance moved and the cost of each event.
            @MainActor func measure(_ name: String, count: Int, units: CGScrollEventUnit, vertical: Int32, horizontal: Int32) async {
                scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
                try? await Task.sleep(nanoseconds: 300_000_000)
                var costs: [Double] = []
                for _ in 0..<count {
                    guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 2, wheel1: vertical, wheel2: horizontal, wheel3: 0),
                          let event = NSEvent(cgEvent: cg) else { continue }
                    let begin = CFAbsoluteTimeGetCurrent()
                    scroll.scrollWheel(with: controller.remappedScroll(event))
                    root.layoutSubtreeIfNeeded(); controller.panel.displayIfNeeded(); CATransaction.flush()
                    costs.append((CFAbsoluteTimeGetCurrent() - begin) * 1000)
                    try? await Task.sleep(nanoseconds: 16_000_000)
                }
                try? await Task.sleep(nanoseconds: 600_000_000)
                let moved = scroll.contentView.bounds.origin.x
                let sorted = costs.sorted()
                print(String(format: "RESULT %@: %d events moved %.0f pt (%.1f per event); cost median %.2f ms, p95 %.2f ms, max %.2f ms",
                             name, count, moved, moved / CGFloat(max(count, 1)), sorted[sorted.count / 2], sorted[Int(Double(sorted.count - 1) * 0.95)], sorted.last ?? 0))
                fflush(stdout)
            }
            if ProcessInfo.processInfo.environment["ELMERS_SCROLL_DEMO"] != nil {
                // For recording with `screencapture -v`: after 1.5 s, a sideways trackpad flick of 40 px every 16 ms for
                // 2 s, through the same rewrite as real input, then back the other way.
                print("PANEL \(controller.panel.frame)"); fflush(stdout)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                for direction: Int32 in [-40, 40] {
                    for _ in 0..<120 {
                        if let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: direction, wheel3: 0), let event = NSEvent(cgEvent: cg) {
                            scroll.scrollWheel(with: controller.remappedScroll(event))
                        }
                        try? await Task.sleep(nanoseconds: 16_000_000)
                    }
                }
                exit(0)
            }
            await measure("mouse wheel, 1 line down", count: 20, units: .line, vertical: -1, horizontal: 0)
            await measure("trackpad, 10 px left", count: 60, units: .pixel, vertical: 0, horizontal: -10)
            await measure("trackpad, 10 px down", count: 60, units: .pixel, vertical: -10, horizontal: 0)
            await measure("fast trackpad flick, 40 px left", count: 60, units: .pixel, vertical: 0, horizontal: -40)
            exit(0)
        }
    }
    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, scroll.documentView?.bounds.width ?? 0 > scroll.contentSize.width { return scroll }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }
    private static func image(_ index: Int) -> Data {
        let image = NSImage(size: NSSize(width: 800, height: 600), flipped: false) { rect in
            NSColor(hue: CGFloat(index % 12) / 12, saturation: 0.6, brightness: 0.8, alpha: 1).setFill(); rect.fill(); return true
        }
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }
}
#endif
