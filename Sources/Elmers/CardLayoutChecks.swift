#if DEBUG
import AppKit
import ElmersCore
import SwiftUI

/// Renders cards offscreen and checks that every header keeps its full 50-pt height at the top of the card. A body
/// taller than the card overflows both ways, which lifts the header and its app icon off the card's top edge.
@MainActor
enum CardLayoutChecks {
    static func run() {
        let image = NSImage(size: NSSize(width: 600, height: 315), flipped: false) { rect in
            NSColor.systemGreen.setFill(); rect.fill(); return true
        }
        let png = image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:])
        let longTitle = "Is there a good alternative to CrossOver for running Windows apps on a Mac these days?"
        let longURL = "https://www.reddit.com/r/macapps/comments/1abcdef/is_there_a_good_alternative_to_crossover_for_running/"
        let cases: [(String, String, LinkPreview?)] = [
            ("link without preview", longURL, nil),
            ("link with image and title", longURL, LinkPreview(title: longTitle, image: png)),
            ("link with image and title, short address", "https://example.com/a", LinkPreview(title: longTitle, image: png)),
            ("link with title only", longURL, LinkPreview(title: longTitle + " " + longTitle, image: nil)),
            ("link with image only", longURL, LinkPreview(title: nil, image: png)),
        ]
        var failures = 0
        for (name, url, preview) in cases {
            var item = ClipboardItem(payload: .text(url), source: "Check")
            item.linkPreview = preview
            let height = headerHeight(of: item, capture: name)
            if abs(height - 50) <= 1 { print("PASS: \(name) keeps a 50-pt header") }
            else { print("FAIL: \(name) header is \(height) pt tall at the card's top"); failures += 1 }
        }
        fflush(stdout); exit(failures == 0 ? 0 : 1)
    }

    /// Rows from the card's top edge, down its left margin, that are still the header tint.
    private static func headerHeight(of item: ClipboardItem, capture name: String) -> Int {
        let renderer = ImageRenderer(content: CardView(item: item, selected: false, index: 0).environment(\.colorScheme, .light))
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { return -1 }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        if let dir = ProcessInfo.processInfo.environment["ELMERS_CAPTURE_DIR"] {
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("card \(name).png"))
        }
        // Below the rounded corner, inside the 13-pt leading padding.
        guard let tint = bitmap.colorAt(x: 6, y: 24) else { return -1 }
        var y = 24
        while y < bitmap.pixelsHigh, let color = bitmap.colorAt(x: 6, y: y), close(color, tint) { y += 1 }
        return y
    }

    private static func close(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let a = a.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.02 && abs(a.greenComponent - b.greenComponent) < 0.02
            && abs(a.blueComponent - b.blueComponent) < 0.02
    }
}
#endif
