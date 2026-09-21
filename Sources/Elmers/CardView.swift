import AppKit
import SwiftUI
import ElmersCore

struct CardView: View {
    let item: ClipboardItem
    let selected: Bool
    /// Paste turns the selected card's ring gray while the pointer rests on a different card.
    var ringDimmed = false
    let index: Int
    static let width: CGFloat = 235
    static let height: CGFloat = 236
    static let cornerRadius: CGFloat = 15
    static let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .gray]
    private var accent: Color {
        if let id = item.sourceBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
           let color = CardImageCache.shared.color(for: id, url: url) { return color }
        switch item.kind {
        case .link: return Color(red: 0.19, green: 0.52, blue: 0.77)
        case .image, .screenshot: return Color(red: 0.57, green: 0.32, blue: 0.65)
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
                    Text(item.title ?? item.kind.rawValue).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        Text(Self.relativeTime(item.copiedAt, now: context.date)).font(.system(size: 12)).opacity(0.9).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let icon = appIcon { Image(nsImage: icon).resizable().frame(width: 46, height: 46) }
                else { Image(systemName: symbol).font(.system(size: 28)).frame(width: 46, height: 46).opacity(0.85) }
            }
            .foregroundStyle(.white).padding(.leading, 13).padding(.trailing, 3).frame(height: 50)
            .background(accent) // Paste's header is a flat tint (#1C3EC3 top to bottom), not a gradient.
            VStack(spacing: 0) {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                // Paste's footer sits on the bottom edge: counts are centered on one line, link addresses are
                // left-aligned and may wrap onto a second line that grows upward.
                HStack(alignment: .bottom, spacing: 5) {
                    if !item.boardIDs.isEmpty { Image(systemName: "pin.fill").font(.system(size: 9)).padding(.bottom, 3) }
                    if item.kind == .link {
                        Text(footer).lineLimit(2).truncationMode(.tail).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(footer).lineLimit(1).frame(maxWidth: .infinity)
                    }
                }
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 13).padding(.bottom, 10).padding(.top, 4)
            }.background(item.kind == .link && item.linkPreview == nil ? Self.linkBodyColor : Color(nsColor: .textBackgroundColor))
        }
        .frame(width: Self.width, height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        // Paste draws the selection as a 3-pt ring just outside the card, with no border on unselected cards.
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: Self.cornerRadius + 4, style: .continuous)
                    .strokeBorder(ringDimmed ? Color(nsColor: .systemGray) : Color.accentColor, lineWidth: 3).padding(-4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.kind.rawValue), \(item.source), \(String(item.text.prefix(140)))")
        .accessibilityValue(selected ? "Selected" : "")
        .help("\(item.source) · \(item.kind.rawValue)\(index < 9 ? " · ⌘\(index + 1) to paste" : "")")
    }
    /// Paste's wording: "now", "30 seconds ago", "5 minutes ago", "3 hours ago", "yesterday", "2 weeks ago".
    static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 30 { return "now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full; formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }
    /// Paste's link placeholder body is a cool light gray (#F3F4F7) rather than white.
    static let linkBodyColor = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 0.14, alpha: 1) : NSColor(red: 0.953, green: 0.957, blue: 0.969, alpha: 1)
    })
    private var symbol: String { item.kind.symbolName }
    private var footer: String {
        switch item.kind {
        case .text: return "\(item.text.count) characters"
        case .link:
            // Paste shows the address without its scheme: "pasteapp.io/help".
            guard let url = URL(string: item.text.components(separatedBy: "\n").first ?? item.text), let host = url.host else { return "Link" }
            let path = url.path == "/" ? "" : url.path
            return host + path + (url.query.map { "?" + $0 } ?? "")
        case .file: return "\(item.payload.items.count) file\(item.payload.items.count == 1 ? "" : "s")"
        default: return ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file)
        }
    }
    @ViewBuilder private var preview: some View {
        if item.kind.isImage, let image = imagePreview(item) {
            GeometryReader { geometry in
                Image(nsImage: image).resizable().scaledToFit().frame(width: geometry.size.width, height: geometry.size.height)
            }
        } else if item.kind == .link, let preview = item.linkPreview, preview.title != nil || preview.image != nil {
            VStack(alignment: .leading, spacing: 0) {
                if let data = preview.image, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: preview.title == nil ? 154 : 108).clipped()
                }
                if let title = preview.title {
                    Text(title).font(.system(size: 13, weight: .medium)).lineLimit(preview.image == nil ? 5 : 2).padding(13)
                }
            }
        } else if item.kind == .link {
            Image(systemName: "safari").font(.system(size: 34, weight: .thin)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if let image = imagePreview(item) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                if let text = item.recognizedText, !text.isEmpty {
                    Text("Recognized text").font(.caption.bold()).foregroundStyle(.secondary)
                    ScrollView { Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 120)
                }
            }
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
        // Paste lifts the hue into a vivid header tint (a navy terminal icon becomes bright blue); keep white text legible.
        return NSColor(hue: h, saturation: min(max(s, 0.6), 0.9), brightness: min(max(v, 0.72), 0.9), alpha: 1)
    }
}

extension ContentKind {
    /// SF Symbol used for this type on cards and in the search field's type filter.
    var symbolName: String {
        switch self { case .text: return "text.alignleft"; case .link: return "link"; case .image: return "photo"; case .screenshot: return "viewfinder"; case .file: return "doc"; case .other: return "doc.on.clipboard" }
    }
    /// Lowercase plural for the search placeholder: "Search images".
    var searchNoun: String {
        switch self { case .text: return "text"; case .other: return "content"; default: return rawValue.lowercased() + "s" }
    }
}
