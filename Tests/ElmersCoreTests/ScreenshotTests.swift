import Foundation
import ElmersCore

final class ScreenshotTests {
    private func info(_ path: String = "/tmp/Screenshot 2026-09-17.png") -> ScreenshotInfo {
        ScreenshotInfo(path: path, captureType: "selection", pixelWidth: 1512, pixelHeight: 982)
    }
    private func payload(_ path: String = "/tmp/Screenshot 2026-09-17.png") -> ClipboardPayload {
        let url = URL(fileURLWithPath: path).absoluteString
        return ClipboardPayload(items: [["public.file-url": Data(url.utf8), "public.png": Data([0, 1, 255])]])
    }

    /// The marker, not the payload, decides the kind: the payload alone would read as a file.
    func testMarkerMakesTheItemAScreenshot() {
        let plain = ClipboardItem(payload: payload(), source: "Finder")
        XCTAssertEqual(plain.kind, .file)
        let shot = ClipboardItem(payload: payload(), source: "Screenshot", screenshot: info())
        XCTAssertEqual(shot.kind, .screenshot)
        XCTAssertEqual(shot.screenshot?.captureType, "selection")
        XCTAssertEqual(shot.screenshot?.pixelWidth, 1512)
    }

    /// Assigning or clearing the marker after the fact must refresh the cached kind.
    func testClearingTheMarkerRestoresTheDerivedKind() {
        var shot = ClipboardItem(payload: payload(), source: "Screenshot", screenshot: info())
        XCTAssertEqual(shot.kind, .screenshot)
        shot.screenshot = nil
        XCTAssertEqual(shot.kind, .file)
    }

    /// The archive stays at version 1, so the marker must survive a round trip.
    func testArchiveRoundTripPreservesTheMarker() throws {
        var history = History()
        _ = history.capture(payload(), source: "Screenshot", screenshot: info())
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("elmers-shot-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = Archive(url: url)
        try archive.save(history)
        let loaded = try archive.load()
        XCTAssertEqual(loaded.items.count, 1)
        XCTAssertEqual(loaded.items[0].kind, .screenshot)
        XCTAssertEqual(loaded.items[0].screenshot?.path, info().path)
        XCTAssertEqual(loaded.items[0].screenshot?.pixelHeight, 982)
    }

    /// An archive written before this feature has no marker and must still load.
    func testArchiveWithoutTheMarkerStillLoads() throws {
        var history = History()
        _ = history.capture(.text("older archive"), source: "Notes")
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("elmers-old-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = Archive(url: url)
        try archive.save(history)
        let loaded = try archive.load()
        XCTAssertNil(loaded.items[0].screenshot)
        XCTAssertEqual(loaded.items[0].kind, .text)
    }

    /// Detecting the same file twice promotes the existing item rather than duplicating it.
    func testSameFileCapturedTwicePromotesInsteadOfDuplicating() {
        var history = History()
        let first = history.capture(payload(), source: "Screenshot", screenshot: info())
        _ = history.capture(.text("something else"), source: "Notes")
        let second = history.capture(payload(), source: "Screenshot", screenshot: info())
        XCTAssertEqual(history.items.count, 2)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(history.items[0].id, first.id)
    }
}
