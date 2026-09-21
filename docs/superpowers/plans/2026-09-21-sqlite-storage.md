# SQLite History Storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single `history.plist` archive with an SQLite database that writes only what changed on each save, and convert existing history once without losing anything.

**Architecture:** A new `HistoryStore` in `ElmersCore` owns `history.sqlite`. It loads a complete `History` at launch, as `Archive` does today. On each save it compares the history with what it last wrote and writes only the changed rows, in one transaction. `AppModel` keeps its in-memory `History` and its call sites unchanged: only launch loading and `persist()` switch from `Archive` to `HistoryStore`. On first launch the store converts `history.plist` through a staging database, verifies the result for exact equality, and renames the plist to `history.plist.migrated`.

**Tech Stack:** Swift 5.9 package, macOS 14+, the system SQLite library (`import SQLite3`, 3.54 on this Mac), Foundation, and CryptoKit (for the report tool only). No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-21-sqlite-storage-design.md`

## Global Constraints

- No package dependencies. Use `import SQLite3` from the SDK.
- Never modify, replace or delete a history file that cannot be read. That covers a damaged database, a newer schema, an unreadable plist and a conversion that does not match.
- Never delete `history.plist`. After a verified conversion it is renamed to `history.plist.migrated`, and an existing `.migrated` file is never overwritten.
- `history.sqlite`, `history.sqlite-wal` and `history.sqlite-shm` are mode 0600, and `~/Library/Application Support/Elmers` is 0700.
- Never print, log or commit clipboard content. Tools print counts and digests only. Tests use synthetic fixtures.
- Keep the public shape of `History`, `ClipboardItem` and `Pinboard`. New initializers are `internal`.
- The 2,000-item and 32 MB limits stay unchanged. Lazy payload loading, FTS5 and raising the limits belong to the stage 2 follow-up (see the spec).
- Test harness: `scripts/test.sh` builds and runs `ElmersCoreChecks`, a plain executable with `XCTAssert*` shims defined in `Tests/ElmersCoreTests/main.swift`. It is not XCTest, so register every new check in the `checks` array in that file.
- Build through `scripts/swift.sh`, never plain `swift build`. It pins the macOS 26 SDK and keeps caches inside `.build`.
- Work on branch `feat/sqlite-storage`. End commit messages with `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `Sources/ElmersCore/SQLiteDatabase.swift` | create | A thin, internal wrapper over the SQLite C API: open, execute, prepare, bind, step, columns, transactions. It knows nothing about clipboard data. |
| `Sources/ElmersCore/HistoryStore.swift` | create | Schema and migrations, safe opening, reading a `History`, incremental saving, staging and plist conversion. |
| `Sources/ElmersCore/ClipboardItem.swift` | modify | Internal initializers that rebuild a stored `ClipboardItem` and `Pinboard`, identity included. |
| `Sources/ElmersCore/History.swift` | modify | An internal `init(items:boards:)`. |
| `Sources/ElmersCore/Archive.swift` | unchanged | Still reads the version 1 plist during conversion. The app no longer writes it. |
| `Sources/Elmers/AppModel.swift` | modify | Loads from and saves to `HistoryStore` instead of `Archive`. |
| `Tests/ElmersCoreTests/HistoryStoreTests.swift` | create | Store tests. |
| `Tests/ElmersCoreTests/StorageTools.swift` | create | `--storage-report` (counts and digest of the real history) and `--storage-benchmark`. |
| `Tests/ElmersCoreTests/main.swift` | modify | Registers the checks and the two tool flags. |
| `Tests/ElmersCoreTests/LiveCaptureCheck.swift` | modify | Reads the running app's database instead of the plist. |
| `docs/paste-parity.md`, `docs/HANDOFF.md` | modify | Evidence and status (Task 4). |

### Schema (version 1)

- `items`: one row per `ClipboardItem`, holding all metadata. `link_attempted` is NULL when there is no link preview. `payload_item_count` keeps empty pasteboard items.
- `representations`: one row per (item, pasteboard-item index, type), holding the bytes. Deleting an item cascades here.
- `boards`: ordered by `position`. Any pinboard change rewrites every row, because there are only a few.
- `pins`: (item, board). There is deliberately no foreign key to `boards`: undoing an item deletion can bring back a pin to a board deleted since then, and `History` keeps such pins.

Dates are stored as `REAL` `timeIntervalSinceReferenceDate`, which round-trips exactly. Items are read in `copied_at DESC, rowid DESC` order. Rows are inserted from the oldest array position first, so when two items share a time, the newer one comes first.

---

### Task 1: HistoryStore saves and loads a History incrementally

**Files:**
- Create: `Sources/ElmersCore/SQLiteDatabase.swift`
- Create: `Sources/ElmersCore/HistoryStore.swift`
- Modify: `Sources/ElmersCore/ClipboardItem.swift` (the private `refreshMetadata()` and `Pinboard.init`)
- Modify: `Sources/ElmersCore/History.swift:6` (after `public init() {}`)
- Test: `Tests/ElmersCoreTests/HistoryStoreTests.swift`, `Tests/ElmersCoreTests/main.swift`

**Interfaces:**
- Consumes: `History`, `ClipboardItem`, `ClipboardPayload`, `Pinboard`, `LinkPreview`, `ScreenshotOrigin` (existing).
- Produces:
  - `public final class HistoryStore: @unchecked Sendable`
  - `public init(directory: URL, readOnly: Bool = false)`
  - `public func load() throws -> History`
  - `public func save(_ history: History) throws`
  - `public var databaseURL: URL`, `legacyArchiveURL: URL`, `migratedArchiveURL: URL`, and internal `stagingURL: URL`
  - `public private(set) var lastSave: HistoryStore.SaveStatistics`, holding `itemsWritten`, `payloadsWritten`, `itemsDeleted: Int` and `boardsChanged: Bool`, with a memberwise `init` that defaults every field
  - `public enum StoreError: LocalizedError, Equatable`, with cases `unsupportedVersion(Int)`, `damaged(String)`, `migrationMismatch(String)`, `readOnly` and `notLoaded`
  - internal `ClipboardItem.init(id:payload:source:sourceBundleID:copiedAt:boardIDs:title:fingerprint:linkPreview:recognizedText:screenshot:imageDigest:)`, `Pinboard.init(id:name:colorIndex:)` and `History.init(items:boards:)`

