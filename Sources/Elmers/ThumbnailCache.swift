import AppKit
import ImageIO
import QuickLookThumbnailing
import ElmersCore

/// Card-sized image thumbnails. Full screenshots are several megabytes of PNG; decoding and drawing them
/// on the main thread every time a card scrolled into view made scrolling stutter. Thumbnails are
/// downsampled off the main thread with ImageIO and cached by payload fingerprint.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    /// Longest side in pixels: a 235-pt card at 2× plus headroom.
    static let maxPixelSize = 512
    private let cache = NSCache<NSString, NSImage>()
    private let files = NSCache<NSString, FileThumbnail>()
    private var failed: Set<String> = []
    private var waiting: [String: [@MainActor (NSImage?) -> Void]] = [:]
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Elmers thumbnails"
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        return queue
    }()

    private init() { cache.totalCostLimit = 128 << 20; files.totalCostLimit = 32 << 20 }

    func cached(_ item: ClipboardItem) -> NSImage? { cache.object(forKey: item.fingerprint as NSString) }

    func thumbnail(for item: ClipboardItem) async -> NSImage? {
        await withCheckedContinuation { continuation in load(item) { continuation.resume(returning: $0) } }
    }

    /// Decodes thumbnails for items that are likely to be shown soon, most recent first.
    func prewarm(_ items: some Sequence<ClipboardItem>) {
        for item in items where item.kind.isImage { load(item) { _ in } }
    }

    private func load(_ item: ClipboardItem, completion: @escaping @MainActor (NSImage?) -> Void) {
        let key = item.fingerprint
        if let image = cache.object(forKey: key as NSString) { completion(image); return }
        guard !failed.contains(key), hasImageData(item) else { completion(nil); return }
        if waiting[key] != nil { waiting[key]!.append(completion); return }
        waiting[key] = [completion]
        let maxPixelSize = Self.maxPixelSize
        queue.addOperation {
            // Large images stay in the database until needed, so even reading the bytes happens off the main thread.
            let thumbnail = imageData(of: item).flatMap { Self.decode($0, maxPixelSize: maxPixelSize) }
            Task { @MainActor in self.finish(key, thumbnail) }
        }
    }

    private func finish(_ key: String, _ thumbnail: CGImage?) {
        let image = thumbnail.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        if let image, let thumbnail { cache.setObject(image, forKey: key as NSString, cost: thumbnail.bytesPerRow * thumbnail.height) }
        else { failed.insert(key) }
        for completion in waiting.removeValue(forKey: key) ?? [] { completion(image) }
    }

    /// Side of the square a file card's thumbnail is requested at. Icon mode pads the page inside it, so on Paste 6.3.11
    /// a portrait text page measures 82 × 109 pt and a 3:2 picture 109 × 72.5 pt.
    static let fileThumbnailSide: CGFloat = 122.5

    /// The last thumbnail made for this file, possibly from an older version of it, to draw without a blank frame.
    func cached(fileAt url: URL) -> NSImage? { files.object(forKey: url.path as NSString)?.image }

    /// Paste 6.3.11 shows a copied file as its Quick Look thumbnail in icon mode (`QLThumbnailImageCreate` with
    /// `kQLThumbnailOptionIconModeKey`), the page or picture Finder shows, and falls back to the file's icon.
    /// Thumbnails are remade when the file's modification date changes.
    func thumbnail(forFileAt url: URL) async -> NSImage {
        let modified = await Task.detached(priority: .userInitiated) {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }.value
        if let entry = files.object(forKey: url.path as NSString), entry.modified == modified { return entry.image }
        let side = Self.fileThumbnailSide
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: 2, representationTypes: .all)
        request.iconMode = true
        let image = (try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request))?.nsImage
            ?? NSWorkspace.shared.icon(forFile: url.path)
        files.setObject(FileThumbnail(image: image, modified: modified), forKey: url.path as NSString, cost: Int(side * side * 16))
        return image
    }

    nonisolated static func decode(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary)
    }
}

private final class FileThumbnail {
    let image: NSImage
    let modified: Date?
    init(image: NSImage, modified: Date?) { self.image = image; self.modified = modified }
}
