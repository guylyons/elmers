import Foundation
import ElmersCore

final class HistoryTests {
    func testSourceTransitionDoesNotAttributeExcludedContentToNextApp() {
        var policy = CapturePolicy(source: "password.app")
        XCTAssertTrue(!policy.accepts(currentSource: "notes.app", declaredSource: nil, excluded: ["password.app"]))
        XCTAssertTrue(policy.accepts(currentSource: "notes.app", declaredSource: nil, excluded: ["password.app"]))
        XCTAssertTrue(!policy.accepts(currentSource: "notes.app", declaredSource: "password.app", excluded: ["password.app"]))
    }

    func testAllowedAppTransitionRetainsClipboardGeneration() {
        var policy = CapturePolicy(source: "notes.app")
        XCTAssertTrue(policy.accepts(currentSource: "browser.app", declaredSource: nil, excluded: ["password.app"]))
        XCTAssertTrue(policy.accepts(currentSource: "password.app", declaredSource: "notes.app", excluded: ["password.app"]))
    }

    func testRepeatedRichTextMetadataReadsAvoidRepeatedParsing() {
        let rtf = "{\\rtf1\\ansi " + String(repeating: "clipboard ", count: 1500) + "}"
        let item = ClipboardItem(payload: .init(items: [["public.rtf": Data(rtf.utf8)]]), source: "Fixture")
        let started = ProcessInfo.processInfo.systemUptime
        for _ in 0..<100 {
            XCTAssertEqual(item.kind, .text)
            XCTAssertTrue(item.text.hasPrefix("clipboard"))
        }
        let milliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1000
        print("Rich-text metadata, 100 reads: \(Int(milliseconds)) ms")
        XCTAssertTrue(milliseconds < 20)
    }

    func testDuplicateMovesToFrontAndKeepsPinboardMembership() {
        var history = History()
        let first = history.capture(.text("alpha"), source: "Editor")
        let board = history.createBoard(name: "Snippets")
        history.pin(first.id, to: board.id)
        _ = history.capture(.text("beta"), source: "Browser")
        let again = history.capture(.text("alpha"), source: "Terminal")
        XCTAssertEqual(history.items.count, 2)
        XCTAssertEqual(history.items.first?.id, first.id)
        XCTAssertEqual(again.boardIDs, [board.id])
    }

    func testSearchMatchesTextAndSourceCaseInsensitivelyAndFiltersType() {
        var history = History()
        _ = history.capture(.text("Café recipe"), source: "Notes")
        _ = history.capture(.text("https://example.com"), source: "Safari")
        XCTAssertEqual(history.filtered(query: "CAFE").count, 1)
        XCTAssertEqual(history.filtered(query: "safari").first?.kind, .link)
        XCTAssertTrue(history.filtered(query: "recipe", kind: .link).isEmpty)
    }

    func testTypingCategoryKeywordsFiltersByKind() {
        var history = History()
        let image = history.capture(ClipboardPayload(items: [["public.png": Data([0, 1, 255])]]), source: "Preview")
        _ = history.capture(.text("An image of a cat"), source: "Notes")
        _ = history.capture(.text("https://example.com/cat.png"), source: "Safari")
        history.renameItem(image.id, title: "Cat photo")
        XCTAssertEqual(history.filtered(query: "Image").map(\.id), [image.id])
        XCTAssertEqual(history.filtered(query: "IMAGES").map(\.id), [image.id])
        XCTAssertEqual(history.filtered(query: "link").map(\.kind), [.link])
        XCTAssertEqual(history.filtered(query: "image cat").map(\.id), [image.id])
        XCTAssertTrue(history.filtered(query: "image dog").isEmpty)
        // With a type chosen in the filter menu, the word is an ordinary search term.
        XCTAssertEqual(history.filtered(query: "image", kind: .text).map(\.text), ["An image of a cat"])
        XCTAssertEqual(SearchQuery("Photos cat").kind, .image)
        XCTAssertEqual(SearchQuery("Photos cat").terms, ["cat"])
        XCTAssertNil(SearchQuery("imagery").kind)
    }

    func testRetentionPreservesPinnedItems() {
        var history = History()
        let old = Date(timeIntervalSince1970: 100)
        let pinned = history.capture(.text("keep"), source: "Notes", at: old)
        _ = history.capture(.text("expire"), source: "Notes", at: old)
        let board = history.createBoard(name: "Saved")
        history.pin(pinned.id, to: board.id)
        history.prune(before: Date(timeIntervalSince1970: 200), limit: 100)
        XCTAssertEqual(history.items.map(\.text), ["keep"])
    }

    func testDeletingBoardPreservesClipboardItem() {
        var history = History()
        let item = history.capture(.text("keep"), source: "Notes")
        let board = history.createBoard(name: "Saved")
        history.pin(item.id, to: board.id)
        history.deleteBoard(board.id)
        XCTAssertEqual(history.items.count, 1)
        XCTAssertTrue(history.items[0].boardIDs.isEmpty)
    }

    func testArchiveRoundTripPreservesBinaryFormatsAndBoards() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = Archive(url: directory.appendingPathComponent("history.plist"))
        var history = History()
        let payload = ClipboardPayload(items: [["public.png": Data([0, 1, 255]), "public.utf8-plain-text": Data("image".utf8)]])
        let item = history.capture(payload, source: "Preview")
        let board = history.createBoard(name: "Images")
        history.pin(item.id, to: board.id)
        let link = history.capture(.text("https://example.com/page"), source: "Browser")
        history.setLinkPreview(link.id, LinkPreview(title: "Example", image: Data([9, 8, 7])))
        history.setRecognizedText(item.id, "invoice 4711")
        XCTAssertEqual(history.filtered(query: "4711").map(\.id), [item.id])
        XCTAssertEqual(history.filtered(query: "example").map(\.id), [link.id])
        try archive.save(history)
        let restored = try archive.load()
        XCTAssertEqual(restored.items[0].linkPreview, LinkPreview(title: "Example", image: Data([9, 8, 7])))
        XCTAssertNil(restored.items[1].linkPreview)
        XCTAssertEqual(restored.items[1].recognizedText, "invoice 4711")
        XCTAssertEqual(restored.items[1].payload, payload)
        XCTAssertEqual(restored.items[1].boardIDs, [board.id])
        XCTAssertEqual(restored.boards[0].name, "Images")
    }

    func testCorruptArchiveIsRejectedAndNeverOverwrittenByLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let corrupt = Data("not an archive".utf8)
        try corrupt.write(to: url)
        XCTAssertThrowsError(try Archive(url: url).load())
        try XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }
}
