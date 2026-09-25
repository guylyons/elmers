import CoreGraphics
import Foundation
import ImageIO
import ElmersCore

final class ColorTests {
    func testOnlySixHexDigitsBecomeColors() {
        // Classified by Paste 6.3.11 on September 23, 2026.
        for text in ["#FF8800", "FF8800", "#123456"] {
            XCTAssertEqual(ClipboardPayload.text(text).kind, .color)
        }
        // Lowercase digits were not tried in Paste; Elmers accepts them.
        XCTAssertEqual(ClipboardPayload.text("#ff8800").kind, .color)
        for text in ["#abc", "#FF880080", "rgb(0, 128, 255)", "rgba(0,128,255,0.5)", "hsl(120, 50%, 50%)", "red", "0xFF8800",
                     " #ff8800 ", "#ff8800\n", "color: #FF8800", "#GG0000", "##FF8800"] {
            XCTAssertEqual(ClipboardPayload.text(text).kind, .text)
        }
    }

    func testColorComponentsDisplayAndContrast() {
        let orange = HexColor("FF8800")!
        XCTAssertEqual(orange.display, "#FF8800")
        XCTAssertEqual([orange.red, orange.green, orange.blue], [1, 136.0 / 255, 0])
        XCTAssertTrue(orange.luminance > 0.3)
        XCTAssertTrue(HexColor("#123456")!.luminance < 0.05)
        XCTAssertNil(HexColor("#12345"))
    }

    func testColorIsAFilter() {
        var history = History()
        let color = history.capture(.text("#00AAFF"), source: "Fixture")
        _ = history.capture(.text("plain"), source: "Fixture")
        XCTAssertEqual(history.items.filter { SearchFilters([.kind(.color)]).matches($0) }.map(\.id), [color.id])
    }
}

final class ImageRotationTests {
    /// A 2×1 image: red on the left, blue on the right.
    private func fixture() -> Data {
        let context = CGContext(data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1); context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
        let data = NSMutableData(); let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil); CGImageDestinationFinalize(destination)
        return data as Data
    }
    /// Top-to-bottom, left-to-right pixel colors as "r", "b".
    private func pixels(_ data: Data) -> (Int, Int, [String]) {
        let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil)!
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &buffer, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let names = stride(from: 0, to: buffer.count, by: 4).map { buffer[$0] > 200 ? "r" : buffer[$0 + 2] > 200 ? "b" : "?" }
        return (image.width, image.height, names)
    }
    func testQuarterTurnsMovePixelsExactly() {
        let source = fixture()
        let (w, h, original) = pixels(source); XCTAssertEqual([w, h], [2, 1]); XCTAssertEqual(original, ["r", "b"])
        // Rotating left (counterclockwise) puts the right-hand blue pixel on top.
        let left = pixels(ImageRotation.rotate(source, quarterTurns: 1)!); XCTAssertEqual([left.0, left.1], [1, 2]); XCTAssertEqual(left.2, ["b", "r"])
        let right = pixels(ImageRotation.rotate(source, quarterTurns: -1)!); XCTAssertEqual(right.2, ["r", "b"]); XCTAssertEqual([right.0, right.1], [1, 2])
        XCTAssertEqual(pixels(ImageRotation.rotate(source, quarterTurns: 2)!).2, ["b", "r"])
        XCTAssertEqual(pixels(ImageRotation.rotate(source, quarterTurns: 4)!).2, ["r", "b"])
        XCTAssertNil(ImageRotation.rotate(Data("not an image".utf8), quarterTurns: 1))
    }
}
