import AppKit

/// Builds the menu bar image from the bundled toolbar artwork.
///
/// The artwork is a grayscale character. Drawn as a template image (alpha only, tinted by the bar) the white
/// cloud becomes a hole and only the small body survives, so the character is drawn in its own colors instead,
/// fitted to the menu bar height. `template(from:pointSize:)` remains for a tinted variant: darkness becomes
/// opacity there. Without the resource (checks run from `.build`), an SF Symbol is used.
enum StatusIcon {
    static let accessibilityDescription = "Elmers clipboard history"

    static func make() -> NSImage {
        if let url = Bundle.main.url(forResource: "Toolbar", withExtension: "png"), let source = NSImage(contentsOf: url),
           let image = render(source, pointSize: 20, template: false) { return image }
        return NSImage(systemSymbolName: "square.on.square", accessibilityDescription: accessibilityDescription)!
    }

    static func template(from source: NSImage, pointSize: CGFloat) -> NSImage? { render(source, pointSize: pointSize, template: true) }

    static func render(_ source: NSImage, pointSize: CGFloat, template: Bool) -> NSImage? {
        guard let content = contentBounds(of: source) else { return nil }
        let result = NSImage(size: NSSize(width: pointSize, height: pointSize))
        for scale in [1, 2, 3] as [CGFloat] {
            let pixels = Int(pointSize * scale)
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            // The bitmap context works in pixels. Fit the artwork's visible bounds into the square, keeping its aspect ratio.
            let side = CGFloat(pixels)
            let fit = min(side / content.width, side / content.height)
            let drawn = NSRect(x: (side - content.width * fit) / 2, y: (side - content.height * fit) / 2, width: content.width * fit, height: content.height * fit)
            source.draw(in: drawn, from: content, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            rep.size = NSSize(width: pointSize, height: pointSize)
            for y in 0..<pixels where template {
                for x in 0..<pixels {
                    guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
                    rep.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: color.alphaComponent * (1 - luminance)), atX: x, y: y)
                }
            }
            result.addRepresentation(rep)
        }
        result.isTemplate = template
        result.accessibilityDescription = accessibilityDescription
        return result
    }

    /// The rectangle, in the source's point coordinates, that holds visible pixels.
    private static func contentBounds(of source: NSImage) -> NSRect? {
        let samples = 128
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: samples, pixelsHigh: samples, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        source.draw(in: NSRect(x: 0, y: 0, width: samples, height: samples), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        var minX = samples, minY = samples, maxX = -1, maxY = -1
        for y in 0..<samples {
            for x in 0..<samples where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let unit = source.size.width / CGFloat(samples), unitY = source.size.height / CGFloat(samples)
        // Bitmap rows count from the top; image coordinates count from the bottom.
        return NSRect(x: CGFloat(minX) * unit, y: CGFloat(samples - 1 - maxY) * unitY, width: CGFloat(maxX - minX + 1) * unit, height: CGFloat(maxY - minY + 1) * unitY)
    }
}
