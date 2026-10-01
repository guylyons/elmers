#if DEBUG
import AppKit
import ElmersCore
import SwiftUI

/// Renders cards offscreen. At full size every header keeps its full 50-pt band at the top of the card: a body taller
/// than the card overflows both ways, which lifts the header and its app icon off the card's top edge. In Compact Mode
/// (Paste 6.3.11, observed October 1) there is no band: the title sits on the card's own surface, and a color or a
/// link's picture runs up to the card's top edge under it, the picture darkened there by the title's shade.
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
        failures += fullSizeBandChecks() + compactChecks(longURL: longURL, longTitle: longTitle)
        fflush(stdout); exit(failures == 0 ? 0 : 1)
    }

    private static let lorem = "Elmers card layout check " + String(repeating: "lorem ipsum dolor sit amet consectetur adipiscing elit ", count: 8)
    private static let finderText = ClipboardItem(payload: .text(lorem), source: "Finder", sourceBundleID: "com.apple.finder")
    /// The band of a full-size card copied from Finder, read at (6, 24). Paste's is #62A9F5, and the palette gives that
    /// exactly, but a card with an app icon renders in HDR offscreen and reads #7BC4FF: only its blueness is checked.
    private static var finderBand: NSColor? { render(finderText, style: .standard, side: 232)?.colorAt(x: 6, y: 24)?.usingColorSpace(.sRGB) }
    /// A solid sRGB picture for link previews, so the pixels under the compact title's shade are predictable.
    private static let pictureColor = NSColor(srgbRed: 0.2, green: 0.6, blue: 0.9, alpha: 1)

    /// Text and color cards keep the band at full size too; a card copied from Finder has Finder's color in it.
    private static func fullSizeBandChecks() -> Int {
        var failures = 0
        let cases: [(String, ClipboardItem)] = [
            ("text", ClipboardItem(payload: .text(lorem), source: "Check")),
            ("text from Finder", finderText),
            ("color", ClipboardItem(payload: .text("#FF8800"), source: "Check")),
        ]
        for (name, item) in cases {
            let height = headerHeight(of: item, capture: name)
            if abs(height - 50) <= 1 { print("PASS: \(name) keeps a 50-pt header") }
            else { print("FAIL: \(name) header is \(height) pt tall at the card's top"); failures += 1 }
        }
        let band = finderBand
        if let band, band.blueComponent > 0.85, band.blueComponent - band.redComponent > 0.3 { print("PASS: a full-size card from Finder has Finder's blue band (\(hex(band)))") }
        else { print("FAIL: a full-size card from Finder has no blue band at its top (\(hex(band)))"); failures += 1 }
        return failures
    }

    /// Compact cards at the smallest panel height (152-pt cards). Pixels are read in the left margin under the corner,
    /// at (6, 24), clear of the title's glyphs (they start 12 pt in) and of the corner (16 pt), and for the picture at
    /// mid-width 4 pt below the top edge, above the title's glyphs and well clear of the 22-pt app icon at the right.
    private static func compactChecks(longURL: String, longTitle: String) -> Int {
        var failures = 0
        let metrics = PanelMetrics(height: PanelMetrics.minimumHeight), style = CardStyle(metrics), side = metrics.cardSide
        func check(_ passed: Bool, _ pass: String, _ fail: String) {
            if passed { print("PASS: \(pass)") } else { print("FAIL: \(fail)"); failures += 1 }
        }
        let picture = NSImage(size: NSSize(width: 600, height: 315), flipped: false) { rect in pictureColor.setFill(); rect.fill(); return true }
        let png = picture.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:])
        var pictureLink = ClipboardItem(payload: .text(longURL), source: "Check")
        pictureLink.linkPreview = LinkPreview(title: longTitle, image: png)
        let cases: [(String, ClipboardItem)] = [
            ("text", ClipboardItem(payload: .text(lorem), source: "Check")),
            ("text from Finder", finderText),
            ("link without preview", ClipboardItem(payload: .text(longURL), source: "Check")),
            ("link with picture", pictureLink),
            ("color", ClipboardItem(payload: .text("#FF8800"), source: "Check")),
        ]
        var renders: [String: NSBitmapImageRep] = [:]
        for (name, item) in cases {
            renders[name] = render(item, style: style, side: side, capture: "compact \(name)")
            // The dark renders are for looking at; Paste's dark Compact Mode has not been observed.
            _ = render(item, style: style, side: side, scheme: .dark, capture: "compact \(name) dark")
        }
        let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        // No band: the card's own surface shows where the full-size band would be (white for text, the top of the link
        // placeholder's fade from white to #F3F4F7 for a link).
        for name in ["text", "text from Finder", "link without preview"] {
            let pixel = renders[name]?.colorAt(x: 6, y: 24)
            check(pixel.map { close($0, white, tolerance: 0.03) } ?? false, "compact \(name) has no header band (\(hex(pixel)) at 6, 24)",
                  "compact \(name) shows \(hex(pixel)) at 6, 24 where its surface should be, not a band")
        }
        if let pixel = renders["text from Finder"]?.colorAt(x: 6, y: 24), let band = finderBand {
            check(!close(pixel, band, tolerance: 0.1), "compact text from Finder does not show Finder's band (\(hex(band)) at full size)",
                  "compact text from Finder still shows Finder's band (\(hex(pixel)))")
        }
        // A color fills the whole card, under the title too: the top-left matches the card's body. ImageRenderer draws
        // #FF8800 as #FF9A00 at full size as well, so the body is the reference, checked only to be that orange.
        let colorPixel = renders["color"]?.colorAt(x: 6, y: 24), body = renders["color"]?.colorAt(x: 6, y: 100)
        let orangeBody = body?.usingColorSpace(.sRGB).map { $0.redComponent > 0.9 && $0.greenComponent > 0.45 && $0.greenComponent < 0.7 && $0.blueComponent < 0.1 } ?? false
        check(orangeBody && colorPixel.flatMap { pixel in body.map { close(pixel, $0) } } ?? false,
              "compact color runs to the card's top (\(hex(colorPixel)) at 6, 24, body \(hex(body)))",
              "compact color shows \(hex(colorPixel)) at 6, 24, not its body's \(hex(body)) (#FF8800)")
        // A link's picture runs up under the title, darkened by its shade: black at 32 % along the top edge, so about
        // 0.70 of the picture 4 pt down. Accepted between 0.55 and 0.9 of the picture, with its hue kept.
        let x = Int(side / 2), y = 4
        let shaded = renders["link with picture"]?.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
        if let shaded, let base = pictureColor.usingColorSpace(.sRGB) {
            let ratio = shaded.blueComponent / base.blueComponent
            let hueKept = abs(shaded.greenComponent / max(shaded.blueComponent, 0.01) - base.greenComponent / base.blueComponent) < 0.1
                && abs(shaded.redComponent / max(shaded.blueComponent, 0.01) - base.redComponent / base.blueComponent) < 0.1
            check(ratio > 0.55 && ratio < 0.9 && hueKept,
                  String(format: "compact link picture runs to the top under the shade (%@ at %d, %d: %.2f of the picture)", hex(shaded), x, y, ratio),
                  String(format: "compact link shows %@ at %d, %d, not the picture (%@) darkened by the shade (%.2f of it)", hex(shaded), x, y, hex(base), ratio))
        } else { check(false, "", "compact link with picture did not render") }
        return failures
    }

    /// Rows from the card's top edge, down its left margin, that are still the header tint.
    private static func headerHeight(of item: ClipboardItem, capture name: String) -> Int {
        guard let bitmap = render(item, style: .standard, side: 232, capture: name) else { return -1 }
        // Below the rounded corner, inside the 13-pt leading padding.
        guard let tint = bitmap.colorAt(x: 6, y: 24) else { return -1 }
        var y = 24
        while y < bitmap.pixelsHigh, let color = bitmap.colorAt(x: 6, y: y), close(color, tint) { y += 1 }
        return y
    }

    /// The card at 1×, written to ELMERS_CAPTURE_DIR as "card <name>.png" when a name is given. With an app icon in it a
    /// card renders as an HDR image (BT.2100 PQ, even with `allowedDynamicRange(.standard)`), whose raw components read
    /// white as #A5A5A5, and #EAEAEA once tone-mapped into 8-bit sRGB. Drawn into extended-range sRGB, where reference
    /// white is 1.0, white reads #FFFFFF.
    private static func render(_ item: ClipboardItem, style: CardStyle, side: CGFloat, scheme: ColorScheme = .light, capture name: String? = nil) -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: CardView(item: item, selected: false, index: 0, style: style).frame(width: side, height: side).environment(\.colorScheme, scheme))
        renderer.scale = 1
        guard let rendered = renderer.cgImage, let space = CGColorSpace(name: CGColorSpace.extendedSRGB),
              let context = CGContext(data: nil, width: rendered.width, height: rendered.height, bitsPerComponent: 16, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
        else { return nil }
        context.draw(rendered, in: CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height))
        guard let cgImage = context.makeImage() else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        if let name, let dir = ProcessInfo.processInfo.environment["ELMERS_CAPTURE_DIR"] {
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("card \(name).png"))
        }
        return bitmap
    }

    private static func close(_ a: NSColor, _ b: NSColor, tolerance: CGFloat = 0.02) -> Bool {
        guard let a = a.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < tolerance && abs(a.greenComponent - b.greenComponent) < tolerance
            && abs(a.blueComponent - b.blueComponent) < tolerance
    }

    private static func hex(_ color: NSColor?) -> String {
        guard let c = color?.usingColorSpace(.sRGB) else { return "none" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255 + 0.5), Int(c.greenComponent * 255 + 0.5), Int(c.blueComponent * 255 + 0.5))
    }
}
#endif