- [ ] **Step 1: Create the branch**

```bash
git switch -c feat/sqlite-storage
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/ElmersCoreTests/HistoryStoreTests.swift`:

```swift
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
    /// Every field the store persists, including the awkward cases: an empty representation, an empty
    /// pasteboard item, fractional times, two items copied at the same instant, reordered and recolored
    /// pinboards, a "nothing found" link preview, empty OCR text and a screenshot with a bookmark.
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

    // MARK: Opening safely

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
        // The write-ahead log and shared-memory files hold clipboard data too.
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
        // A failed open never retires the legacy archive.
        try XCTAssertEqual(try Data(contentsOf: store.legacyArchiveURL), legacy)
    }

    // MARK: Saving and reading

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

        // Delete then restore a pinboard, as undo does.
        history.deleteBoard(work.id); try store.save(history)
        history.restoreBoard(work, at: workIndex, pinnedIDs: pinned); try store.save(history)
        // Delete an item, delete one of its boards, then undo only the item deletion: the item comes back
        // pinned to a board that no longer exists, and the store keeps it exactly as the history has it.
        history.delete(receipt.id); try store.save(history)
        let images = history.boards.first { $0.name == "Images" }!
        history.deleteBoard(images.id); try store.save(history)
        history.restoreItems([receipt]); try store.save(history)

        let restored = try HistoryStore(directory: directory).load()
        XCTAssertEqual(restored.items, history.items)
        XCTAssertEqual(restored.boards, history.boards)
        XCTAssertEqual(restored.items.first { $0.id == receipt.id }?.boardIDs, [images.id, work.id])
    }
}
```

In `Tests/ElmersCoreTests/main.swift`, add `let store = HistoryStoreTests()` after `let screenshots = ScreenshotTests()`, and add these entries at the start of the `checks` array:

```swift
    ("store creates a private empty database", store.testNewDirectoryGetsPrivateEmptyDatabase),
    ("store rejects damaged or newer databases", store.testDamagedOrNewerDatabaseIsRejectedAndLeftUntouched),
    ("store round trip preserves every field", store.testRoundTripPreservesEveryField),
    ("store saves only what changed", store.testSavesWriteOnlyWhatChanged),
    ("store keeps undo restores across reload", store.testUndoRestoresSurviveReload),
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `scripts/test.sh`
Expected: the build fails with `cannot find 'HistoryStore' in scope`.

- [ ] **Step 4: Add the internal initializers the store needs**

In `Sources/ElmersCore/ClipboardItem.swift`, insert this directly above `private mutating func refreshMetadata() {`:

```swift
    /// Rebuilds a stored item exactly, including its identity. Used by HistoryStore.
    init(id: UUID, payload: ClipboardPayload, source: String, sourceBundleID: String?, copiedAt: Date, boardIDs: Set<UUID>,
         title: String?, fingerprint: String, linkPreview: LinkPreview?, recognizedText: String?,
         screenshot: ScreenshotOrigin?, imageDigest: String?) {
        self.id = id; self.payload = payload; self.source = source; self.sourceBundleID = sourceBundleID
        self.copiedAt = copiedAt; self.boardIDs = boardIDs; self.title = title; self.fingerprint = fingerprint
        self.linkPreview = linkPreview; self.recognizedText = recognizedText; self.screenshot = screenshot; self.imageDigest = imageDigest
        refreshMetadata()
    }
```

(Assigning `payload` inside an initializer does not run its `didSet`, so the metadata passed in is kept.)

In the same file, directly below `public init(name: String, colorIndex: Int = 0) { id = UUID(); ... }` in `Pinboard`:

```swift
    init(id: UUID, name: String, colorIndex: Int) { self.id = id; self.name = name; self.colorIndex = colorIndex }
```

In `Sources/ElmersCore/History.swift`, directly below `public init() {}`:

```swift
    init(items: [ClipboardItem], boards: [Pinboard]) { self.items = items; self.boards = boards }
```

- [ ] **Step 5: Create the SQLite wrapper**

Create `Sources/ElmersCore/SQLiteDatabase.swift`:

```swift
import Foundation
import SQLite3

/// A minimal wrapper over the system SQLite library. Not thread-safe: the owner serializes all access.
final class SQLiteDatabase {
    struct Failure: LocalizedError {
        let code: Int32
        let message: String
        var errorDescription: String? { "SQLite error \(code): \(message)" }
    }
    enum Value {
        case int(Int), double(Double), text(String), blob(Data), null
    }

    private let handle: OpaquePointer

    init(url: URL, create: Bool, readOnly: Bool = false) throws {
        var db: OpaquePointer?
        let access = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | (create ? SQLITE_OPEN_CREATE : 0)
        let result = sqlite3_open_v2(url.path, &db, access | SQLITE_OPEN_NOMUTEX, nil)
        guard result == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open \(url.lastPathComponent)"
            sqlite3_close_v2(db)
            throw Failure(code: result, message: message)
        }
        handle = db
        sqlite3_busy_timeout(db, 2_000)
    }
    deinit { sqlite3_close_v2(handle) }

    func execute(_ sql: String) throws {
        let result = sqlite3_exec(handle, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw failure(result) }
    }
    func prepare(_ sql: String) throws -> Statement {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw failure(result) }
        return Statement(handle: statement, database: self)
    }
    /// Runs `body` in one write transaction; any error rolls the whole transaction back.
    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try body(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }
    func integer(_ sql: String) throws -> Int {
        let statement = try prepare(sql)
        return try statement.step() ? statement.int(0) : 0
    }
    func text(_ sql: String) throws -> String? {
        let statement = try prepare(sql)
        return try statement.step() ? statement.text(0) : nil
    }
    fileprivate func failure(_ code: Int32) -> Failure { Failure(code: code, message: String(cString: sqlite3_errmsg(handle))) }

    final class Statement {
        private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        private let handle: OpaquePointer
        private let database: SQLiteDatabase
        fileprivate init(handle: OpaquePointer, database: SQLiteDatabase) { self.handle = handle; self.database = database }
        deinit { sqlite3_finalize(handle) }

        /// Binds `values` to the parameters in order and steps until the statement is done.
        func run(_ values: [Value]) throws {
            try bind(values)
            while try step() {}
        }
        func bind(_ values: [Value]) throws {
            sqlite3_reset(handle)
            sqlite3_clear_bindings(handle)
            for (offset, value) in values.enumerated() {
                let index = Int32(offset + 1)
                let result: Int32
                switch value {
                case .int(let number): result = sqlite3_bind_int64(handle, index, Int64(number))
                case .double(let number): result = sqlite3_bind_double(handle, index, number)
                case .text(let string):
                    result = string.withCString { sqlite3_bind_text(handle, index, $0, Int32(string.utf8.count), Self.transient) }
                case .blob(let data) where data.isEmpty:
                    // A nil pointer would bind NULL; an empty representation must stay an empty blob.
                    result = sqlite3_bind_zeroblob(handle, index, 0)
                case .blob(let data):
                    result = data.withUnsafeBytes { sqlite3_bind_blob(handle, index, $0.baseAddress, Int32(data.count), Self.transient) }
                case .null: result = sqlite3_bind_null(handle, index)
                }
                guard result == SQLITE_OK else { throw database.failure(result) }
            }
        }
        /// Returns true while rows are available and false once the statement is done.
        func step() throws -> Bool {
            switch sqlite3_step(handle) {
            case SQLITE_ROW: return true
            case SQLITE_DONE: return false
            case let result: throw database.failure(result)
            }
        }
        func isNull(_ column: Int32) -> Bool { sqlite3_column_type(handle, column) == SQLITE_NULL }
        func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(handle, column)) }
        func double(_ column: Int32) -> Double { sqlite3_column_double(handle, column) }
        func text(_ column: Int32) -> String? {
            guard !isNull(column), let bytes = sqlite3_column_text(handle, column) else { return nil }
            return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(handle, column))), as: UTF8.self)
        }
        func blob(_ column: Int32) -> Data? {
            guard !isNull(column) else { return nil }
            let count = Int(sqlite3_column_bytes(handle, column))
            guard count > 0, let bytes = sqlite3_column_blob(handle, column) else { return Data() }
            return Data(bytes: bytes, count: count)
        }
    }
}
```

- [ ] **Step 6: Create the store**

Create `Sources/ElmersCore/HistoryStore.swift`:

```swift
import Foundation

