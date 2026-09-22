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

    /// User decision (2026-09-22): copying nothing must not create a card. Paste itself records empty
    /// and whitespace-only text; Elmers deliberately drops payloads with no visible content.
    func testBlankTextIsNeverCaptured() throws {
        XCTAssertTrue(ClipboardPayload.text("").isBlank)
        XCTAssertTrue(ClipboardPayload.text("  \n\t\u{00A0}").isBlank)
        XCTAssertTrue(ClipboardPayload(items: [["public.utf8-plain-text": Data(), "com.example.private": Data()]]).isBlank)
        XCTAssertTrue(ClipboardPayload(items: [["public.rtf": Data("{\\rtf1\\ansi  \\par }".utf8), "public.utf8-plain-text": Data(" \n".utf8)]]).isBlank)
        XCTAssertTrue(ClipboardPayload(items: [["public.html": Data("<meta charset=\"utf-8\"><p>&nbsp; </p>".utf8), "public.utf8-plain-text": Data(" ".utf8)]]).isBlank)
        XCTAssertTrue(ClipboardPayload(items: [["public.utf16-external-plain-text": " ".data(using: .utf16)!]]).isBlank)
        XCTAssertTrue(ClipboardPayload(items: [[:], ["public.utf8-plain-text": Data()]]).isBlank)
        XCTAssertTrue(!ClipboardPayload.text("a").isBlank)
        XCTAssertTrue(!ClipboardPayload.text(" x ").isBlank)
        XCTAssertTrue(!ClipboardPayload(items: [["public.png": Data([137, 80, 78, 71, 0, 255])]]).isBlank)
        XCTAssertTrue(!ClipboardPayload(items: [["public.utf8-plain-text": Data(), "com.example.private": Data([1])]]).isBlank)
        XCTAssertTrue(!ClipboardPayload(items: [["public.html": Data("<p><img src=\"x.png\"></p>".utf8), "public.utf8-plain-text": Data()]]).isBlank)
        XCTAssertTrue(!ClipboardPayload(items: [["public.utf8-plain-text": Data()], ["public.utf8-plain-text": Data("b".utf8)]]).isBlank)

        let board = NSPasteboard(name: .init("ElmersTests-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        board.clearContents(); board.setString("", forType: .string)
        try XCTAssertNil(try PasteboardCodec.read(from: board))
        board.clearContents(); board.setString("\n\t ", forType: .string)
        try XCTAssertNil(try PasteboardCodec.read(from: board))
        board.clearContents(); board.setString(" . ", forType: .string)
        try XCTAssertNotNil(try PasteboardCodec.read(from: board))
    }
}
