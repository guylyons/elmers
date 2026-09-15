import AppKit
import Foundation
import ElmersCore

final class PasteboardTests {
    func testMultiItemRoundTripPreservesEveryRepresentation() throws {
        let board = NSPasteboard(name: .init("ElmersTests-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        let payload = ClipboardPayload(items: [
            ["public.utf8-plain-text": Data("hello".utf8), "public.rtf": Data("{\\rtf1 hello}".utf8)],
            ["public.png": Data([137, 80, 78, 71, 0, 255])]
        ])
        XCTAssertTrue(PasteboardCodec.write(payload, to: board))
        let restored = try PasteboardCodec.read(from: board)
        XCTAssertEqual(restored?.items.count, 2)
        // macOS also synthesizes UTF-16 text. Every supplied representation must survive byte-for-byte.
        for (index, representations) in payload.items.enumerated() {
            for (type, data) in representations { XCTAssertEqual(restored?.items[index][type], data) }
        }
    }

    func testPlainTextDeliveryStripsRichRepresentations() throws {
        let board = NSPasteboard(name: .init("ElmersTests-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        let payload = ClipboardPayload(items: [["public.utf8-plain-text": Data("hello".utf8), "public.rtf": Data("rich".utf8)]])
        XCTAssertTrue(PasteboardCodec.write(payload, to: board, plainText: true))
        XCTAssertEqual(board.string(forType: .string), "hello")
        XCTAssertNil(board.data(forType: .rtf))
    }

    func testConfidentialMarkerPreventsCapture() throws {
        let board = NSPasteboard(name: .init("ElmersTests-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        _ = PasteboardCodec.write(ClipboardPayload(items: [["public.utf8-plain-text": Data("secret".utf8), "org.nspasteboard.ConcealedType": Data()]]), to: board)
        try XCTAssertNil(try PasteboardCodec.read(from: board))
        try XCTAssertNotNil(try PasteboardCodec.read(from: board, ignoreConfidential: false))
    }
}