/// Keeps History in an SQLite database so a save writes only the rows that changed, instead of rewriting
/// the whole history. Not thread-safe: load on one thread, then send every save through one serial queue.
public final class HistoryStore: @unchecked Sendable {
    public struct SaveStatistics: Equatable, Sendable {
        public var itemsWritten = 0, payloadsWritten = 0, itemsDeleted = 0
        /// Pinboards are few, so any change to them rewrites the whole list.
        public var boardsChanged = false
        public init(itemsWritten: Int = 0, payloadsWritten: Int = 0, itemsDeleted: Int = 0, boardsChanged: Bool = false) {
            self.itemsWritten = itemsWritten; self.payloadsWritten = payloadsWritten
            self.itemsDeleted = itemsDeleted; self.boardsChanged = boardsChanged
        }
    }
    public enum StoreError: LocalizedError, Equatable {
        case unsupportedVersion(Int), damaged(String), migrationMismatch(String), readOnly, notLoaded
        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion: "This history database was created by a newer version of Elmers."
            case .damaged(let detail): "The history database is damaged (\(detail))."
            case .migrationMismatch(let detail): "The old history archive could not be converted (\(detail)). It has been left unchanged."
            case .readOnly: "The history database was opened read-only."
            case .notLoaded: "The history database has not been opened."
            }
        }
    }
    public static let schemaVersion = 1
    public let directory: URL
    public let readOnly: Bool
    public var databaseURL: URL { directory.appendingPathComponent("history.sqlite") }
    public var legacyArchiveURL: URL { directory.appendingPathComponent("history.plist") }
    public var migratedArchiveURL: URL { directory.appendingPathComponent("history.plist.migrated") }
    var stagingURL: URL { directory.appendingPathComponent("history.sqlite.migrating") }
    /// What the most recent save wrote; tests use it to prove saves are incremental.
    public private(set) var lastSave = SaveStatistics()
    private var database: SQLiteDatabase?
    /// What the database holds for each item, apart from payload bytes (which change only with the fingerprint).
    private var savedItems: [UUID: StoredItem] = [:]
    private var savedBoards: [Pinboard] = []

    public init(directory: URL, readOnly: Bool = false) {
        self.directory = directory; self.readOnly = readOnly
    }

    /// Opens the database, creating an empty one when there is none yet. Never modifies a database it cannot read.
    public func load() throws -> History {
        let files = FileManager.default
        if !files.fileExists(atPath: databaseURL.path) {
            guard !readOnly else { throw StoreError.notLoaded }
            try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try build(History())
            try files.moveItem(at: stagingURL, to: databaseURL)
        }
        let database = try Self.open(databaseURL, readOnly: readOnly)
        let history = try Self.read(database)
        self.database = database
        savedItems = Dictionary(history.items.map { ($0.id, StoredItem($0)) }, uniquingKeysWith: { first, _ in first })
        savedBoards = history.boards
        return history
    }

    /// Writes the difference between `history` and what the database already holds, in one transaction.
    /// If the transaction fails nothing is recorded as saved, so the next save retries the same changes.
    public func save(_ history: History) throws {
        guard !readOnly else { throw StoreError.readOnly }
        guard let database else { throw StoreError.notLoaded }
        var statistics = SaveStatistics()
        try database.transaction {
            try Self.write(history, to: database, baseline: savedItems, baselineBoards: savedBoards, statistics: &statistics)
        }
        savedItems = Dictionary(history.items.map { ($0.id, StoredItem($0)) }, uniquingKeysWith: { first, _ in first })
        savedBoards = history.boards
        lastSave = statistics
    }

    // MARK: - Opening and schema

    /// Checks the version and integrity before anything is written, so an unreadable or newer file is left as it was.
    private static func open(_ url: URL, readOnly: Bool, create: Bool = false, journal: String = "WAL") throws -> SQLiteDatabase {
        let database = try SQLiteDatabase(url: url, create: create, readOnly: readOnly)
        let version: Int
        do { version = try database.integer("PRAGMA user_version") } catch { throw StoreError.damaged(error.localizedDescription) }
        guard version <= schemaVersion else { throw StoreError.unsupportedVersion(version) }
        guard (try? database.text("PRAGMA quick_check")) == "ok" else { throw StoreError.damaged("integrity check failed") }
        guard !readOnly else { return database }
        try database.execute("PRAGMA journal_mode = \(journal)")
        try database.execute("PRAGMA foreign_keys = ON")
        if version < schemaVersion {
            try database.transaction {
                for next in (version + 1)...schemaVersion { try database.execute(migrations[next]!) }
                try database.execute("PRAGMA user_version = \(schemaVersion)")
            }
        }
        return database
    }

    /// Schema steps by version. Add a new entry for every change; never edit a released one.
    static let migrations: [Int: String] = [
        1: """
        CREATE TABLE items (
            id TEXT PRIMARY KEY,
            copied_at REAL NOT NULL,
            source TEXT NOT NULL,
            source_bundle_id TEXT,
            title TEXT,
            fingerprint TEXT NOT NULL,
            payload_item_count INTEGER NOT NULL,
            recognized_text TEXT,
            image_digest TEXT,
            link_title TEXT,
            link_image BLOB,
            link_attempted INTEGER,
            screenshot_url TEXT,
            screenshot_identity TEXT,
            screenshot_bookmark BLOB
        );
        CREATE INDEX items_by_time ON items (copied_at DESC);
        CREATE TABLE representations (
            item_id TEXT NOT NULL REFERENCES items (id) ON DELETE CASCADE,
            item_index INTEGER NOT NULL,
            type TEXT NOT NULL,
            data BLOB NOT NULL,
            UNIQUE (item_id, item_index, type)
        );
        CREATE TABLE boards (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            color_index INTEGER NOT NULL,
            position INTEGER NOT NULL
        );
        -- No foreign key to boards: undoing an item deletion can restore a pin to a board deleted since,
        -- and the history keeps such pins as they are.
        CREATE TABLE pins (
            item_id TEXT NOT NULL REFERENCES items (id) ON DELETE CASCADE,
            board_id TEXT NOT NULL,
            PRIMARY KEY (item_id, board_id)
        );
        """
    ]

    // MARK: - Reading

    private static func read(_ database: SQLiteDatabase) throws -> History {
        var payloads: [String: [Int: [String: Data]]] = [:]
        let representations = try database.prepare("SELECT item_id, item_index, type, data FROM representations")
        while try representations.step() {
            guard let item = representations.text(0), let type = representations.text(2) else { throw StoreError.damaged("representation row") }
            payloads[item, default: [:]][representations.int(1), default: [:]][type] = representations.blob(3) ?? Data()
        }
        var pins: [String: Set<UUID>] = [:]
        let pinRows = try database.prepare("SELECT item_id, board_id FROM pins")
        while try pinRows.step() {
            guard let item = pinRows.text(0), let board = pinRows.text(1).flatMap(UUID.init(uuidString:)) else { throw StoreError.damaged("pin row") }
            pins[item, default: []].insert(board)
        }
        var boards: [Pinboard] = []
        let boardRows = try database.prepare("SELECT id, name, color_index FROM boards ORDER BY position")
        while try boardRows.step() {
            guard let id = boardRows.text(0).flatMap(UUID.init(uuidString:)), let name = boardRows.text(1) else { throw StoreError.damaged("pinboard row") }
            boards.append(Pinboard(id: id, name: name, colorIndex: boardRows.int(2)))
        }
        var items: [ClipboardItem] = []
        // Rows are inserted oldest-array-position first, so on equal times the higher rowid is the newer item.
        let rows = try database.prepare("""
            SELECT id, copied_at, source, source_bundle_id, title, fingerprint, payload_item_count, recognized_text, image_digest,
                   link_title, link_image, link_attempted, screenshot_url, screenshot_identity, screenshot_bookmark
            FROM items ORDER BY copied_at DESC, rowid DESC
            """)
        while try rows.step() {
            guard let key = rows.text(0), let id = UUID(uuidString: key), let source = rows.text(2), let fingerprint = rows.text(5) else {
                throw StoreError.damaged("item row")
            }
            let stored = payloads[key] ?? [:]
            let payload = ClipboardPayload(items: (0..<rows.int(6)).map { stored[$0] ?? [:] })
            let preview = rows.isNull(11) ? nil : LinkPreview(title: rows.text(9), image: rows.blob(10), attempted: rows.int(11) != 0)
            let screenshot = rows.text(12).flatMap(URL.init(string:)).map {
                ScreenshotOrigin(originalURL: $0, fileIdentity: rows.text(13) ?? "", bookmark: rows.blob(14))
            }
            items.append(ClipboardItem(id: id, payload: payload, source: source, sourceBundleID: rows.text(3),
                                       copiedAt: Date(timeIntervalSinceReferenceDate: rows.double(1)), boardIDs: pins[key] ?? [],
                                       title: rows.text(4), fingerprint: fingerprint, linkPreview: preview,
                                       recognizedText: rows.text(7), screenshot: screenshot, imageDigest: rows.text(8)))
        }
        return History(items: items, boards: boards)
    }

    // MARK: - Writing

    private static func write(_ history: History, to database: SQLiteDatabase, baseline: [UUID: StoredItem],
                              baselineBoards: [Pinboard], statistics: inout SaveStatistics) throws {
        if history.boards != baselineBoards {
            try database.execute("DELETE FROM boards")
            let insert = try database.prepare("INSERT INTO boards (id, name, color_index, position) VALUES (?, ?, ?, ?)")
            for (position, board) in history.boards.enumerated() {
                try insert.run([.text(board.id.uuidString), .text(board.name), .int(board.colorIndex), .int(position)])
            }
            statistics.boardsChanged = true
        }
        let present = Set(history.items.map(\.id))
        let delete = try database.prepare("DELETE FROM items WHERE id = ?")
        for id in baseline.keys where !present.contains(id) {
            try delete.run([.text(id.uuidString)])
            statistics.itemsDeleted += 1
        }
        let upsert = try database.prepare("""
            INSERT INTO items (id, copied_at, source, source_bundle_id, title, fingerprint, payload_item_count, recognized_text,
                               image_digest, link_title, link_image, link_attempted, screenshot_url, screenshot_identity, screenshot_bookmark)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET
                copied_at = excluded.copied_at, source = excluded.source, source_bundle_id = excluded.source_bundle_id,
                title = excluded.title, fingerprint = excluded.fingerprint, payload_item_count = excluded.payload_item_count,
                recognized_text = excluded.recognized_text, image_digest = excluded.image_digest, link_title = excluded.link_title,
                link_image = excluded.link_image, link_attempted = excluded.link_attempted, screenshot_url = excluded.screenshot_url,
                screenshot_identity = excluded.screenshot_identity, screenshot_bookmark = excluded.screenshot_bookmark
            """)
        let clearPins = try database.prepare("DELETE FROM pins WHERE item_id = ?")
        let insertPin = try database.prepare("INSERT INTO pins (item_id, board_id) VALUES (?, ?)")
        let clearRepresentations = try database.prepare("DELETE FROM representations WHERE item_id = ?")
        let insertRepresentation = try database.prepare("INSERT INTO representations (item_id, item_index, type, data) VALUES (?, ?, ?, ?)")
        // Oldest array position first, so newer items get higher rowids (the tie-break when times are equal).
        for item in history.items.reversed() {
            let previous = baseline[item.id]
            guard StoredItem(item) != previous else { continue }
            let key = SQLiteDatabase.Value.text(item.id.uuidString)
            func optional(_ text: String?) -> SQLiteDatabase.Value { text.map { .text($0) } ?? .null }
            func optional(_ data: Data?) -> SQLiteDatabase.Value { data.map { .blob($0) } ?? .null }
            try upsert.run([
                key, .double(item.copiedAt.timeIntervalSinceReferenceDate), .text(item.source), optional(item.sourceBundleID),
                optional(item.title), .text(item.fingerprint), .int(item.payload.items.count), optional(item.recognizedText),
                optional(item.imageDigest), optional(item.linkPreview?.title), optional(item.linkPreview?.image),
                item.linkPreview.map { .int($0.attempted ? 1 : 0) } ?? .null,
                optional(item.screenshot?.originalURL.absoluteString), optional(item.screenshot?.fileIdentity),
                optional(item.screenshot?.bookmark),
            ])
            statistics.itemsWritten += 1
            if previous?.boardIDs != item.boardIDs {
                try clearPins.run([key])
                for board in item.boardIDs { try insertPin.run([key, .text(board.uuidString)]) }
            }
            if previous?.fingerprint != item.fingerprint {
                try clearRepresentations.run([key])
                for (index, representations) in item.payload.items.enumerated() {
                    for (type, data) in representations { try insertRepresentation.run([key, .int(index), .text(type), .blob(data)]) }
                }
                statistics.payloadsWritten += 1
            }
        }
    }

    // MARK: - Staging

    /// Writes `history` into a fresh staging database that is only moved into place once complete.
    private func build(_ history: History) throws {
        let files = FileManager.default
        for suffix in ["", "-journal", "-wal", "-shm"] { try? files.removeItem(atPath: stagingURL.path + suffix) }
        do {
            // A rollback journal keeps the finished staging database in one file, ready to be moved.
            let database = try Self.open(stagingURL, readOnly: false, create: true, journal: "DELETE")
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stagingURL.path)
            var statistics = SaveStatistics()
            try database.transaction {
                try Self.write(history, to: database, baseline: [:], baselineBoards: [], statistics: &statistics)
            }
        }
    }
}

