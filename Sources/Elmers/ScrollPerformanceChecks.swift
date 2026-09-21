#if DEBUG
import AppKit
import ElmersCore

/// Measures main-thread cost of scrolling a history full of large images. Each step scrolls the real
/// NSScrollView, then forces layout, display and a Core Animation commit, so the timing covers the
/// SwiftUI updates and image decoding that happen on the main thread before a frame can be shown.
@MainActor
enum ScrollPerformanceChecks {
    static func run(model: AppModel, controller: PanelController) {
        Task { @MainActor in
            let count = Int(ProcessInfo.processInfo.environment["ELMERS_SCROLL_IMAGES"] ?? "") ?? 40
            let started = Date()
            for index in 0..<count { model.captureForChecks(.init(items: [["public.png": fixture(index)]]), source: "Preview") }
            print("INFO: generated \(count) 3840×2160 PNG fixtures in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
            controller.show()
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let root = controller.panel.contentView, let scroll = scrollView(in: root) else {
                print("FAIL: history scroll view not found"); fflush(stdout); exit(1)
            }
            if let thumbnail = model.visibleItems.first.flatMap(ThumbnailCache.shared.cached) {
                guard max(thumbnail.size.width, thumbnail.size.height) <= CGFloat(ThumbnailCache.maxPixelSize) else {
                    print("FAIL: card thumbnail is \(thumbnail.size), larger than \(ThumbnailCache.maxPixelSize) px"); fflush(stdout); exit(1)
                }
            } else { print("FAIL: first image thumbnail was not decoded"); fflush(stdout); exit(1) }
            KeyboardInteractionChecks.capturePanel(controller, name: "image-cards")
            var durations: [Double] = []
            let limit = (scroll.documentView?.bounds.width ?? 0) - scroll.contentSize.width
            var x: CGFloat = 0
            while x < limit {
                x = min(x + 48, limit)
                let begin = CFAbsoluteTimeGetCurrent()
                scroll.contentView.scroll(to: NSPoint(x: x, y: 0))
                scroll.reflectScrolledClipView(scroll.contentView)
                root.layoutSubtreeIfNeeded()
                controller.panel.displayIfNeeded()
                CATransaction.flush()
                durations.append((CFAbsoluteTimeGetCurrent() - begin) * 1000)
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            let sorted = durations.sorted()
            func percentile(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))] }
            let slow = durations.filter { $0 > 16.7 }.count
            print(String(format: "RESULT: %d scroll steps, median %.2f ms, p95 %.2f ms, max %.2f ms, %d over 16.7 ms",
                         durations.count, percentile(0.5), percentile(0.95), sorted.last ?? 0, slow))
            let budget = Double(ProcessInfo.processInfo.environment["ELMERS_SCROLL_P95_MS"] ?? "") ?? 16.7
            if durations.isEmpty || percentile(0.95) > budget { print("FAIL: p95 scroll step exceeds \(budget) ms"); fflush(stdout); exit(1) }
            print("PASS: image-heavy history scrolls within \(budget) ms at p95"); fflush(stdout); exit(0)
        }
    }

    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, scroll.documentView?.bounds.width ?? 0 > scroll.contentSize.width { return scroll }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }

    /// A screenshot-sized PNG with gradients, blocks and text, different for every index.
    private static func fixture(_ index: Int) -> Data {
        let width = 3840, height = 2160
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let hue = CGFloat(index % 12) / 12
        NSGradient(starting: NSColor(hue: hue, saturation: 0.5, brightness: 0.9, alpha: 1),
                   ending: NSColor(hue: 1 - hue, saturation: 0.7, brightness: 0.4, alpha: 1))!
            .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: CGFloat(index * 17))
        var seed = UInt64(index + 1) &* 0x9E3779B97F4A7C15
        func next() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 40) / CGFloat(1 << 24) }
        for _ in 0..<120 {
            NSColor(hue: next(), saturation: next(), brightness: next(), alpha: 0.8).setFill()
            NSRect(x: next() * CGFloat(width), y: next() * CGFloat(height), width: next() * 600, height: next() * 400).fill()
        }
        for line in 0..<30 {
            ("Scroll fixture \(index) — line \(line) of synthetic screenshot text" as NSString)
                .draw(at: NSPoint(x: 80, y: 60 + line * 68), withAttributes: [.font: NSFont.systemFont(ofSize: 44), .foregroundColor: NSColor.white])
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])!
    }
}
#endif
