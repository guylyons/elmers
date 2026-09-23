import Foundation
import SQLite3
import ElmersCore

/// Deleted and replaced clipboard content must not stay readable in the database, its WAL or freed pages,
/// and the history folder must stay out of Time Machine.
final class StorageSecurityTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("elmers-security-" + UUID().uuidString)
    }
    /// Every byte SQLite keeps for this store: the database, its WAL and shared memory, any rollback journal.
    private func storedBytes(_ directory: URL) throws -> Data {
        var bytes = Data()
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) where name.hasPrefix("history.sqlite") {
            bytes.append(try Data(contentsOf: directory.appendingPathComponent(name)))
        }
        return bytes
    }
    private func contains(_ data: Data, _ marker: String) -> Bool { data.range(of: Data(marker.utf8)) != nil }
    private func pragma(_ url: URL, _ name: String) -> Int {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_close_v2(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA \(name)", -1, &statement, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : -1
    }

    func testDeletedAndReplacedContentLeavesNoTraceOnDisk() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directory: directory)
        var history = try store.load()
        let secret = "secret-\(UUID().uuidString)"
        // Large enough to spill onto overflow pages, which are freed whole rather than rewritten.
        let item = history.capture(.text(secret + String(repeating: " padding", count: 4000)), source: "Notes")
        let edited = history.capture(.text("edit me"), source: "Notes")
        let oldTitle = "title-\(UUID().uuidString)", oldText = "ocr-\(UUID().uuidString)"
        history.renameItem(edited.id, title: oldTitle)
        history.setRecognizedText(edited.id, oldText)
        try store.save(history)
        let saved = try storedBytes(directory)
        XCTAssertTrue(contains(saved, secret))

        history.delete(item.id)
        history.renameItem(edited.id, title: "new title")
        history.setRecognizedText(edited.id, "new text")
        history.editItem(edited.id, payload: .text("edited"))
        try store.save(history)
        let bytes = try storedBytes(directory)
        for marker in [secret, oldTitle, oldText, "edit me"] { XCTAssertTrue(!contains(bytes, marker)) }
        let reopened = try HistoryStore(directory: directory, readOnly: true).load()
        XCTAssertEqual(reopened.items.map(\.text), ["edited"])
        XCTAssertEqual(pragma(store.databaseURL, "freelist_count"), 0)
    }

    func testExistingDatabaseIsScrubbedWhenOpened() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A database written by an earlier build: no auto-vacuum, fast secure delete, a deleted row left in free pages.
        let url = directory.appendingPathComponent("history.sqlite")
        let secret = "legacy-\(UUID().uuidString)"
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        let sql = "PRAGMA secure_delete = OFF; PRAGMA journal_mode = WAL; " + HistoryStore.migrations[1]! + """
            ; PRAGMA user_version = 1;
            INSERT INTO items (id, copied_at, source, fingerprint, payload_item_count) VALUES ('\(UUID().uuidString)', 0, 'Notes', 'f', 1);
            INSERT INTO items (id, copied_at, source, fingerprint, payload_item_count, title)
                VALUES ('\(UUID().uuidString)', 1, 'Notes', 'g', 1, '\(secret)' || printf('%.5000c', 'x'));
            DELETE FROM items WHERE copied_at = 1;
            PRAGMA wal_checkpoint(TRUNCATE);
            """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let legacy = try storedBytes(directory)
        XCTAssertTrue(contains(legacy, secret))

        let history = try HistoryStore(directory: directory).load()
        XCTAssertEqual(history.items.count, 1)
        let scrubbed = try storedBytes(directory)
        XCTAssertTrue(!contains(scrubbed, secret))
        XCTAssertEqual(pragma(url, "auto_vacuum"), 2)
    }

    func testHistoryFolderIsExcludedFromBackups() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try HistoryStore(directory: directory).load()
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }
}

extension StorageSecurityTests {
    /// The one-time scrub needs exclusive access; another open connection must not stop history from loading.
    func testScrubWaitsForExclusiveAccessWithoutBlockingLoad() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("history.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        // A current-schema database, so the open below needs no migration (which would wait for the write lock).
        let schema = (1...HistoryStore.schemaVersion).map { HistoryStore.migrations[$0]! }.joined(separator: "; ")
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA journal_mode = WAL; " + schema + "; PRAGMA user_version = \(HistoryStore.schemaVersion);", nil, nil, nil), SQLITE_OK)
        // Another process mid-write keeps VACUUM from running.
        XCTAssertEqual(sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil), SQLITE_OK)
        let history = try HistoryStore(directory: directory).load()
        XCTAssertTrue(history.items.isEmpty)
        sqlite3_exec(db, "COMMIT", nil, nil, nil); sqlite3_close(db)
        _ = try HistoryStore(directory: directory).load()
        XCTAssertEqual(pragma(url, "auto_vacuum"), 2)
    }
}
