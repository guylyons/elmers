import AppKit
import ImageIO
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
    private var failed: Set<String> = []
    private var waiting: [String: [@MainActor (NSImage?) -> Void]] = [:]
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Elmers thumbnails"
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        return queue
    }()

    private init() { cache.totalCostLimit = 128 << 20 }

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
