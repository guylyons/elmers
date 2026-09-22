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
    private func contentsIfPresent(_ url: URL) throws -> Data? {
        FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
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

    func testReappearedLegacyArchiveMergesWithoutLosingEitherHistory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = HistoryStore(directory: directory)

        var common = History()
        let shared = common.capture(.text("original payload"), source: "Notes")
        let sharedBoard = common.createBoard(name: "Shared")
        common.pin(shared.id, to: sharedBoard.id)
        try Archive(url: paths.legacyArchiveURL).save(common)
        let firstArchive = try Data(contentsOf: paths.legacyArchiveURL)

        var databaseHistory = common
        let databaseOnly = databaseHistory.capture(.text("database only"), source: "Terminal")
        let databaseBoard = databaseHistory.createBoard(name: "Database Board")
        databaseHistory.pin(databaseOnly.id, to: databaseBoard.id)
        do {
            let writer = HistoryStore(directory: directory)
            _ = try writer.load()
            try XCTAssertEqual(try Data(contentsOf: writer.migratedArchiveURL), firstArchive)
            try writer.save(databaseHistory)
        }

        var legacyHistory = common
        legacyHistory.renameBoard(sharedBoard.id, to: "Recovered Shared")
        legacyHistory.recolorBoard(sharedBoard.id, color: 6)
        legacyHistory.editItem(shared.id, payload: .text("legacy payload"))
        legacyHistory.renameItem(shared.id, title: "Recovered title")
        legacyHistory.unpin(shared.id, from: sharedBoard.id)
        let legacyBoard = legacyHistory.createBoard(name: "Legacy Board")
        legacyHistory.pin(shared.id, to: legacyBoard.id)
        let legacyOnly = legacyHistory.capture(.text("legacy only"), source: "Safari")
        legacyHistory.pin(legacyOnly.id, to: legacyBoard.id)
        try Archive(url: paths.legacyArchiveURL).save(legacyHistory)

        let reappearedArchive = try Data(contentsOf: paths.legacyArchiveURL)
        let merged = try HistoryStore(directory: directory).load()

        XCTAssertEqual(Set(merged.items.map(\.id)), Set([shared.id, databaseOnly.id, legacyOnly.id]))
        let recoveredShared = merged.items.first { $0.id == shared.id }
        XCTAssertEqual(recoveredShared?.text, "legacy payload")
        XCTAssertEqual(recoveredShared?.title, "Recovered title")
        XCTAssertEqual(recoveredShared?.boardIDs, Set([sharedBoard.id, legacyBoard.id]))
        XCTAssertEqual(merged.boards.map(\.id), [sharedBoard.id, legacyBoard.id, databaseBoard.id])
        XCTAssertEqual(merged.boards.first?.name, "Recovered Shared")
        XCTAssertEqual(merged.boards.first?.colorIndex, 6)
        XCTAssertTrue(!FileManager.default.fileExists(atPath: paths.legacyArchiveURL.path))
        try XCTAssertEqual(try Data(contentsOf: paths.migratedArchiveURL), firstArchive)
        try XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("history.plist.recovered")), reappearedArchive)

        let recoveryDirectories = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("history-recovery-") }
        XCTAssertEqual(recoveryDirectories.count, 1)
        try XCTAssertEqual(try permissions(recoveryDirectories[0]), 0o700)
        try XCTAssertEqual(try Data(contentsOf: recoveryDirectories[0].appendingPathComponent("history.plist")), reappearedArchive)
        let backedUpDatabase = try HistoryStore(directory: recoveryDirectories[0], readOnly: true).load()
        XCTAssertEqual(backedUpDatabase.items, databaseHistory.items)
        XCTAssertEqual(backedUpDatabase.boards, databaseHistory.boards)

        let reopened = try HistoryStore(directory: directory).load()
        XCTAssertEqual(reopened.items, merged.items)
        XCTAssertEqual(reopened.boards, merged.boards)
        let finalRecoveryDirectories = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("history-recovery-") }
        XCTAssertEqual(finalRecoveryDirectories.count, 1)
    }

    func testUnreadableReappearedArchiveLeavesDatabaseAndArchiveUntouched() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = HistoryStore(directory: directory)
        var history = History()
        history.capture(.text("database survives"), source: "Notes")
        do {
            let writer = HistoryStore(directory: directory)
            _ = try writer.load()
            try writer.save(history)
        }
        let corrupt = Data("not an archive".utf8)
        try corrupt.write(to: paths.legacyArchiveURL)

        let databaseBefore = try contentsIfPresent(paths.databaseURL)
        let walBefore = try contentsIfPresent(URL(fileURLWithPath: paths.databaseURL.path + "-wal"))
        XCTAssertThrowsError(try HistoryStore(directory: directory).load())
        try XCTAssertEqual(try contentsIfPresent(paths.databaseURL), databaseBefore)
        try XCTAssertEqual(try contentsIfPresent(URL(fileURLWithPath: paths.databaseURL.path + "-wal")), walBefore)
        try XCTAssertEqual(try Data(contentsOf: paths.legacyArchiveURL), corrupt)
        let recoveryDirectories = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("history-recovery-") }
        XCTAssertTrue(recoveryDirectories.isEmpty)
    }

    func testRecoveryDoesNotInvalidateAnAlreadyOpenWriter() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = HistoryStore(directory: directory)
        var writerHistory = History()
        writerHistory.capture(.text("database item"), source: "Notes")
        let writer = HistoryStore(directory: directory)
        _ = try writer.load()
        try writer.save(writerHistory)

        var legacy = History()
        legacy.capture(.text("legacy item"), source: "Safari")
        try Archive(url: paths.legacyArchiveURL).save(legacy)
        _ = try HistoryStore(directory: directory).load()

        let later = writerHistory.capture(.text("later writer item"), source: "Terminal")
        try writer.save(writerHistory)
        let reopened = try HistoryStore(directory: directory, readOnly: true).load()
        XCTAssertTrue(reopened.items.contains(where: { $0.id == later.id }))
        XCTAssertTrue(reopened.items.contains(where: { $0.text == "legacy item" }))
    }

    func testLoadReadsOneSnapshotDuringConcurrentSaves() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var history = History()
        let item = history.capture(.text("version 0"), source: "Notes")
        let writer = HistoryStore(directory: directory)
        _ = try writer.load()
        try writer.save(history)

        let lock = NSLock()
        var writerError: Error?
        let started = DispatchSemaphore(value: 0)
        let finished = DispatchGroup()
        finished.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            started.signal()
            do {
                for version in 1...200 {
                    history.editItem(item.id, payload: .text("version \(version)"))
                    try writer.save(history)
                }
            } catch { lock.lock(); writerError = error; lock.unlock() }
            finished.leave()
        }
        started.wait()
        var inconsistent = false
        for _ in 0..<200 {
            let loaded = try HistoryStore(directory: directory, readOnly: true).load()
            if loaded.items.contains(where: { $0.fingerprint != $0.payload.fingerprint }) { inconsistent = true; break }
        }
        finished.wait()
        lock.lock(); let failure = writerError; lock.unlock()
        XCTAssertNil(failure)
        XCTAssertTrue(!inconsistent)
    }

    func testConversionRetiresLegacyWhenMigratedArchiveAlreadyExists() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = HistoryStore(directory: directory)
        var older = History(); older.capture(.text("older backup"), source: "Notes")
        try Archive(url: paths.migratedArchiveURL).save(older)
        var active = History()
        let item = active.capture(.text("active item"), source: "Safari")
        try Archive(url: paths.legacyArchiveURL).save(active)

        let store = HistoryStore(directory: directory)
        var converted = try store.load()
        converted.renameItem(item.id, title: "must survive")
        try store.save(converted)
        let reopened = try HistoryStore(directory: directory).load()

        XCTAssertEqual(reopened.items.first(where: { $0.id == item.id })?.title, "must survive")
        XCTAssertTrue(!FileManager.default.fileExists(atPath: paths.legacyArchiveURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.plist.migrated-2").path))
    }

    func testRollbackBackupExportsFreshHistoryWithoutOverwritingPriorBackup() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected = Self.richHistory()
        let store = HistoryStore(directory: directory)
        _ = try store.load()
        try store.save(expected)

        let backup = try backupStorageForRollback(directory: directory)
        let original = try Data(contentsOf: backup)
        let restored = try Archive(url: backup).load()
        XCTAssertEqual(restored.items, expected.items)
        XCTAssertEqual(restored.boards, expected.boards)
        var later = expected
        later.capture(.text("captured after first backup"), source: "Notes")
        try store.save(later)
        let freshBackup = try backupStorageForRollback(directory: directory)
        XCTAssertTrue(freshBackup != backup)
        let fresh = try Archive(url: freshBackup).load()
        XCTAssertEqual(fresh.items, later.items)
        XCTAssertEqual(fresh.boards, later.boards)
        try XCTAssertEqual(try Data(contentsOf: backup), original)
        try XCTAssertEqual(try permissions(backup), 0o600)
        try XCTAssertEqual(try permissions(freshBackup), 0o600)
    }

    // MARK: - Fixtures for order, multi-writer and failed-save checks

    private struct FixtureError: LocalizedError {
        let detail: String
        var errorDescription: String? { "store fixture failed: \(detail)" }
    }

    /// Rewrites the archived item array in reverse, producing the kind of plist an older build left behind
    /// when a background decode inserted an item with an older date above a newer one.
    private func reverseArchivedItemOrder(at url: URL) throws {
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard var root = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), options: [],
                                                                   format: &format) as? [String: Any],
              var history = root["history"] as? [String: Any],
              let items = history["items"] as? [Any] else { throw FixtureError(detail: "archive layout") }
        history["items"] = Array(items.reversed())
        root["history"] = history
        try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0).write(to: url)
    }

    /// Runs one statement on a second connection to the same file, standing in for another process.
    private func executeOnSecondConnection(_ sql: String, at url: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
            sqlite3_close(handle); throw FixtureError(detail: "second connection")
        }
        defer { sqlite3_close(handle) }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw FixtureError(detail: String(cString: sqlite3_errmsg(handle)))
        }
    }
    private func installAbortTrigger(at url: URL) throws {
        try executeOnSecondConnection("""
            CREATE TRIGGER elmers_check_abort BEFORE INSERT ON items WHEN NEW.title = 'boom'
            BEGIN SELECT RAISE(ABORT, 'injected write failure'); END
            """, at: url)
    }
    private func removeAbortTrigger(at url: URL) throws {
        try executeOnSecondConnection("DROP TRIGGER elmers_check_abort", at: url)
    }
    private func recoveryDirectories(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("history-recovery-") }
    }

    func testOutOfOrderLegacyArchiveConvertsAndIsStoredNewestFirst() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = Self.richHistory()
        let store = HistoryStore(directory: directory)
        try Archive(url: store.legacyArchiveURL).save(history)
        try reverseArchivedItemOrder(at: store.legacyArchiveURL)
        let scrambled = try Archive(url: store.legacyArchiveURL).load()
        XCTAssertEqual(scrambled.items.map(\.id), history.items.map(\.id).reversed())
        XCTAssertTrue(scrambled.items.map(\.copiedAt) != scrambled.items.map(\.copiedAt).sorted(by: >))

        let converted = try store.load()
        XCTAssertEqual(converted.items.count, history.items.count)
        XCTAssertEqual(Set(converted.items.map(\.id)), Set(history.items.map(\.id)))
        for item in history.items { XCTAssertEqual(converted.items.first { $0.id == item.id }, item) }
        XCTAssertEqual(converted.items.map(\.copiedAt), converted.items.map(\.copiedAt).sorted(by: >))
        XCTAssertEqual(converted.boards, history.boards)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.migratedArchiveURL.path))
        let reopened = try HistoryStore(directory: directory, readOnly: true).load()
        XCTAssertEqual(reopened.items, converted.items)
    }

    func testRecoveryMergesItemsThatShareATimestamp() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = HistoryStore(directory: directory)
        let instant = Date(timeIntervalSinceReferenceDate: 700_000_000)
        var common = History()
        let shared = common.capture(.text("shared at the tie"), source: "Notes", at: instant)
        try Archive(url: paths.legacyArchiveURL).save(common)

        var databaseHistory = common
        let databaseOnly = databaseHistory.capture(.text("database at the tie"), source: "Terminal", at: instant)
        do {
            let writer = HistoryStore(directory: directory)
            _ = try writer.load()
            try writer.save(databaseHistory)
        }
        var legacyHistory = common
        legacyHistory.renameItem(shared.id, title: "Recovered tie")
        try Archive(url: paths.legacyArchiveURL).save(legacyHistory)

        let merged = try HistoryStore(directory: directory).load()
        XCTAssertEqual(Set(merged.items.map(\.id)), Set([shared.id, databaseOnly.id]))
        XCTAssertEqual(merged.items.first { $0.id == shared.id }?.title, "Recovered tie")
        XCTAssertEqual(merged.items.first { $0.id == databaseOnly.id }?.text, "database at the tie")
        XCTAssertEqual(merged.items.map(\.copiedAt), [instant, instant])
        XCTAssertTrue(!FileManager.default.fileExists(atPath: paths.legacyArchiveURL.path))
        try XCTAssertEqual(try recoveryDirectories(in: directory).count, 1)
    }

    func testRepeatedFailingRecoveryReusesOneBackupDirectory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = HistoryStore(directory: directory)
        var databaseHistory = History()
        let survivor = databaseHistory.capture(.text("database survives"), source: "Notes")
        do {
            let writer = HistoryStore(directory: directory)
            _ = try writer.load()
            try writer.save(databaseHistory)
        }
        var legacy = History()
        let arriving = legacy.capture(.text("legacy arrives"), source: "Safari")
        legacy.renameItem(arriving.id, title: "boom")
        try Archive(url: paths.legacyArchiveURL).save(legacy)
        let archiveBytes = try Data(contentsOf: paths.legacyArchiveURL)
        try installAbortTrigger(at: paths.databaseURL)

        for _ in 0..<2 { XCTAssertThrowsError(try HistoryStore(directory: directory).load()) }
        try XCTAssertEqual(try recoveryDirectories(in: directory).count, 1)
        try XCTAssertEqual(try Data(contentsOf: paths.legacyArchiveURL), archiveBytes)
        let untouched = try HistoryStore(directory: directory, readOnly: true).load()
        XCTAssertEqual(untouched.items.map(\.id), [survivor.id])

        try removeAbortTrigger(at: paths.databaseURL)
        let recovered = try HistoryStore(directory: directory).load()
        XCTAssertEqual(Set(recovered.items.map(\.id)), Set([survivor.id, arriving.id]))
        try XCTAssertEqual(try recoveryDirectories(in: directory).count, 1)
    }


    func testRenameKeepsPayloadAfterAnotherWriterDeletesTheRow() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var history = History()
        let item = history.capture(.text("payload must survive"), source: "Notes")
        let keeper = history.capture(.text("untouched neighbour"), source: "Safari")
        let writer = HistoryStore(directory: directory)
        _ = try writer.load()
        try writer.save(history)

        let second = HistoryStore(directory: directory)
        var secondHistory = try second.load()
        secondHistory.delete(item.id)
        let secondOnly = secondHistory.capture(.text("written by the other writer"), source: "Terminal")
        try second.save(secondHistory)

        history.renameItem(item.id, title: "Renamed after deletion")
        try writer.save(history)

        let reloaded = try HistoryStore(directory: directory, readOnly: true).load()
        let restored = reloaded.items.first { $0.id == item.id }
        XCTAssertEqual(restored?.title, "Renamed after deletion")
        XCTAssertEqual(restored?.text, "payload must survive")
        XCTAssertEqual(restored?.kind, .text)
        XCTAssertTrue(reloaded.items.contains { $0.id == keeper.id })
        XCTAssertTrue(reloaded.items.contains { $0.id == secondOnly.id })
    }

    func testFailedSaveKeepsItsChangesForTheNextSave() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var history = History()
        let first = history.capture(.text("first"), source: "Notes")
        let store = HistoryStore(directory: directory)
        _ = try store.load()
        try store.save(history)

        history.createBoard(name: "Ledger")
        history.renameItem(first.id, title: "kept change")
        let blocked = history.capture(.text("blocked"), source: "Safari")
        history.renameItem(blocked.id, title: "boom")
        try installAbortTrigger(at: store.databaseURL)
        XCTAssertThrowsError(try store.save(history))

        let afterFailure = try HistoryStore(directory: directory, readOnly: true).load()
        XCTAssertTrue(afterFailure.boards.isEmpty)
        XCTAssertEqual(afterFailure.items.map(\.id), [first.id])
        XCTAssertNil(afterFailure.items.first?.title)

        try removeAbortTrigger(at: store.databaseURL)
        try store.save(history)
        let reloaded = try HistoryStore(directory: directory, readOnly: true).load()
        XCTAssertEqual(reloaded.boards.map(\.name), ["Ledger"])
        XCTAssertEqual(reloaded.items.first { $0.id == first.id }?.title, "kept change")
        XCTAssertEqual(reloaded.items.first { $0.id == blocked.id }?.text, "blocked")
        XCTAssertEqual(reloaded.items.first { $0.id == blocked.id }?.title, "boom")
    }
}
