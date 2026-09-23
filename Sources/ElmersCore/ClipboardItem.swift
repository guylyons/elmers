import AppKit
import CryptoKit
import Foundation

public enum ContentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case text = "Text", link = "Link", image = "Image", screenshot = "Screenshot", file = "File", color = "Color", other = "Content"
    public var id: String { rawValue }
    public var isImage: Bool { self == .image || self == .screenshot }
}

/// A copied color. Paste 6.3.11 makes a Color card only from exactly six hex digits with an optional leading "#":
/// "#FF8800" and "FF8800" are colors; "#abc", "#FF880080", "0xFF8800", "rgb(…)", "red" and a hex value with
/// surrounding spaces stay Text.
public struct HexColor: Equatable, Sendable {
    public let red: Double, green: Double, blue: Double
    /// The value as the card shows it, always with a leading "#".
    public let display: String
    public init?(_ text: String) {
        let digits = text.hasPrefix("#") ? text.dropFirst() : Substring(text)
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else { return nil }
        red = Double(value >> 16 & 0xFF) / 255; green = Double(value >> 8 & 0xFF) / 255; blue = Double(value & 0xFF) / 255
        display = "#" + digits
    }
    /// Relative luminance (WCAG), used to pick dark or light text on the swatch.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.039_28 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

public struct ClipboardPayload: Codable, Equatable, Sendable {
    public var items: [[String: Data]]
    public init(items: [[String: Data]]) { self.items = items }
    public static func text(_ string: String) -> Self {
        .init(items: [[NSPasteboard.PasteboardType.string.rawValue: Data(string.utf8)]])
    }
    public var text: String {
        items.compactMap { representations -> String? in
            for type in [NSPasteboard.PasteboardType.string.rawValue, "public.url", "public.file-url"] {
                if let data = representations[type], let text = String(data: data, encoding: .utf8) { return text }
            }
            if let data = representations[NSPasteboard.PasteboardType.rtf.rawValue] {
                return NSAttributedString(rtf: data, documentAttributes: nil)?.string
            }
            return nil
        }.joined(separator: "\n")
    }
    public var kind: ContentKind { kind(for: text) }
    /// True when pasting the payload would produce nothing visible: every representation is empty, or is
    /// text that contains only whitespace. Any other non-empty representation counts as content.
    /// Paste records such copies; Elmers drops them by user decision (2026-09-22).
    public var isBlank: Bool {
        items.allSatisfy { representations in
            representations.allSatisfy { type, data in
                if data.isEmpty { return true }
                guard let text = Self.visibleText(type: type, data: data) else { return false }
                return text.allSatisfy(\.isWhitespace)
            }
        }
    }
    /// Decodes the human-visible characters of a text-like representation; nil for every other type.
    private static func visibleText(type: String, data: Data) -> String? {
        switch type {
        case "public.utf8-plain-text", "public.plain-text", "public.text", "NSStringPboardType", "com.apple.traditional-mac-plain-text":
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .macOSRoman)
        case "public.utf16-plain-text", "public.utf16-external-plain-text":
            return String(data: data, encoding: .utf16)
        case "public.rtf":
            return NSAttributedString(rtf: data, documentAttributes: nil)?.string
        case "public.html":
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            // Images, objects and embedded frames are content even when no text surrounds them.
            if html.range(of: "<(img|object|embed|iframe|video|audio|svg|canvas)\\b", options: [.regularExpression, .caseInsensitive]) != nil { return "x" }
            let stripped = html.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
            return stripped.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&#160;", with: " ")
        default:
            return nil
        }
    }
    func kind(for text: String) -> ContentKind {
        let types = Set(items.flatMap { $0.keys })
        if types.contains("public.file-url") { return .file }
        if types.contains("public.png") || types.contains("public.tiff") { return .image }
        if HexColor(text) != nil { return .color }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains(where: { $0.isWhitespace }), let url = URL(string: value),
           ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil { return .link }
        return text.isEmpty ? .other : .text
    }
    public var byteCount: Int { items.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } } }
    public var fingerprint: String {
        var hash = SHA256()
        // Length framing prevents ambiguity between adjacent representations/items.
        func append(_ data: Data) {
            var length = UInt64(data.count).bigEndian
            withUnsafeBytes(of: &length) { hash.update(data: Data($0)) }
            hash.update(data: data)
        }
        for item in items {
            append(Data("item".utf8))
            for key in item.keys.sorted() { append(Data(key.utf8)); append(item[key]!) }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct ClipboardItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var payload: ClipboardPayload {
        didSet { screenshot = nil; imageDigest = nil; recognizedText = nil; refreshMetadata(); fingerprint = payload.fingerprint }
    }
    public var source: String
    public var sourceBundleID: String?
    public var copiedAt: Date
    public var boardIDs: Set<UUID>
    public var title: String?
    public var fingerprint: String
    /// Optional remote preview for links, filled only when the user enables link previews.
    public var linkPreview: LinkPreview?
    /// Text recognized in an image item; empty string records that recognition ran and found nothing.
    public var recognizedText: String?
    public var screenshot: ScreenshotOrigin?
    /// Decoded image identity, computed off the main thread for cross-source screenshot duplicates.
    public var imageDigest: String?
    private var cachedText = ""
    private var cachedKind: ContentKind = .other
    private var cachedByteCount = 0
    public var text: String { cachedText }
    public var kind: ContentKind { cachedKind == .image && screenshot != nil ? .screenshot : cachedKind }
    public var byteCount: Int { cachedByteCount }
    public init(payload: ClipboardPayload, source: String, sourceBundleID: String? = nil, at: Date = Date()) {
        id = UUID(); self.payload = payload; self.source = source; self.sourceBundleID = sourceBundleID
        copiedAt = at; boardIDs = []; fingerprint = payload.fingerprint
        refreshMetadata()
    }
    init(id: UUID, payload: ClipboardPayload, source: String, sourceBundleID: String?, copiedAt: Date, boardIDs: Set<UUID>,
         title: String?, fingerprint: String, linkPreview: LinkPreview?, recognizedText: String?,
         screenshot: ScreenshotOrigin?, imageDigest: String?) {
        self.id = id; self.payload = payload; self.source = source; self.sourceBundleID = sourceBundleID
        self.copiedAt = copiedAt; self.boardIDs = boardIDs; self.title = title; self.fingerprint = fingerprint
        self.linkPreview = linkPreview; self.recognizedText = recognizedText; self.screenshot = screenshot; self.imageDigest = imageDigest
        refreshMetadata()
    }
    private mutating func refreshMetadata() {
        cachedText = payload.text
        cachedKind = payload.kind(for: cachedText)
        cachedByteCount = payload.byteCount
    }
    // Optional additions preserve backwards decoding of the v1 archive.
    private enum CodingKeys: String, CodingKey { case id, payload, source, sourceBundleID, copiedAt, boardIDs, title, fingerprint, linkPreview, recognizedText, screenshot, imageDigest }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        payload = try values.decode(ClipboardPayload.self, forKey: .payload)
        source = try values.decode(String.self, forKey: .source)
        sourceBundleID = try values.decodeIfPresent(String.self, forKey: .sourceBundleID)
        copiedAt = try values.decode(Date.self, forKey: .copiedAt)
        boardIDs = try values.decode(Set<UUID>.self, forKey: .boardIDs)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        fingerprint = try values.decode(String.self, forKey: .fingerprint)
        linkPreview = try values.decodeIfPresent(LinkPreview.self, forKey: .linkPreview)
        recognizedText = try values.decodeIfPresent(String.self, forKey: .recognizedText)
        screenshot = try values.decodeIfPresent(ScreenshotOrigin.self, forKey: .screenshot)
        imageDigest = try values.decodeIfPresent(String.self, forKey: .imageDigest)
        refreshMetadata()
    }
}

public struct ScreenshotOrigin: Codable, Equatable, Sendable {
    public var originalURL: URL
    public var fileIdentity: String
    public var bookmark: Data?
    public init(originalURL: URL, fileIdentity: String, bookmark: Data? = nil) {
        self.originalURL = originalURL; self.fileIdentity = fileIdentity; self.bookmark = bookmark
    }
}

/// Title and a small PNG image fetched for a link. `attempted` records a fetch that found nothing so it is not retried.
public struct LinkPreview: Codable, Equatable, Sendable {
    public var title: String?
    public var image: Data?
    public var attempted: Bool
    public init(title: String? = nil, image: Data? = nil, attempted: Bool = true) { self.title = title; self.image = image; self.attempted = attempted }
}

public struct Pinboard: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var colorIndex: Int
    public init(name: String, colorIndex: Int = 0) { id = UUID(); self.name = name; self.colorIndex = colorIndex }
    init(id: UUID, name: String, colorIndex: Int) { self.id = id; self.name = name; self.colorIndex = colorIndex }
    /// Red, orange, yellow, green, blue, purple, pink, gray.
    public static let colorCount = 8
}
