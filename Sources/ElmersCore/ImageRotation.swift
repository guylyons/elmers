import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Quarter-turn rotation for the editor's Rotate left and Rotate right (Paste 6.3.11's image editing).
public enum ImageRotation {
    /// Rotates encoded image data by `quarterTurns` × 90°, counterclockwise when positive, and returns PNG data.
    /// Pixels are moved exactly, without resampling.
    public static func rotate(_ data: Data, quarterTurns: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let turns = ((quarterTurns % 4) + 4) % 4
        let width = turns % 2 == 0 ? image.width : image.height, height = turns % 2 == 0 ? image.height : image.width
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space.model == .rgb ? space : CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        // Rotate about the new canvas's center, then draw the original centered on it.
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: CGFloat(turns) * .pi / 2)
        context.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2, width: CGFloat(image.width), height: CGFloat(image.height)))
        guard let rotated = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, rotated, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
