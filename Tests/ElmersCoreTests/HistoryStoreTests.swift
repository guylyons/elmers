import Foundation
import SQLite3
import ElmersCore

final class HistoryStoreTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("elmers-store-" + UUID().uuidString)
    }
    private func permissions(_ url: URL) throws -> Int {
        try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int ?? -1
    }
    static func richHistory() -> History {
        var history = History()
        let instant = Date(timeIntervalSinceReferenceDate: 800_000_000.125)
        let image = history.capture(.init(items: [["public.png": Data([0, 1, 255]), "public.utf8-plain-text": Data("image".utf8),
                                                   "com.example.empty": Data()], [:]]),
                                    source: "Preview", sourceBundleID: "com.apple.Preview", at: instant.addingTimeInterval(-60),
                                    screenshot: ScreenshotOrigin(originalURL: URL(fileURLWithPath: "/tmp/Screenshot 1.png"),
                                                                 fileIdentity: "1:2:3", bookmark: Data([4, 5])),
                                    imageDigest: "digest")
        let link = history.capture(.text("https://example.com/page"), source: "Safari", at: instant)
        let twin = history.capture(.text("same instant"), source: "Notes", at: instant)
        let blank = history.capture(.text("https://example.org"), source: "Safari", at: instant.addingTimeInterval(-120))
        let work = history.createBoard(name: "Work"), images = history.createBoard(name: "Images")
        history.moveBoard(images.id, before: work.id)
        history.recolorBoard(work.id, color: 5)
        history.pin(image.id, to: images.id); history.pin(image.id, to: work.id); history.pin(twin.id, to: work.id)
        history.renameItem(image.id, title: "Receipt")
        history.setRecognizedText(image.id, "invoice 4711")
        history.setRecognizedText(twin.id, "")
        history.setLinkPreview(link.id, LinkPreview(title: "Example", image: Data([9, 8, 7])))
        history.setLinkPreview(blank.id, LinkPreview())
        return history
    }

    func testNewDirectoryGetsPrivateEmptyDatabase() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directory: directory)
        let history = try store.load()
        XCTAssertTrue(history.items.isEmpty && history.boards.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.databaseURL.path))
        try XCTAssertEqual(try permissions(store.databaseURL), 0o600)
        try XCTAssertEqual(try permissions(directory), 0o700)
        var changed = history
        changed.capture(.text("private"), source: "Notes")
        try store.save(changed)
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) where name.hasPrefix("history.sqlite") {
            try XCTAssertEqual(try permissions(directory.appendingPathComponent(name)), 0o600)
        }
        let reopened = try HistoryStore(directory: directory, readOnly: true).load()
        XCTAssertEqual(reopened.items.map(\.text), ["private"])
    }

    func testDamagedOrNewerDatabaseIsRejectedAndLeftUntouched() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = Data("legacy archive stays put".utf8)
        try legacy.write(to: store.legacyArchiveURL)
        let garbage = Data("not a database".utf8)
        try garbage.write(to: store.databaseURL)
        XCTAssertThrowsError(try store.load())
        try XCTAssertEqual(try Data(contentsOf: store.databaseURL), garbage)
        try FileManager.default.removeItem(at: store.databaseURL)
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(store.databaseURL.path, &handle), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle, "CREATE TABLE future (x); PRAGMA user_version = 99", nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)
        let newer = try Data(contentsOf: store.databaseURL)
        do { _ = try store.load(); XCTAssertTrue(false) }
        catch { XCTAssertEqual(error as? HistoryStore.StoreError, .unsupportedVersion(99)) }
        try XCTAssertEqual(try Data(contentsOf: store.databaseURL), newer)
        try XCTAssertEqual(try Data(contentsOf: store.legacyArchiveURL), legacy)
    }

    func testRoundTripPreservesEveryField() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = Self.richHistory()
        let store = HistoryStore(directory: directory)
        _ = try store.load()
        try store.save(history)
        let restored = try HistoryStore(directory: directory).load()
        XCTAssertEqual(restored.boards, history.boards)
        XCTAssertEqual(restored.items.map(\.id), history.items.map(\.id))
        XCTAssertEqual(restored.items, history.items)
        XCTAssertEqual(restored.items.first { $0.title == "Receipt" }?.payload.items.first?["com.example.empty"], Data())
        XCTAssertEqual(restored.filtered(query: "4711").map(\.title), ["Receipt"])
    }

    func testSavesWriteOnlyWhatChanged() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var history = Self.richHistory()
        let store = HistoryStore(directory: directory)
        _ = try store.load()
        try store.save(history)
        XCTAssertEqual(store.lastSave, .init(itemsWritten: 4, payloadsWritten: 4, itemsDeleted: 0, boardsChanged: true))
        try store.save(history)
        XCTAssertEqual(store.lastSave, .init())
        let image = history.items.first { $0.title == "Receipt" }!
        history.renameItem(image.id, title: "Receipt, March")
        try store.save(history)
        XCTAssertEqual(store.lastSave, .init(itemsWritten: 1))
        let board = history.boards[0]
        history.unpin(image.id, from: board.id)
        try store.save(history)
        XCTAssertEqual(store.lastSave, .init(itemsWritten: 1))
        let added = history.capture(.text("new"), source: "Notes")
        try store.save(history)
        XCTAssertEqual(store.lastSave, .init(itemsWritten: 1, payloadsWritten: 1))
        history.editItem(added.id, payload: .text("edited"))
        try store.save(history)
        XCTAssertEqual(store.lastSave, .init(itemsWritten: 1, payloadsWritten: 1))
        history.recolorBoard(board.id, color: 2)
        try store.save(history)
        XCTAssertEqual(store.lastSave, .init(boardsChanged: true))
        history.delete(added.id)
        try store.save(history)
        XCTAssertEqual(store.lastSave, .init(itemsDeleted: 1))
        let restored = try HistoryStore(directory: directory).load()
        XCTAssertEqual(restored.items, history.items)
        XCTAssertEqual(restored.boards, history.boards)
    }

    func testUndoRestoresSurviveReload() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var history = Self.richHistory()
        let store = HistoryStore(directory: directory)
        _ = try store.load()
        try store.save(history)
        let work = history.boards.first { $0.name == "Work" }!
        let pinned = Set(history.items.filter { $0.boardIDs.contains(work.id) }.map(\.id))
        let workIndex = history.boards.firstIndex(of: work)!
        let receipt = history.items.first { $0.title == "Receipt" }!
        history.deleteBoard(work.id); try store.save(history)
        history.restoreBoard(work, at: workIndex, pinnedIDs: pinned); try store.save(history)
        history.delete(receipt.id); try store.save(history)
        let images = history.boards.first { $0.name == "Images" }!
        history.deleteBoard(images.id); try store.save(history)
        history.restoreItems([receipt]); try store.save(history)
        let restored = try HistoryStore(directory: directory).load()
        XCTAssertEqual(restored.items, history.items)
        XCTAssertEqual(restored.boards, history.boards)
        XCTAssertEqual(restored.items.first { $0.id == receipt.id }?.boardIDs, [images.id, work.id])
    }

    func testLegacyArchiveIsConvertedOnceAndKept() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = Self.richHistory()
        let store = HistoryStore(directory: directory)
        try Archive(url: store.legacyArchiveURL).save(history)
        let original = try Data(contentsOf: store.legacyArchiveURL)
        let converted = try store.load()
        XCTAssertEqual(converted.items, history.items)
        XCTAssertEqual(converted.boards, history.boards)
        XCTAssertTrue(!FileManager.default.fileExists(atPath: store.legacyArchiveURL.path))
        try XCTAssertEqual(try Data(contentsOf: store.migratedArchiveURL), original)
        XCTAssertTrue(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.sqlite.migrating").path))
        try XCTAssertEqual(try permissions(store.databaseURL), 0o600)
        let reopened = try HistoryStore(directory: directory).load()
        XCTAssertEqual(reopened.items, history.items)
        try XCTAssertEqual(try Data(contentsOf: store.migratedArchiveURL), original)
    }

    func testUnreadableLegacyArchiveIsNotConverted() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corrupt = Data("not an archive".utf8)
        try corrupt.write(to: store.legacyArchiveURL)
        XCTAssertThrowsError(try store.load())
        try XCTAssertEqual(try Data(contentsOf: store.legacyArchiveURL), corrupt)
        XCTAssertTrue(!FileManager.default.fileExists(atPath: store.databaseURL.path))
        XCTAssertTrue(!FileManager.default.fileExists(atPath: store.migratedArchiveURL.path))
    }

    func testInterruptedConversionStartsOver() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = Self.richHistory()
        let store = HistoryStore(directory: directory)
        try Archive(url: store.legacyArchiveURL).save(history)
        try Data("half-written".utf8).write(to: directory.appendingPathComponent("history.sqlite.migrating"))
        let converted = try store.load()
        XCTAssertEqual(converted.items, history.items)
    }
}
