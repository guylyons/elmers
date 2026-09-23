import Foundation
import ElmersCore

/// Large representations stay in the database until used; these checks guard against a partial payload ever being
/// saved in place of the stored bytes.
final class LazyPayloadTests {
    private func temporaryDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("elmers-lazy-" + UUID().uuidString) }
    private func bytes(_ count: Int, seed: UInt8) -> Data { Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31) ^ seed }) }
    /// A history with one large image (plus a small text representation) and one text item, saved and reloaded.
    private func stored(_ directory: URL) throws -> (History, UUID, Data) {
        var history = History()
        let large = bytes(HistoryStore.inlineLimit * 4, seed: 7)
        let image = history.capture(.init(items: [["public.png": large, "public.utf8-plain-text": Data("caption".utf8)]]), source: "Preview")
        history.capture(.text("plain words"), source: "Notes")
        let store = HistoryStore(directory: directory)
        _ = try store.load(); try store.save(history)
        return (try HistoryStore(directory: directory).load(), image.id, large)
    }

    func testLargeRepresentationsLoadOnDemand() throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let (history, id, large) = try stored(directory)
        let image = history.items.first { $0.id == id }!
        XCTAssertTrue(image.payload.hasDeferredRepresentations)
        XCTAssertEqual(image.kind, .image)
        XCTAssertEqual(image.text, "caption")
        XCTAssertEqual(image.byteCount, large.count + "caption".utf8.count)
        XCTAssertEqual(image.payload.itemCount, 1)
        let materialized = try image.payload.materializedItems()
        XCTAssertEqual(materialized[0]["public.png"], large)
        XCTAssertEqual(image.payload.items[0]["public.png"], large)
        XCTAssertTrue(!(history.items.first { $0.id != id }!.payload.hasDeferredRepresentations))
    }

    func testRenamingALazyItemKeepsItsStoredBytes() throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let (loaded, id, large) = try stored(directory)
        var history = loaded
        let store = HistoryStore(directory: directory)
        _ = try store.load()
        history.renameItem(id, title: "Renamed")
        try store.save(history)
        XCTAssertEqual(store.lastSave.payloadsWritten, 0)
        let reloaded = try HistoryStore(directory: directory).load().items.first { $0.id == id }!
        XCTAssertEqual(reloaded.title, "Renamed")
        let reloadedBytes = try reloaded.payload.materializedItems()[0]["public.png"]
        XCTAssertEqual(reloadedBytes, large)
    }

    func testUndoingADeletionRestoresRetainedBytes() throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directory: directory)
        _ = try stored(directory)
        var history = try store.load()
        let image = history.items.first { $0.payload.hasDeferredRepresentations }!
        try image.payload.retainDeferred()
        history.delete(image.id); try store.save(history)
        history.restoreItems([image]); try store.save(history)
        let reloaded = try HistoryStore(directory: directory).load().items.first { $0.id == image.id }!
        let restoredBytes = try reloaded.payload.materializedItems()[0]["public.png"]
        XCTAssertEqual(restoredBytes?.count, HistoryStore.inlineLimit * 4)
    }

    func testUnreadableContentIsNeverSavedPartially() throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        _ = try stored(directory)
        let writer = HistoryStore(directory: directory)
        var history = try writer.load()
        let image = history.items.first { $0.payload.hasDeferredRepresentations }!
        // Another writer deletes the item; this writer's copy can no longer read its image.
        let other = HistoryStore(directory: directory)
        var otherHistory = try other.load(); otherHistory.delete(image.id); try other.save(otherHistory)
        XCTAssertThrowsError(try image.payload.materializedItems())
        // Undoing without a retained copy would bring the item back as a caption only; the save leaves it out instead.
        history.delete(image.id); try writer.save(history)
        history.restoreItems([image]); try writer.save(history)
        let reloaded = try HistoryStore(directory: directory).load()
        XCTAssertNil(reloaded.items.first { $0.id == image.id })
        XCTAssertEqual(reloaded.items.map(\.text), ["plain words"])
    }

    func testAnEditedItemNeverReadsItsReplacementIntoTheOldPayload() throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        _ = try stored(directory)
        let writer = HistoryStore(directory: directory)
        var history = try writer.load()
        let original = history.items.first { $0.payload.hasDeferredRepresentations }!
        history.editItem(original.id, payload: .init(items: [["public.png": bytes(HistoryStore.inlineLimit * 2, seed: 99)]]))
        try writer.save(history)
        // The old payload's rows were replaced; reading them now would mix in the new image, so the read fails.
        XCTAssertThrowsError(try original.payload.materializedItems())
    }

    func testDuplicateMergeIntoALazyImageKeepsItsBytes() throws {
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let (loaded, id, large) = try stored(directory)
        var history = loaded
        let stored = history.items.first { $0.id == id }!
        // A screenshot file of the same picture arrives: its representations merge into the clipboard item.
        history.replaceItem({ var item = stored; item.imageDigest = "same"; return item }())
        history.capture(.init(items: [["public.tiff": Data([1, 2, 3])]]), source: "Screenshot", at: stored.copiedAt,
                        screenshot: ScreenshotOrigin(originalURL: URL(fileURLWithPath: "/tmp/shot.png"), fileIdentity: "x"), imageDigest: "same")
        let merged = history.items.first { $0.id == id }!
        XCTAssertEqual(merged.payload.items[0]["public.png"], large)
        XCTAssertEqual(merged.payload.items[0]["public.tiff"], Data([1, 2, 3]))
    }
}
