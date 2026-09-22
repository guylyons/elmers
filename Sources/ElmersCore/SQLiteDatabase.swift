import Foundation
import SQLite3

final class SQLiteDatabase {
    struct Failure: LocalizedError {
        let code: Int32
        let message: String
        var errorDescription: String? { "SQLite error \(code): \(message)" }
    }
    enum Value { case int(Int), double(Double), text(String), blob(Data), null }
    private let handle: OpaquePointer

    init(url: URL, create: Bool, readOnly: Bool = false) throws {
        // SQLite would create the file with the process umask, and it copies that mode onto the journal,
        // WAL and SHM files it opens later. Create it private first so nothing is ever briefly world-readable.
        if create, !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
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
    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try body(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }
    func readTransaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN DEFERRED")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
    var isInTransaction: Bool { sqlite3_get_autocommit(handle) == 0 }
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

        func run(_ values: [Value]) throws { try bind(values); while try step() {} }
        func bind(_ values: [Value]) throws {
            sqlite3_reset(handle); sqlite3_clear_bindings(handle)
            for (offset, value) in values.enumerated() {
                let index = Int32(offset + 1)
                let result: Int32
                switch value {
                case .int(let number): result = sqlite3_bind_int64(handle, index, Int64(number))
                case .double(let number): result = sqlite3_bind_double(handle, index, number)
                case .text(let string):
                    result = string.withCString { sqlite3_bind_text(handle, index, $0, Int32(string.utf8.count), Self.transient) }
                case .blob(let data) where data.isEmpty: result = sqlite3_bind_zeroblob(handle, index, 0)
                case .blob(let data):
                    result = data.withUnsafeBytes { sqlite3_bind_blob(handle, index, $0.baseAddress, Int32(data.count), Self.transient) }
                case .null: result = sqlite3_bind_null(handle, index)
                }
                guard result == SQLITE_OK else { throw database.failure(result) }
            }
        }
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
