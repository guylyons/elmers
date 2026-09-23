import AppKit
import SwiftUI
import ElmersCore

struct CardView: View {
    let item: ClipboardItem
    let selected: Bool
    /// Paste turns the selected card's ring gray while the pointer rests on a different card.
    var ringDimmed = false
    let index: Int
    static let width: CGFloat = 232
    static let height: CGFloat = 232
    static let cornerRadius: CGFloat = 16
    /// Pinboard colors in Display P3. Paste's red renders #FE3A3C, which no sRGB system red reaches; the other seven
    /// take Apple's light-mode system values as P3 components in the same way and are not yet compared with Paste.
    static let colors: [Color] = [(1, 0.23, 0.24), (1, 0.584, 0), (1, 0.8, 0), (0.204, 0.78, 0.349), (0, 0.478, 1),
                                  (0.686, 0.322, 0.871), (1, 0.176, 0.333), (0.557, 0.557, 0.576)]
        .map { Color(.displayP3, red: $0.0, green: $0.1, blue: $0.2) }
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
                VStack(alignment: .leading, spacing: -1) {
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
            if let color = HexColor(item.text), item.kind == .color {
                // Paste 6.3.11 fills the whole body with the color and centers the value in 18-pt monospaced type,
                // with no count footer.
                Text(color.display).font(.system(size: 18, design: .monospaced))
                    .foregroundStyle(color.luminance > 0.18 ? Color.black.opacity(0.85) : Color.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.sRGB, red: color.red, green: color.green, blue: color.blue))
            } else {
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
                }.background(item.kind == .link && item.linkPreview == nil ? Self.linkBodyColor : Self.bodyColor)
            }
        }
        .frame(width: Self.width, height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        // Paste 6.3.11 draws the selection as a 4-pt ring hugging the outside of the card, with no gap and no
        // border on unselected cards.
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: Self.cornerRadius + 4, style: .continuous)
                    .strokeBorder(ringDimmed ? Color(nsColor: .systemGray) : Self.ringColor, lineWidth: 4).padding(-4)
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
    /// Paste's ring is a Display P3 blue (renders #016EFE), more saturated than the sRGB system accent.
    static let ringColor = Color(.displayP3, red: 0.004, green: 0.431, blue: 0.996)
    /// Card bodies are white in light mode and #141414 in dark mode (measured on Paste 6.3.11).
    static let bodyColor = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 0.078, alpha: 1) : .white
    })
    /// Paste's link placeholder body is a cool light gray (#F3F4F7) rather than white.
    static let linkBodyColor = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 0.14, alpha: 1) : NSColor(red: 0.953, green: 0.957, blue: 0.969, alpha: 1)
    })
    private var symbol: String { item.kind.symbolName }
    private var footer: String {
        switch item.kind {
        case .text: return "\(item.text.count) character\(item.text.count == 1 ? "" : "s")" // Paste: "1 character", "41 characters"
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
        if item.kind.isImage, hasImageData(item) {
            CardThumbnail(item: item)
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
            if item.text.isEmpty { PreviewUnavailable(compact: true) }
            else {
                Text(String(item.text.prefix(1600)))
                    .font(.system(size: 13)).foregroundStyle(Color(nsColor: .textColor))
                    .frame(maxWidth: .infinity, alignment: .topLeading).padding(13)
            }
        }
    }
}

/// Whether the payload has an image, known without reading bytes that may still be in the database.
func hasImageData(_ item: ClipboardItem) -> Bool { !item.payload.types.isDisjoint(with: ["public.png", "public.tiff"]) }

/// The first image representation in the payload. For a stored item this may read the database, so keep it off
/// the main thread where possible.
func imageData(of item: ClipboardItem) -> Data? {
    for representations in item.payload.items {
        for type in ["public.png", "public.tiff"] {
            if let data = representations[type] { return data }
        }
    }
    return nil
}

/// Full-resolution image for previews, sharing and drags; cards use `CardThumbnail` instead.
func imagePreview(_ item: ClipboardItem) -> NSImage? { imageData(of: item).flatMap(NSImage.init(data:)) }

/// A card's image, drawn from a downsampled thumbnail that is decoded off the main thread.
private struct CardThumbnail: View {
    let item: ClipboardItem
    @State private var loaded: NSImage?
    var body: some View {
        GeometryReader { geometry in
            if let image = loaded ?? ThumbnailCache.shared.cached(item) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .task(id: item.fingerprint) {
            guard ThumbnailCache.shared.cached(item) == nil else { return }
            loaded = await ThumbnailCache.shared.thumbnail(for: item)
        }
    }
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
            else if item.text.isEmpty { PreviewUnavailable(compact: false) }
            else { ScrollView { Text(item.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
            Text(item.copiedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth: 480, minHeight: 320)
    }
}

/// Paste 6.3.11's wording for content it keeps but cannot draw: "Preview unavailable" / "Preview can't be shown, but the
/// content is saved, and you're able to paste it". Paste's layout for this state has not been seen.
struct PreviewUnavailable: View {
    let compact: Bool
    var body: some View {
        VStack(spacing: compact ? 4 : 8) {
            Text("Preview unavailable").font(.system(size: compact ? 13 : 17, weight: .semibold))
            Text("Preview can’t be shown, but the\u{00A0}content is saved, and\u{00A0}you’re able to\u{00A0}paste it")
                .font(.system(size: compact ? 12 : 13)).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center).padding(compact ? 13 : 24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Source icons are independent of selection state. Avoid Launch Services/icon I/O on every redraw.
final class CardImageCache {
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
        switch self { case .text: return "text.alignleft"; case .link: return "link"; case .image: return "photo"; case .screenshot: return "viewfinder"; case .file: return "doc"; case .color: return "paintpalette"; case .other: return "doc.on.clipboard" }
    }
    /// Lowercase plural for the search placeholder: "Search images".
    var searchNoun: String {
        switch self { case .text: return "text"; case .other: return "content"; default: return rawValue.lowercased() + "s" }
    }
}
