import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Call on a background queue. Limits compressed and decoded sizes before allocating pixels.
public struct ScreenshotImage {
    public static let maximumBytes = 32 * 1024 * 1024
    public let payload: ClipboardPayload
    public let digest: String
    public enum ReadError: LocalizedError {
        case invalid, unsupported, tooLarge
        public var errorDescription: String? {
            switch self {
            case .invalid: return String(localized: "A screenshot could not be read as a complete image. The original file is unchanged.")
            case .unsupported: return String(localized: "This screenshot format is not supported yet. Use PNG, JPEG, TIFF or HEIC in macOS.")
            case .tooLarge: return String(localized: "A screenshot exceeds Elmers’ 32 MB capture or decoded image size limit. The original file is unchanged.")
            }
        }
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw ReadError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              let type = CGImageSourceGetType(source) as String? else { throw ReadError.invalid }
        guard [UTType.png.identifier, UTType.jpeg.identifier, UTType.tiff.identifier, UTType.heic.identifier, UTType.heif.identifier].contains(type) else { throw ReadError.unsupported }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0,
              width <= 32768, height <= 32768, width * height <= 32 * 1024 * 1024 else { throw ReadError.tooLarge }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data else { throw ReadError.invalid }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var hash = SHA256()
        hash.update(data: Data("\(width)x\(height):sRGB-RGBA8:".utf8))
        hash.update(data: Data(bytesNoCopy: pixels, count: width * height * 4, deallocator: .none))
        var representations = [type: data]
        if type != UTType.png.identifier && type != UTType.tiff.identifier {
            let png = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else { throw ReadError.invalid }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw ReadError.invalid }
            guard png.length + data.count <= maximumBytes else { throw ReadError.tooLarge }
            representations[UTType.png.identifier] = png as Data
        }
        return Self(payload: ClipboardPayload(items: [representations]), digest: hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
    public static func digest(of payload: ClipboardPayload) -> String? {
        guard payload.items.count == 1, let representations = payload.items.first else { return nil }
        for type in ["public.png", "public.tiff", "public.jpeg", "public.heic", "public.heif"] {
            if let data = representations[type], let image = try? decode(data) { return image.digest }
        }
        return nil
    }
}
