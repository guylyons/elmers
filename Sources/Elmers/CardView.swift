import AppKit
import SwiftUI
import ElmersCore

struct CardView: View {
    let item: ClipboardItem
    let selected: Bool
    let index: Int
    static let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .gray]
    private var accent: Color {
        if let id = item.sourceBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
           let color = CardImageCache.shared.color(for: id, url: url) { return color }
        switch item.kind {
        case .link: return Color(red: 0.19, green: 0.52, blue: 0.77)
        case .image: return Color(red: 0.57, green: 0.32, blue: 0.65)
        case .file: return Color(red: 0.77, green: 0.48, blue: 0.2)
        default: return Color(red: 0.08, green: 0.18, blue: 0.43)
        }
    }
    private var appIcon: NSImage? {
        guard let id = item.sourceBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return CardImageCache.shared.icon(for: id, url: url)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title ?? item.kind.rawValue).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(Self.relativeTime(item.copiedAt, now: context.date)).font(.system(size: 11)).opacity(0.85).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let icon = appIcon { Image(nsImage: icon).resizable().frame(width: 38, height: 38) }
                else { Image(systemName: symbol).font(.system(size: 25)).frame(width: 38, height: 38).opacity(0.85) }
            }
            .foregroundStyle(.white).padding(.leading, 13).padding(.trailing, 5).frame(height: 48).background(accent.gradient)
            VStack(spacing: 0) {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                HStack(spacing: 5) {
                    if !item.boardIDs.isEmpty { Image(systemName: "pin.fill").font(.system(size: 9)) }
                    Spacer(minLength: 0)
                    Text(footer).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 10).frame(height: 28)
            }.background(Color(nsColor: .textBackgroundColor))
        }
        .frame(width: 230, height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? Color.accentColor : .black.opacity(0.06), lineWidth: selected ? 3 : 1))
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.kind.rawValue), \(item.source), \(String(item.text.prefix(140)))")
        .accessibilityValue(selected ? "Selected" : "")
        .help("\(item.source) · \(item.kind.rawValue)\(index < 9 ? " · ⌘\(index + 1) to paste" : "")")
    }
    /// Paste's wording: "just now", "5 minutes ago", "3 hours ago", "yesterday", "2 weeks ago".
    static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full; formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }
    private var symbol: String {
        switch item.kind { case .text: return "text.alignleft"; case .link: return "link"; case .image: return "photo"; case .file: return "doc"; case .other: return "doc.on.clipboard" }
    }
    private var footer: String {
        switch item.kind {
        case .text: return "\(item.text.count) characters"
        case .link: return URL(string: item.text)?.host ?? "Link"
        case .file: return "\(item.payload.items.count) file\(item.payload.items.count == 1 ? "" : "s")"
        default: return ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file)
        }
    }
    @ViewBuilder private var preview: some View {
        if item.kind == .image, let image = imagePreview(item) {
            GeometryReader { geometry in
                Image(nsImage: image).resizable().scaledToFit().frame(width: geometry.size.width, height: geometry.size.height)
            }
        } else if item.kind == .file {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "doc.fill").font(.system(size: 40)).foregroundStyle(.orange)
                Text(item.text.components(separatedBy: "\n").compactMap { URL(string: $0)?.lastPathComponent }.joined(separator: "\n"))
                    .font(.system(size: 13, weight: .medium)).lineLimit(4)
            }.padding(13)
        } else {
            Text(item.text.isEmpty ? "\(item.payload.items.count) clipboard item(s)" : String(item.text.prefix(1600)))
                .font(.system(size: 13)).foregroundStyle(Color(nsColor: .textColor))
                .frame(maxWidth: .infinity, alignment: .topLeading).padding(13)
        }
    }
}

func imagePreview(_ item: ClipboardItem) -> NSImage? {
    for representations in item.payload.items {
        for type in ["public.png", "public.tiff"] {
            if let data = representations[type], let image = NSImage(data: data) { return image }
        }
    }
    return nil
}

struct ItemPreview: View {
    let item: ClipboardItem
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(item.title ?? item.kind.rawValue).font(.title2.bold()); Spacer(); Text(item.source).foregroundStyle(.secondary) }
            Divider()
            if let image = imagePreview(item) { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { ScrollView { Text(item.text.isEmpty ? "No text preview available." : item.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
            Text(item.copiedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth: 480, minHeight: 320)
    }
}

/// Source icons are independent of selection state. Avoid Launch Services/icon I/O on every redraw.
private final class CardImageCache {
    static let shared = CardImageCache()
    private let icons = NSCache<NSString, NSImage>()
    private var colors: [String: Color?] = [:]
    func icon(for id: String, url: URL) -> NSImage {
        if let icon = icons.object(forKey: id as NSString) { return icon }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons.setObject(icon, forKey: id as NSString)
        return icon
    }
    /// The card header takes the source app's dominant icon color, as Paste does (Brave is orange, Safari blue).
    func color(for id: String, url: URL) -> Color? {
        if let cached = colors[id] { return cached }
        let color = Self.dominantColor(of: icon(for: id, url: url)).map(Color.init)
        colors[id] = color
        return color
    }
    private static func dominantColor(of image: NSImage) -> NSColor? {
        let size = 24
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        // Weight opaque, saturated, mid-brightness pixels; bucket hues so a vivid accent beats a large neutral area.
        var buckets: [Int: (weight: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat)] = [:]
        for y in 0..<size { for x in 0..<size {
            guard let pixel = bitmap.colorAt(x: x, y: y), pixel.alphaComponent > 0.6 else { continue }
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
            pixel.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
            let weight = s * s * min(v, 1 - abs(v - 0.55)) + 0.001
            let key = Int(h * 12) * 4 + Int(s * 3.99)
            var bucket = buckets[key] ?? (0, 0, 0, 0)
            bucket.weight += weight; bucket.r += pixel.redComponent * weight; bucket.g += pixel.greenComponent * weight; bucket.b += pixel.blueComponent * weight
            buckets[key] = bucket
        } }
        guard let best = buckets.values.max(by: { $0.weight < $1.weight }), best.weight > 0.5 else { return nil }
        let color = NSColor(red: best.r / best.weight, green: best.g / best.weight, blue: best.b / best.weight, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        // Keep white text legible: clamp brightness and lift saturation slightly.
        return NSColor(hue: h, saturation: min(max(s, 0.55), 1), brightness: min(max(v, 0.45), 0.85), alpha: 1)
    }
}
