#if DEBUG
import Foundation

@MainActor
enum StoragePersistenceChecks {
    static func run(model: AppModel) {
        let token = UUID().uuidString
        let keptText = "Elmers storage fixture kept \(token)"
        let deletedText = "Elmers storage fixture deleted \(token)"
        let boardName = "Elmers storage fixture \(token)"
        let title = "Persisted fixture \(token)"

        model.newText(keptText)
        guard let kept = model.history.items.first(where: { $0.text == keptText }) else { fail("create kept item") }
        model.createBoard(name: boardName)
        guard let board = model.history.boards.first(where: { $0.name == boardName }) else { fail("create pinboard") }
        model.pin(kept, to: board)
        model.renameItem(kept, title: title)
        model.newText(deletedText)
        guard let deleted = model.history.items.first(where: { $0.text == deletedText }) else { fail("create deleted item") }
        model.delete(deleted)
        model.flush()

        let reloaded = AppModel()
        guard let persisted = reloaded.history.items.first(where: { $0.id == kept.id }),
              persisted.title == title, persisted.boardIDs.contains(board.id),
              !reloaded.history.items.contains(where: { $0.id == deleted.id }),
              reloaded.history.boards.contains(where: { $0.id == board.id }) else { fail("reload mutations") }

        reloaded.delete(persisted)
        if let persistedBoard = reloaded.history.boards.first(where: { $0.id == board.id }) { reloaded.deleteBoard(persistedBoard) }
        reloaded.flush()
        let cleaned = AppModel()
        guard !cleaned.history.items.contains(where: { $0.id == kept.id || $0.id == deleted.id }),
              !cleaned.history.boards.contains(where: { $0.id == board.id }) else { fail("clean fixtures") }
        print("PASS: real SQLite pin, rename, delete, and reload persistence")
        fflush(stdout)
        exit(0)
    }

    private static func fail(_ step: String) -> Never {
        print("FAIL: real SQLite persistence check at \(step)")
        fflush(stdout)
        exit(1)
    }
}
#endif