/// Everything the database stores for an item except the payload bytes.
private struct StoredItem: Equatable {
    let fingerprint: String, source: String, sourceBundleID: String?, copiedAt: Date, boardIDs: Set<UUID>, title: String?
    let linkPreview: LinkPreview?, recognizedText: String?, screenshot: ScreenshotOrigin?, imageDigest: String?
    init(_ item: ClipboardItem) {
        fingerprint = item.fingerprint; source = item.source; sourceBundleID = item.sourceBundleID; copiedAt = item.copiedAt
        boardIDs = item.boardIDs; title = item.title; linkPreview = item.linkPreview; recognizedText = item.recognizedText
        screenshot = item.screenshot; imageDigest = item.imageDigest
    }
}
```

- [ ] **Step 7: Run the tests and confirm they pass**

Run: `scripts/test.sh`
Expected: every line is `PASS`, ending with `30 checks, 0 failures`.

If linking fails with undefined `_sqlite3_*` symbols, add `linkerSettings: [.linkedLibrary("sqlite3")]` to the `ElmersCore` target in `Package.swift` and run the tests again. The standalone prototype autolinked without it.

- [ ] **Step 8: Commit**

```bash
git add Sources/ElmersCore/SQLiteDatabase.swift Sources/ElmersCore/HistoryStore.swift Sources/ElmersCore/ClipboardItem.swift \
        Sources/ElmersCore/History.swift Tests/ElmersCoreTests/HistoryStoreTests.swift Tests/ElmersCoreTests/main.swift
