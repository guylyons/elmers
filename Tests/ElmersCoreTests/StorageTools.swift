import CryptoKit
import Foundation
import ElmersCore

private enum StorageToolError: LocalizedError {
    case backupExists, backupMismatch
    var errorDescription: String? {
        switch self {
        case .backupExists: "history.plist.post-sqlite already exists; it was not overwritten."
        case .backupMismatch: "The rollback plist did not verify; SQLite was left unchanged."
        }
    }
}

@discardableResult
func backupStorageForRollback(directory suppliedDirectory: URL? = nil) throws -> URL {
    let directory = suppliedDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Elmers")
    let destination = directory.appendingPathComponent("history.plist.post-sqlite")
    guard !FileManager.default.fileExists(atPath: destination.path) else { throw StorageToolError.backupExists }
    let history = try HistoryStore(directory: directory, readOnly: true).load()
    try Archive(url: destination).save(history)
    let restored = try Archive(url: destination).load()
    guard restored.items == history.items, restored.boards == history.boards else { throw StorageToolError.backupMismatch }
    return destination
}

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
