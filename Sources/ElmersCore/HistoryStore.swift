import Foundation

/// Keeps History in an SQLite database so a save writes only the rows that changed, instead of rewriting
/// the whole history. On first use it converts the version 1 `history.plist` archive and keeps the original
/// as `history.plist.migrated`. Not thread-safe: load on one thread, then send every save through one
/// serial queue.
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
            case .unsupportedVersion: String(localized: "This history database was created by a newer version of Elmers.")
            case .damaged(let detail): String(localized: "The history database is damaged (\(detail)).")
            case .migrationMismatch(let detail): String(localized: "The old history archive could not be converted (\(detail)). It has been left unchanged.")
            case .readOnly: String(localized: "The history database was opened read-only.")
            case .notLoaded: String(localized: "The history database has not been opened.")
            }
        }
    }
    public static let schemaVersion = 1
    /// Representations up to this size are read with the item; larger ones stay in the database until used, so a
    /// long history of images does not have to fit in memory. Text types are always read, whatever their size,
    /// because titles, search and the item's type come from them.
    public static let inlineLimit = 64 * 1024
    static let textTypes = ["public.utf8-plain-text", "public.url", "public.file-url", "public.rtf"]
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
    /// `PRAGMA data_version` as of the last commit on this connection. It changes only when another
    /// connection commits, which is the signal that the baseline above no longer describes the database.
    private var dataVersion: Int?

    public init(directory: URL, readOnly: Bool = false) { self.directory = directory; self.readOnly = readOnly }

    /// Opens the database, creating it or converting the legacy archive when there is none yet. If an
    /// older build recreates the plist after conversion, its history is conservatively merged back into
    /// SQLite after both stores are backed up. Never modifies a database it cannot read or a legacy archive
    /// it cannot convert.
    public func load() throws -> History {
        let files = FileManager.default
        if !readOnly, files.fileExists(atPath: databaseURL.path), files.fileExists(atPath: legacyArchiveURL.path) {
            try recoverReappearedArchive()
        }
        if !files.fileExists(atPath: databaseURL.path) {
            guard !readOnly else { throw StoreError.notLoaded }
            try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let legacy = files.fileExists(atPath: legacyArchiveURL.path) ? Self.canonical(try Archive(url: legacyArchiveURL).load()) : nil
            try build(legacy ?? History())
            if let legacy {
                let converted = try Self.read(Self.open(stagingURL, readOnly: true))
                try Self.verify(converted, matches: legacy)
            }
            try files.moveItem(at: stagingURL, to: databaseURL)
        }
        let database = try Self.open(databaseURL, readOnly: readOnly)
        if !readOnly {
            Self.scrub(database)
            excludeFromBackups()
        }
        let history = try Self.read(database)
        self.database = database
        savedItems = Self.baseline(history.items)
        savedBoards = history.boards
        dataVersion = try? database.integer("PRAGMA data_version")
        if !readOnly { try retireLegacyArchive() }
        return history
    }

    /// Keeps clipboard history, and every backup kept beside it, out of Time Machine so deleted items do not
    /// live on in old backups. The flag is stored on the folder itself, so the next launch finds it already set.
    private func excludeFromBackups() {
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var folder = directory
        try? folder.setResourceValues(values)
    }

    public func save(_ history: History) throws {
        guard !readOnly else { throw StoreError.readOnly }
        guard let database else { throw StoreError.notLoaded }
        var statistics = SaveStatistics()
        var replacedContent = false
        try database.transaction {
            var baseline = savedItems
            // Rows this process last wrote are the only ones it may delete, even after a rebuild below.
            var deleting = Set(savedItems.keys)
            // Another writer may have changed or removed rows since the last commit here. Diffing against
            // the stale baseline would then update an item's metadata without rewriting the representations
            // that went with it, so rebuild the baseline from the database inside the transaction instead.
            if try database.integer("PRAGMA data_version") != dataVersion {
                baseline = Self.baseline(try Self.read(database).items)
                deleting.formIntersection(baseline.keys)
            }
            // Pinboards are rewritten as a set, so merge this process's pinboard edits into whatever the
            // database holds now; otherwise saving them would undo another writer's pinboard changes.
            var target = history
            var storedBoards = history.boards
            if history.boards != savedBoards {
                storedBoards = try Self.readBoards(database)
                target = History(items: history.items,
                                 boards: Self.mergeBoards(local: history.boards, base: savedBoards, stored: storedBoards))
            }
            try Self.write(target, to: database, baseline: baseline, deleting: deleting,
                           baselineBoards: storedBoards, statistics: &statistics, replacedContent: &replacedContent)
        }
        if replacedContent { Self.scrub(database) }
        savedItems = Self.baseline(history.items)
        savedBoards = history.boards
        dataVersion = try? database.integer("PRAGMA data_version")
        lastSave = statistics
    }

    /// After a save removed or replaced content: return the (already zeroed) free pages to the file system and
    /// empty the WAL, whose older frames still hold the rows as they were before. Best effort; a busy reader
    /// in another process only postpones this to the next such save.
    private static func scrub(_ database: SQLiteDatabase) {
        try? database.execute("PRAGMA incremental_vacuum")
        try? database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    private static func readBoards(_ database: SQLiteDatabase) throws -> [Pinboard] {
        var boards: [Pinboard] = []
        let boardRows = try database.prepare("SELECT id, name, color_index FROM boards ORDER BY position")
        while try boardRows.step() {
            guard let id = boardRows.text(0).flatMap(UUID.init(uuidString:)), let name = boardRows.text(1) else { throw StoreError.damaged("pinboard row") }
            boards.append(Pinboard(id: id, name: name, colorIndex: boardRows.int(2)))
        }
        return boards
    }

    /// Three-way merge of pinboards: `local` is this process's list, `base` what it last saved, and
    /// `stored` what the database holds now. Boards this process added, changed or deleted follow
    /// `local`; every other board follows `stored`, so another writer's additions, edits and deletions
    /// survive. The order follows `local` when this process reordered its boards and `stored` otherwise,
    /// with boards only one side knows kept at their position on that side. An edit here to a board another
    /// writer deleted brings the board back, as an edited item does.
    static func mergeBoards(local: [Pinboard], base: [Pinboard], stored: [Pinboard]) -> [Pinboard] {
        let baseByID = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let storedByID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let localIDs = Set(local.map(\.id))
        // Boards unchanged here take the stored version, or disappear if another writer deleted them.
        let fromLocal: [Pinboard] = local.compactMap { board in
            guard let original = baseByID[board.id], original == board else { return board }
            return storedByID[board.id]
        }
        let keptBase = base.map(\.id).filter(localIDs.contains)
        let reordered = local.map(\.id).filter { baseByID[$0] != nil } != keptBase
        let addedElsewhere = stored.filter { baseByID[$0.id] == nil && !localIDs.contains($0.id) }
        if reordered {
            var merged = fromLocal
            for board in addedElsewhere {
                merged.insert(board, at: min(stored.firstIndex(of: board) ?? merged.count, merged.count))
            }
            return merged
        }
        let fromLocalByID = Dictionary(fromLocal.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var merged: [Pinboard] = stored.compactMap { board in
            if baseByID[board.id] == nil { return localIDs.contains(board.id) ? nil : board }
            return fromLocalByID[board.id]
        }
        // Boards added here, and boards edited here that another writer deleted, go back at their local position.
        for (index, board) in local.enumerated() where storedByID[board.id] == nil {
            guard let kept = fromLocalByID[board.id] else { continue }
            merged.insert(kept, at: min(index, merged.count))
        }
        return merged
    }

    private static func baseline(_ items: [ClipboardItem]) -> [UUID: StoredItem] {
        Dictionary(items.map { ($0.id, StoredItem($0)) }, uniquingKeysWith: { first, _ in first })
    }

    private static func open(_ url: URL, readOnly: Bool, create: Bool = false, journal: String = "WAL") throws -> SQLiteDatabase {
        let database = try SQLiteDatabase(url: url, create: create, readOnly: readOnly)
        let version: Int
        do { version = try database.integer("PRAGMA user_version") } catch { throw StoreError.damaged(error.localizedDescription) }
        guard version <= schemaVersion else { throw StoreError.unsupportedVersion(version) }
        guard (try? database.text("PRAGMA quick_check")) == "ok" else { throw StoreError.damaged("integrity check failed") }
        guard !readOnly else { return database }
        // Clipboard history is private: zero the bytes of every deleted row, freed page and overwritten value
        // instead of leaving them readable in the file, and keep SQLite's temporary files (VACUUM's copy of the
        // database included) in memory rather than in the temporary directory.
        try database.execute("PRAGMA secure_delete = ON")
        try database.execute("PRAGMA temp_store = MEMORY")
        // Incremental auto-vacuum lets saves give freed pages back so the file shrinks. Earlier builds created
        // databases without it and with fast secure delete, which left deleted content in whole free pages;
        // switching modes needs one VACUUM, and that rewrite also drops those pages. VACUUM fails while another
        // process has the database open; history still loads, and the rewrite is tried again on the next open.
        if try database.integer("PRAGMA auto_vacuum") != 2 {
            try database.execute("PRAGMA auto_vacuum = INCREMENTAL")
            try? database.execute("VACUUM")
        }
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

    /// Schema steps by version. Public so storage checks can build a database as an earlier build left it.
    public static let migrations: [Int: String] = [
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
        if database.isInTransaction { return try readSnapshot(database) }
        return try database.readTransaction { try readSnapshot(database) }
    }

    private static func readSnapshot(_ database: SQLiteDatabase) throws -> History {
        var payloads: [String: [Int: [String: Data]]] = [:]
        var sizes: [String: [DeferredRepresentations.Key: Int]] = [:]
        let inline = textTypes.map { "'\($0)'" }.joined(separator: ", ")
        let representations = try database.prepare("""
            SELECT item_id, item_index, type, length(data),
                   CASE WHEN length(data) <= \(inlineLimit) OR type IN (\(inline)) THEN data END
            FROM representations
            """)
        while try representations.step() {
            guard let item = representations.text(0), let type = representations.text(2) else { throw StoreError.damaged("representation row") }
            let index = representations.int(1)
            if representations.isNull(4), representations.int(3) > 0 {
                sizes[item, default: [:]][.init(index: index, type: type)] = representations.int(3)
                payloads[item, default: [:]][index, default: [:]] = payloads[item]?[index] ?? [:]
            } else {
                payloads[item, default: [:]][index, default: [:]][type] = representations.blob(4) ?? Data()
            }
        }
        let reader = RepresentationReader(url: database.url)
        var pins: [String: Set<UUID>] = [:]
        let pinRows = try database.prepare("SELECT item_id, board_id FROM pins")
        while try pinRows.step() {
            guard let item = pinRows.text(0), let board = pinRows.text(1).flatMap(UUID.init(uuidString:)) else { throw StoreError.damaged("pin row") }
            pins[item, default: []].insert(board)
        }
        let boards = try readBoards(database)
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
            let deferred = sizes[key].map { DeferredRepresentations(itemID: id, fingerprint: fingerprint, sizes: $0, reader: reader) }
            let payload = ClipboardPayload(loaded: (0..<rows.int(6)).map { stored[$0] ?? [:] }, deferred: deferred)
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

    /// `baseline` says what each row currently holds, `deleting` which rows this writer owns and may
    /// remove when they are no longer in `history`. Rows another writer added are in neither set.
    private static func write(_ history: History, to database: SQLiteDatabase, baseline: [UUID: StoredItem],
                              deleting: Set<UUID>, baselineBoards: [Pinboard], statistics: inout SaveStatistics,
                              replacedContent: inout Bool) throws {
        if history.boards != baselineBoards {
            replacedContent = replacedContent || !baselineBoards.isEmpty
            try database.execute("DELETE FROM boards")
            let insert = try database.prepare("INSERT INTO boards (id, name, color_index, position) VALUES (?, ?, ?, ?)")
            for (position, board) in history.boards.enumerated() {
                try insert.run([.text(board.id.uuidString), .text(board.name), .int(board.colorIndex), .int(position)])
            }
            statistics.boardsChanged = true
        }
        let present = Set(history.items.map(\.id))
        let delete = try database.prepare("DELETE FROM items WHERE id = ?")
        for id in deleting where !present.contains(id) {
            try delete.run([.text(id.uuidString)]); statistics.itemsDeleted += 1
            replacedContent = true
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
            var payloadItems: [[String: Data]]?
            if previous?.fingerprint != item.fingerprint {
                // A partial payload must never replace stored bytes. When deferred content can no longer be read
                // because another writer deleted or replaced the item, that writer's change stands and this item
                // is left out of the save instead of failing every save from now on.
                do { payloadItems = try item.payload.materializedItems() }
                catch is RepresentationReader.ReadError { continue }
            }
            if previous != nil { replacedContent = true }
            let key = SQLiteDatabase.Value.text(item.id.uuidString)
            func optional(_ text: String?) -> SQLiteDatabase.Value { text.map { .text($0) } ?? .null }
            func optional(_ data: Data?) -> SQLiteDatabase.Value { data.map { .blob($0) } ?? .null }
            try upsert.run([
                key, .double(item.copiedAt.timeIntervalSinceReferenceDate), .text(item.source), optional(item.sourceBundleID),
                optional(item.title), .text(item.fingerprint), .int(item.payload.itemCount), optional(item.recognizedText),
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
                for (index, representations) in (payloadItems ?? []).enumerated() {
                    for (type, data) in representations { try insertRepresentation.run([key, .int(index), .text(type), .blob(data)]) }
                }
                statistics.payloadsWritten += 1
            }
        }
    }

    private func build(_ history: History, at destination: URL? = nil) throws {
        let files = FileManager.default
        let destination = destination ?? stagingURL
        for suffix in ["", "-journal", "-wal", "-shm"] { try? files.removeItem(atPath: destination.path + suffix) }
        let database = try Self.open(destination, readOnly: false, create: true, journal: "DELETE")
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        var statistics = SaveStatistics()
        try database.transaction {
            var replacedContent = false
            try Self.write(history, to: database, baseline: [:], deleting: [], baselineBoards: [], statistics: &statistics,
                           replacedContent: &replacedContent)
        }
    }

    /// History in the order the store keeps it: newest first, with items copied at the same instant left in
    /// their original order. Older builds inserted every capture at the front, so a plist can arrive out of
    /// order; conversion builds and compares against this form rather than refusing to convert.
    private static func canonical(_ history: History) -> History {
        let ordered = history.items.enumerated()
            .sorted { $0.element.copiedAt == $1.element.copiedAt ? $0.offset < $1.offset : $0.element.copiedAt > $1.element.copiedAt }
            .map(\.element)
        return History(items: ordered, boards: history.boards)
    }

    /// Compares a conversion or merge with what it was built from. Items are matched by id rather than by
    /// position, because rows written into an existing database keep their original rowid and so can come
    /// back in a different order among items sharing a timestamp. The stored order is checked separately.
    private static func verify(_ converted: History, matches expected: History) throws {
        guard converted.boards == expected.boards else { throw StoreError.migrationMismatch("pinboards differ") }
        guard converted.items.count == expected.items.count else { throw StoreError.migrationMismatch("item counts differ") }
        var remaining = Dictionary(converted.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard remaining.count == converted.items.count else { throw StoreError.migrationMismatch("duplicate items") }
        for item in expected.items {
            guard remaining.removeValue(forKey: item.id) == item else { throw StoreError.migrationMismatch("items differ") }
        }
        guard zip(converted.items, converted.items.dropFirst()).allSatisfy({ $0.copiedAt >= $1.copiedAt }) else {
            throw StoreError.migrationMismatch("items are not stored newest first")
        }
    }

    private func recoverReappearedArchive() throws {
        let files = FileManager.default
        let database = try Self.open(databaseURL, readOnly: false)
        let legacyHistory = try Archive(url: legacyArchiveURL).load()
        // Back up before the merge transaction, and only when no earlier attempt already saved these exact
        // plist bytes, so a recovery that keeps failing cannot add a full-size copy on every launch.
        if try existingRecoveryDirectory() == nil { try backupRecoveryFiles(databaseHistory: try Self.read(database)) }
        try database.transaction {
            let databaseHistory = try Self.read(database)
            let candidate = Self.merge(databaseHistory: databaseHistory, legacyHistory: legacyHistory)
            let baseline = Self.baseline(databaseHistory.items)
            var statistics = SaveStatistics()
            var replacedContent = false
            try Self.write(candidate, to: database, baseline: baseline, deleting: Set(baseline.keys),
                           baselineBoards: databaseHistory.boards, statistics: &statistics, replacedContent: &replacedContent)
            try Self.verify(try Self.read(database), matches: candidate)
        }
        try files.moveItem(at: legacyArchiveURL, to: nextRecoveredArchiveURL())
    }

    private static func loadHistory(from url: URL) throws -> History {
        try read(open(url, readOnly: true))
    }

    /// The reappeared plist is the later whole-history writer. It wins same-ID metadata, while pin
    /// memberships are unioned and every database-only item and pinboard is retained.
    private static func merge(databaseHistory: History, legacyHistory: History) -> History {
        var boards = legacyHistory.boards
        let legacyBoardIDs = Set(boards.map(\.id))
        boards.append(contentsOf: databaseHistory.boards.filter { !legacyBoardIDs.contains($0.id) })

        var items = Dictionary(databaseHistory.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for legacyItem in legacyHistory.items {
            var recovered = legacyItem
            if let databaseItem = items[legacyItem.id] { recovered.boardIDs.formUnion(databaseItem.boardIDs) }
            items[legacyItem.id] = recovered
        }
        let preferredOrder = legacyHistory.items.map(\.id) + databaseHistory.items.map(\.id).filter { id in
            !legacyHistory.items.contains(where: { $0.id == id })
        }
        let rank = Dictionary(uniqueKeysWithValues: preferredOrder.enumerated().map { ($0.element, $0.offset) })
        let mergedItems = items.values.sorted {
            if $0.copiedAt != $1.copiedAt { return $0.copiedAt > $1.copiedAt }
            return rank[$0.id, default: .max] < rank[$1.id, default: .max]
        }
        return History(items: mergedItems, boards: boards)
    }

    /// A recovery directory that already holds a byte-identical copy of the plist waiting to be recovered.
    private func existingRecoveryDirectory() throws -> URL? {
        let files = FileManager.default
        let current = try Data(contentsOf: legacyArchiveURL, options: .mappedIfSafe)
        let entries = (try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where entry.lastPathComponent.hasPrefix("history-recovery-") {
            let copy = entry.appendingPathComponent(legacyArchiveURL.lastPathComponent)
            guard let bytes = try? Data(contentsOf: copy, options: .mappedIfSafe), bytes == current else { continue }
            return entry
        }
        return nil
    }

    private func backupRecoveryFiles(databaseHistory: History) throws {
        let files = FileManager.default
        let recovery = directory.appendingPathComponent("history-recovery-" + UUID().uuidString)
        try files.createDirectory(at: recovery, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let archiveCopy = recovery.appendingPathComponent(legacyArchiveURL.lastPathComponent)
        try files.copyItem(at: legacyArchiveURL, to: archiveCopy)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archiveCopy.path)
        let databaseCopy = recovery.appendingPathComponent(databaseURL.lastPathComponent)
        try build(databaseHistory, at: databaseCopy)
        try Self.verify(try Self.loadHistory(from: databaseCopy), matches: databaseHistory)
    }

    private func nextRecoveredArchiveURL() -> URL {
        nextAvailableArchiveURL(base: directory.appendingPathComponent("history.plist.recovered"))
    }

    private func nextMigratedArchiveURL() -> URL {
        nextAvailableArchiveURL(base: migratedArchiveURL)
    }

    private func nextAvailableArchiveURL(base: URL) -> URL {
        let files = FileManager.default
        guard files.fileExists(atPath: base.path) else { return base }
        var number = 2
        while files.fileExists(atPath: URL(fileURLWithPath: base.path + "-\(number)").path) { number += 1 }
        return URL(fileURLWithPath: base.path + "-\(number)")
    }

    private func retireLegacyArchive() throws {
        let files = FileManager.default
        guard files.fileExists(atPath: legacyArchiveURL.path) else { return }
        try files.moveItem(at: legacyArchiveURL, to: nextMigratedArchiveURL())
    }
}

/// Reads an item's stored representations on demand, through its own read-only connection so a card or a paste on
/// the main thread never waits behind a save. Reads check the item's fingerprint, so bytes another process has
/// since replaced are never mixed into an older item.
final class RepresentationReader: @unchecked Sendable {
    enum ReadError: LocalizedError {
        case changed, missing(String)
        var errorDescription: String? {
            switch self {
            case .changed: String(localized: "The item was changed or deleted elsewhere.")
            case .missing(let type): String(localized: "Stored content (\(type)) could not be read.")
            }
        }
    }
    let url: URL
    private let lock = NSLock()
    private var database: SQLiteDatabase?
    init(url: URL) { self.url = url }
    func representations(of itemID: UUID, fingerprint: String) throws -> [Int: [String: Data]] {
        try lock.withLock {
            let database = try self.database ?? SQLiteDatabase(url: url, create: false, readOnly: true)
            self.database = database
            return try database.readTransaction {
                let key = SQLiteDatabase.Value.text(itemID.uuidString)
                let item = try database.prepare("SELECT fingerprint FROM items WHERE id = ?")
                try item.bind([key])
                guard try item.step(), item.text(0) == fingerprint else { throw ReadError.changed }
                let rows = try database.prepare("SELECT item_index, type, data FROM representations WHERE item_id = ?")
                try rows.bind([key])
                var result: [Int: [String: Data]] = [:]
                while try rows.step() { if let type = rows.text(1) { result[rows.int(0), default: [:]][type] = rows.blob(2) ?? Data() } }
                return result
            }
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