git commit -m "Add an SQLite history store that saves only what changed

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Convert the plist archive once, verified, and keep it

**Files:**
- Modify: `Sources/ElmersCore/HistoryStore.swift` (the class doc comment, `load()`, and two new methods)
- Test: `Tests/ElmersCoreTests/HistoryStoreTests.swift`, `Tests/ElmersCoreTests/main.swift`

**Interfaces:**
- Consumes: `Archive(url:).load()` (existing), `HistoryStore.build(_:)`, `open(_:readOnly:)` and `read(_:)` from Task 1.
- Produces: `load()` now converts `legacyArchiveURL` when no database exists, and retires the plist to `migratedArchiveURL` after every successful non-read-only open. Adds `private static func verify(_:matches:)` and `private func retireLegacyArchive()`.

- [ ] **Step 1: Write the failing tests**

Add these methods at the end of `HistoryStoreTests`, before its closing brace:

```swift
    // MARK: Converting the plist archive

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

        // The next launch reads the database and leaves the kept archive alone.
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
```

Add to the `checks` array in `Tests/ElmersCoreTests/main.swift`, after the Task 1 store entries:

```swift
    ("plist archive converts once and is kept", store.testLegacyArchiveIsConvertedOnceAndKept),
    ("unreadable plist archive is not converted", store.testUnreadableLegacyArchiveIsNotConverted),
    ("interrupted conversion starts over", store.testInterruptedConversionStartsOver),
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `scripts/test.sh`
Expected: `FAIL` lines for all three new checks. The converted history is empty, and the unreadable archive produces no error. The summary line reads `33 checks, N failures` with N greater than 0; the harness counts failed assertions, not failed checks.

- [ ] **Step 3: Convert in `load()`**

In `Sources/ElmersCore/HistoryStore.swift`, replace the whole `load()` method, including its doc comment, with:

```swift
    /// Opens the database, creating it or converting the legacy archive when there is none yet.
    /// Never modifies a database it cannot read or a legacy archive it cannot convert.
    public func load() throws -> History {
        let files = FileManager.default
        if !files.fileExists(atPath: databaseURL.path) {
            guard !readOnly else { throw StoreError.notLoaded }
            try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let legacy = files.fileExists(atPath: legacyArchiveURL.path) ? try Archive(url: legacyArchiveURL).load() : nil
            try build(legacy ?? History())
            if let legacy {
                let converted = try Self.read(Self.open(stagingURL, readOnly: true))
                try Self.verify(converted, matches: legacy)
            }
            try files.moveItem(at: stagingURL, to: databaseURL)
        }
        let database = try Self.open(databaseURL, readOnly: readOnly)
        let history = try Self.read(database)
        self.database = database
        savedItems = Dictionary(history.items.map { ($0.id, StoredItem($0)) }, uniquingKeysWith: { first, _ in first })
        savedBoards = history.boards
        if !readOnly { retireLegacyArchive() }
        return history
    }
