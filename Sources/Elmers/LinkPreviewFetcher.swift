import AppKit
import LinkPresentation
import ElmersCore

/// Downloads a link's title and a representative image with LinkPresentation.
/// Images are downscaled to a small PNG so the archive stays compact. Fetches neither send nor keep cookies, and
/// whatever web state LinkPresentation still leaves in Elmers' own storage is cleared afterwards, so previewing a
/// copied link cannot sign the user in, track them across fetches, or leave a record of the sites they copied.
@MainActor
final class LinkPreviewFetcher {
    private var providers: [LPMetadataProvider] = []

    func fetch(_ text: String, completion: @escaping @MainActor (LinkPreview) -> Void) {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), ["http", "https"].contains(url.scheme ?? "") else {
            completion(LinkPreview()); return
        }
        let provider = LPMetadataProvider()
        provider.timeout = 15
        providers.append(provider)
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        provider.startFetchingMetadata(for: request) { [weak self] metadata, _ in
            Task { @MainActor in
                self?.providers.removeAll { $0 === provider }
                Self.purgeWebState()
                guard let metadata else { completion(LinkPreview()); return }
                let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                Self.loadImage(metadata.imageProvider ?? metadata.iconProvider) { image in
                    completion(LinkPreview(title: title?.isEmpty == true ? nil : title, image: image))
                }
            }
        }
    }

    /// Elmers never needs cookies or cached web responses, so any in its storage came from link previews.
    static func purgeWebState() {
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
        URLCache.shared.removeAllCachedResponses()
    }

    private static func loadImage(_ provider: NSItemProvider?, completion: @escaping @MainActor (Data?) -> Void) {
        guard let provider, provider.canLoadObject(ofClass: NSImage.self) else { completion(nil); return }
        provider.loadObject(ofClass: NSImage.self) { object, _ in
            let data = (object as? NSImage).flatMap { downscaledPNG($0, maxWidth: 480) }
            Task { @MainActor in completion(data) }
        }
    }

    nonisolated static func downscaledPNG(_ image: NSImage, maxWidth: CGFloat) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, maxWidth / image.size.width)
        let size = NSSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
