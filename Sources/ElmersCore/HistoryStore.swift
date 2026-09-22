import Foundation

/// Keeps History in SQLite so each save writes only changed rows.
public final class HistoryStore: @unchecked Sendable {
    public struct SaveStatistics: Equatable, Sendable {
        public var itemsWritten = 0, payloadsWritten = 0, itemsDeleted = 0
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
    public private(set) var lastSave = SaveStatistics()
    private var database: SQLiteDatabase?
    private var savedItems: [UUID: StoredItem] = [:]
    private var savedBoards: [Pinboard] = []

    public init(directory: URL, readOnly: Bool = false) { self.directory = directory; self.readOnly = readOnly }

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

    static let migrations: [Int: String] = [
        1: """
        CREATE TABLE items (
            id TEXT PRIMARY KEY, copied_at REAL NOT NULL, source TEXT NOT NULL, source_bundle_id TEXT,
            title TEXT, fingerprint TEXT NOT NULL, payload_item_count INTEGER NOT NULL, recognized_text TEXT,
            image_digest TEXT, link_title TEXT, link_image BLOB, link_attempted INTEGER,
            screenshot_url TEXT, screenshot_identity TEXT, screenshot_bookmark BLOB
        );
        CREATE INDEX items_by_time ON items (copied_at DESC);
        CREATE TABLE representations (
            item_id TEXT NOT NULL REFERENCES items (id) ON DELETE CASCADE, item_index INTEGER NOT NULL,
            type TEXT NOT NULL, data BLOB NOT NULL, UNIQUE (item_id, item_index, type)
        );
        CREATE TABLE boards (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, color_index INTEGER NOT NULL, position INTEGER NOT NULL
        );
        CREATE TABLE pins (
            item_id TEXT NOT NULL REFERENCES items (id) ON DELETE CASCADE, board_id TEXT NOT NULL,
            PRIMARY KEY (item_id, board_id)
        );
        """
    ]

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
            try delete.run([.text(id.uuidString)]); statistics.itemsDeleted += 1
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
                optional(item.screenshot?.originalURL.absoluteString), optional(item.screenshot?.fileIdentity), optional(item.screenshot?.bookmark)
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

    private func build(_ history: History) throws {
        let files = FileManager.default
        for suffix in ["", "-journal", "-wal", "-shm"] { try? files.removeItem(atPath: stagingURL.path + suffix) }
        let database = try Self.open(stagingURL, readOnly: false, create: true, journal: "DELETE")
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stagingURL.path)
        var statistics = SaveStatistics()
        try database.transaction {
            try Self.write(history, to: database, baseline: [:], baselineBoards: [], statistics: &statistics)
        }
    }
}

private struct StoredItem: Equatable {
    let fingerprint: String, source: String, sourceBundleID: String?, copiedAt: Date, boardIDs: Set<UUID>, title: String?
    let linkPreview: LinkPreview?, recognizedText: String?, screenshot: ScreenshotOrigin?, imageDigest: String?
    init(_ item: ClipboardItem) {
        fingerprint = item.fingerprint; source = item.source; sourceBundleID = item.sourceBundleID; copiedAt = item.copiedAt
        boardIDs = item.boardIDs; title = item.title; linkPreview = item.linkPreview; recognizedText = item.recognizedText
        screenshot = item.screenshot; imageDigest = item.imageDigest
    }
}