```

- [ ] **Step 4: Add verification and retirement**

Add these methods at the end of the `HistoryStore` class, after `build(_:)` and before the class's closing brace:

```swift

    private static func verify(_ converted: History, matches legacy: History) throws {
        guard converted.boards == legacy.boards else { throw StoreError.migrationMismatch("pinboards differ") }
        let byID = Dictionary(converted.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard converted.items.count == legacy.items.count else { throw StoreError.migrationMismatch("item counts differ") }
        guard legacy.items.allSatisfy({ byID[$0.id] == $0 }) else { throw StoreError.migrationMismatch("items differ") }
    }

    /// Keeps the converted archive under a new name rather than deleting it. An existing `.migrated`
    /// file is never overwritten.
    private func retireLegacyArchive() {
        let files = FileManager.default
        guard files.fileExists(atPath: legacyArchiveURL.path), !files.fileExists(atPath: migratedArchiveURL.path) else { return }
        try? files.moveItem(at: legacyArchiveURL, to: migratedArchiveURL)
    }
```

Replace the class doc comment with:

```swift
/// Keeps History in an SQLite database so a save writes only the rows that changed, instead of rewriting
/// the whole history. On first use it converts the version 1 `history.plist` archive and keeps the original
/// as `history.plist.migrated`. Not thread-safe: load on one thread, then send every save through one
/// serial queue.
```

Also rename the `// MARK: - Staging` line to `// MARK: - Legacy archive`.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `scripts/test.sh`
Expected: `33 checks, 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Sources/ElmersCore/HistoryStore.swift Tests/ElmersCoreTests/HistoryStoreTests.swift Tests/ElmersCoreTests/main.swift
git commit -m "Convert the plist history into SQLite once, verified, keeping the original

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Switch the app to the store, with report and benchmark tools

**Files:**
- Create: `Tests/ElmersCoreTests/StorageTools.swift`
- Modify: `Tests/ElmersCoreTests/main.swift` (tool flags, next to `--live-capture`)
- Modify: `Tests/ElmersCoreTests/LiveCaptureCheck.swift:16-21`
- Modify: `Sources/Elmers/AppModel.swift:79`, `:150-154` and `:462-469` (`archive`, init loading, `persist()`)

**Interfaces:**
- Consumes: `HistoryStore(directory:readOnly:)`, `load()`, `save(_:)`, `databaseURL`, `legacyArchiveURL` and `migratedArchiveURL` from Tasks 1 and 2.
- Produces: `ElmersCoreChecks --storage-report` and `ElmersCoreChecks --storage-benchmark`, which Task 4 relies on.

- [ ] **Step 1: Add the tools**

Create `Tests/ElmersCoreTests/StorageTools.swift`:

```swift
import CryptoKit
import Foundation
import ElmersCore

/// Summarizes the real history files before and after conversion. Prints counts and a digest of
/// identities, times, titles and pins only, never clipboard content.
func reportStorage() {
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Elmers")
    let store = HistoryStore(directory: directory, readOnly: true)
    for url in [store.legacyArchiveURL, store.migratedArchiveURL] where FileManager.default.fileExists(atPath: url.path) {
        do { print("\(url.lastPathComponent): \(summary(try Archive(url: url).load()))") }
        catch { print("\(url.lastPathComponent): unreadable (\(error.localizedDescription))") }
    }
    guard FileManager.default.fileExists(atPath: store.databaseURL.path) else { print("history.sqlite: none"); return }
    do { print("\(store.databaseURL.lastPathComponent): \(summary(try store.load()))") }
    catch { print("\(store.databaseURL.lastPathComponent): unreadable (\(error.localizedDescription))") }
}

private func summary(_ history: History) -> String {
    var hash = SHA256()
    for item in history.items.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
        let pins = item.boardIDs.map(\.uuidString).sorted().joined(separator: ",")
        hash.update(data: Data("\(item.id)|\(item.fingerprint)|\(item.copiedAt.timeIntervalSinceReferenceDate)|\(item.title ?? "")|\(pins)".utf8))
    }
    for board in history.boards { hash.update(data: Data("\(board.id)|\(board.name)|\(board.colorIndex)".utf8)) }
    let digest = hash.finalize().prefix(6).map { String(format: "%02x", $0) }.joined()
    let bytes = Int64(history.items.reduce(0) { $0 + $1.byteCount })
    return "\(history.items.count) items, \(history.boards.count) pinboards, \(history.items.filter { !$0.boardIDs.isEmpty }.count) pinned, "
        + "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)), identity \(digest)"
}

