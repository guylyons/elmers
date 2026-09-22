import AppKit
import ElmersCore

func verifyLiveCapture() throws {
    let board = NSPasteboard.general
    let original = try PasteboardCodec.read(from: board, ignoreConfidential: false, ignoreTransient: false)
    let fixture = "Elmers live verification " + UUID().uuidString
    guard PasteboardCodec.write(.text(fixture), to: board) else { throw NSError(domain: "ElmersCheck", code: 1) }
    let writtenGeneration = board.changeCount
    defer {
        if board.changeCount == writtenGeneration {
            if let original { _ = PasteboardCodec.write(original, to: board) }
            else { board.clearContents() }
        }
    }
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Elmers")
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        Thread.sleep(forTimeInterval: 0.2)
        if let history = try? HistoryStore(directory: directory, readOnly: true).load(), history.items.contains(where: { $0.text == fixture }) {
            print("PASS running app captured and persisted synthetic clipboard text")
            return
        }
    }
    failures += 1
    print("FAIL running app did not persist the synthetic clipboard within five seconds")
}