/// Times the plist archive against the SQLite store on a synthetic history shaped like a heavy real one:
/// 2,000 items, one in ten a 250 KB image.
func benchmarkStorage() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("elmers-benchmark-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    func random(_ count: Int) -> Data {
        var data = Data(count: count)
        data.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, $0.count) }
        return data
    }
    var history = History()
    for index in 0..<2_000 {
        let date = Date(timeIntervalSinceReferenceDate: Double(index))
        if index % 10 == 0 { history.capture(.init(items: [["public.png": random(250_000)]]), source: "Preview", at: date) }
        else { history.capture(.text(String(repeating: "benchmark \(index) ", count: 50)), source: "Notes", at: date) }
    }
    func measure(_ label: String, _ body: () throws -> Void) rethrows {
        let start = CFAbsoluteTimeGetCurrent()
        try body()
        print(label.padding(toLength: 38, withPad: " ", startingAt: 0) + String(format: "%8.1f ms", (CFAbsoluteTimeGetCurrent() - start) * 1_000))
    }
    let archive = Archive(url: directory.appendingPathComponent("history.plist"))
    try measure("plist: save whole history") { try archive.save(history) }
    try measure("plist: load") { _ = try archive.load() }
    let store = HistoryStore(directory: directory)
    try measure("sqlite: convert plist on first load") { _ = try store.load() }
    history.renameItem(history.items[500].id, title: "Renamed")
    try measure("sqlite: save a rename") { try store.save(history) }
    history.capture(.init(items: [["public.png": random(5_000_000)]]), source: "Preview")
    try measure("sqlite: save a new 5 MB image") { try store.save(history) }
    history.delete(history.items[10].id)
    try measure("sqlite: save a deletion") { try store.save(history) }
    try measure("sqlite: load") { _ = try HistoryStore(directory: directory).load() }
}
```

In `Tests/ElmersCoreTests/main.swift`, directly after the `--live-capture` block:

```swift
if CommandLine.arguments.contains("--storage-report") { reportStorage(); exit(0) }
if CommandLine.arguments.contains("--storage-benchmark") {
    do { try benchmarkStorage() } catch { print("FAIL storage benchmark: \(error)"); exit(1) }
    exit(0)
}
```

- [ ] **Step 2: Run the benchmark and record the numbers**

Run: `scripts/swift.sh build -c release --product ElmersCoreChecks && .build/release/ElmersCoreChecks --storage-benchmark`
Expected (the prototype on this Mac): plist whole save about 150–180 ms; SQLite save of a rename about 12–17 ms, of a new 5 MB image about 33–37 ms, of a deletion about 8 ms; SQLite load about 35–55 ms; first-load conversion about 270 ms. Copy the actual output into Task 4's docs step. Treat any SQLite single-change save above 50 ms as a regression to investigate before continuing.

- [ ] **Step 3: Point the live capture check at the database**

In `Tests/ElmersCoreTests/LiveCaptureCheck.swift`, replace:

```swift
    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Elmers/history.plist")
```

with:

```swift
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Elmers")
```

and replace `if let history = try? Archive(url: url).load(),` with `if let history = try? HistoryStore(directory: directory, readOnly: true).load(),`.

- [ ] **Step 4: Switch `AppModel` to the store**

In `Sources/Elmers/AppModel.swift`:

Replace `    private let archive: Archive` with:

```swift
    private let store: HistoryStore
```

Replace:

```swift
        archive = Archive(url: directory.appendingPathComponent("history.plist"))
        if !demo {
            do { history = try archive.load(); prune() }
```

with:

```swift
        store = HistoryStore(directory: directory)
        if !demo {
            do { history = try store.load(); prune() }
```

(Leave the `catch` line unchanged. "The original archive is preserved" is still true: the store never modifies a file it cannot read.)

In `persist()`, replace:

```swift
        let snapshot = history, archive = archive
        saveQueue.async { [weak self] in
            do { try archive.save(snapshot) }
```

with:

```swift
        let snapshot = history, store = store
        saveQueue.async { [weak self] in
            do { try store.save(snapshot) }
```

`load()` runs on the main thread in `init` before any save is queued. Every `save` runs on the serial `saveQueue`, and `flush()` already drains that queue at termination. This matches the store's threading contract.

- [ ] **Step 5: Confirm nothing writes the plist any more**

Run: `grep -rn "Archive(" Sources Tests`
Expected: only `Sources/ElmersCore/HistoryStore.swift` (conversion), `Tests/ElmersCoreTests/HistoryTests.swift`, `ScreenshotTests.swift`, `HistoryStoreTests.swift` and `StorageTools.swift`. Nothing in `Sources/Elmers`.

- [ ] **Step 6: Run every automated check**

```bash
scripts/test.sh
scripts/swift.sh build --product Elmers
.build/debug/Elmers --demo --check-interaction
.build/debug/Elmers --demo --check-screenshots
.build/debug/Elmers --demo --check-status-item
.build/debug/Elmers --demo --check-sounds
.build/debug/Elmers --demo --check-scroll-performance
scripts/build-app.sh
```

Expected: `33 checks, 0 failures`, every check prints `PASS`, and the build ends with `Built .../dist/Elmers.app`. Demo mode never touches the store, so these checks show the app still behaves. They do not prove storage on real data; that is Task 4.

- [ ] **Step 7: Commit**

```bash
git add Sources/Elmers/AppModel.swift Tests/ElmersCoreTests/StorageTools.swift Tests/ElmersCoreTests/main.swift \
        Tests/ElmersCoreTests/LiveCaptureCheck.swift
git commit -m "Save history through the SQLite store; add storage report and benchmark

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Convert the real history and record the evidence

This task touches the user's real clipboard history, so **ask the user before Step 2** and explain the steps. Every step keeps the original: a backup copy, then `history.plist.migrated`.

**Files:**
- Modify: `docs/paste-parity.md` (new section), `docs/HANDOFF.md` (checkpoint)

- [ ] **Step 1: Get the user's go-ahead**

Tell the user that Elmers will be quit, `history.plist` will be copied to `history.plist.pre-sqlite` in the same private folder, and the new build will convert the history. Wait for a yes.

- [ ] **Step 2: Quit Elmers and back up**

```bash
osascript -e 'quit app "Elmers"'; sleep 2; pgrep -x Elmers && echo "still running" || echo "stopped"
cp -p "$HOME/Library/Application Support/Elmers/history.plist" "$HOME/Library/Application Support/Elmers/history.plist.pre-sqlite"
```

Expected: `stopped`. The backup keeps mode 0600. Do not copy it anywhere else.

- [ ] **Step 3: Record the report before conversion**

Run: `.build/debug/ElmersCoreChecks --storage-report`
Expected: a `history.plist: N items, B pinboards, P pinned, SIZE, identity XXXXXXXXXXXX` line (the backup is not listed) and `history.sqlite: none`. Save the line.

- [ ] **Step 4: Launch the new build and record the report after conversion**

```bash
open dist/Elmers.app; sleep 5
.build/debug/ElmersCoreChecks --storage-report
ls -l "$HOME/Library/Application Support/Elmers"
```

Expected: no `history.plist` line. `history.plist.migrated` and `history.sqlite` show the same N, B, P and identity digest as Step 3. `history.sqlite*` files are `-rw-------`. If the counts or digest differ, stop, quit Elmers, and roll back (Step 7) before investigating.

- [ ] **Step 5: Exercise real persistence**

Run: `.build/debug/ElmersCoreChecks --live-capture`
Expected: `PASS running app captured and persisted synthetic clipboard text`. The check restores the previous clipboard afterwards.

Then, with the user: copy a harmless text, pin it to a pinboard, rename it, delete another harmless test item, quit Elmers from its menu, and relaunch. All four changes must survive. Note whether launch feels slower than before (conversion happens only on the first launch).

- [ ] **Step 6: Document**

Append a "September 21 — SQLite storage" section to `docs/paste-parity.md`. Record: what changed; the Step 2 benchmark output from Task 3; the before and after report lines (counts and digest only, never content); permissions; the live-capture result; the manual persistence check; and what is not done (stage 2: lazy payloads, FTS5, raising the 2,000-item limit). Add a short checkpoint to `docs/HANDOFF.md` with the rollback procedure from Step 7. Then commit:

```bash
git add docs/paste-parity.md docs/HANDOFF.md
git commit -m "docs: record the SQLite storage conversion

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 7: Rollback procedure (only if needed; document it either way)**

```bash
osascript -e 'quit app "Elmers"'; sleep 2
cd "$HOME/Library/Application Support/Elmers"
rm -f history.sqlite history.sqlite-wal history.sqlite-shm
mv history.plist.migrated history.plist
# then run a build from main before this branch
```

- [ ] **Step 8: Finish the branch**

Use superpowers:finishing-a-development-branch. Leave `history.plist.pre-sqlite` in place until the user says to remove it.
