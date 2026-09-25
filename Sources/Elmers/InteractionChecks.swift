#if DEBUG
import AppKit
import Combine
import ElmersCore

/// Exercises the actual panel and event dispatch, with synthetic in-memory content only.
@MainActor
final class InteractionChecks {
    static var observation: AnyCancellable?
    static func run(model: AppModel, controller: PanelController) {
        model.undoManager.groupsByEvent = false
        model.undoManager.beginUndoGrouping()
        model.newText("Existing undo fixture")
        let originalID = model.history.items[0].id
        model.createBoard(name: "Undo fixture board")
        let board = model.history.boards[0]
        model.pin(model.history.items.first { $0.id == originalID }!, to: board)
        model.renameItem(model.history.items.first { $0.id == originalID }!, title: "Keep this title")
        let before = model.history.items.first { $0.id == originalID }!
        model.undoManager.endUndoGrouping()
        model.undoManager.beginUndoGrouping()
        model.newText("Existing undo fixture")
        model.undoManager.endUndoGrouping()
        model.undo()
        guard model.history.items.first(where: { $0.id == originalID }) == before else {
            print("FAIL: undo of duplicate text changed or deleted the original item"); fflush(stdout); exit(1)
        }
        model.undoManager.beginUndoGrouping()
        model.newText("Pinned redo fixture")
        model.undoManager.endUndoGrouping()
        let pinnedID = model.history.items[0].id
        model.undo(); model.redo()
        guard model.history.items.first(where: { $0.id == pinnedID })?.boardIDs.contains(board.id) == true else {
            print("FAIL: redo lost the new item's pinboard membership"); fflush(stdout); exit(1)
        }
        print("PASS: duplicate text undo and pinned-item redo preserve history")
        model.undoManager.groupsByEvent = true
        model.boardID = nil
        model.newText("Interaction fixture A")
        model.newText("Interaction fixture B")
        model.query = "Interaction fixture"
        let secondID = model.visibleItems[1].id
        model.selectedID = model.visibleItems[0].id
        model.selectAll()
        model.select(secondID, rightClick: true)
        guard model.selectedItems.count == 2 else {
            print("FAIL: context click collapsed selection"); fflush(stdout); exit(1)
        }
        print("PASS: context click preserves multiple selected items")
        model.filters = SearchFilters([.kind(.text), .app("No such app"), .date(.today)]); model.boardID = board.id; model.searchOpen = true
        controller.show()
        guard model.query.isEmpty, model.filters.isEmpty, !model.searchOpen, model.boardID == nil,
              !model.searchIsFocused, model.selectedID == model.history.items.first?.id, model.selectedItems.count == 1 else {
            print("FAIL: opening the history did not clear search and filters and select the most recent item"); fflush(stdout); exit(1)
        }
        print("PASS: opening the history clears search and filters and selects the most recent item")
        model.query = "Interaction fixture"
        model.selectedID = model.visibleItems[0].id
        var deliveries = 0
        model.deliver = { _, _ in deliveries += 1 }
        controller.show(resetState: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let started = ProcessInfo.processInfo.systemUptime
            observation = model.$selection.dropFirst().sink { selection in
                let id = selection.focus
                print("Selection changed to second: \(id == secondID), deliveries: \(deliveries)")
                if id == secondID { print("Selection latency: \(Int((ProcessInfo.processInfo.systemUptime - started) * 1000)) ms") }
            }
            // Second card, using the same window-relative coordinates as a real click.
            for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: 365, y: 130), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: controller.panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                NSApp.postEvent(event, atStart: false)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard model.selectedID == secondID else { print("FAIL: selection still pending after 120 ms; deliveries: \(deliveries)"); fflush(stdout); exit(1) }
                guard deliveries == 0 else { print("FAIL: single click pasted content"); fflush(stdout); exit(1) }
                print("PASS: single click selects without waiting for double-click timeout")
                for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                    let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: 365, y: 130), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: controller.panel.windowNumber, context: nil, eventNumber: 2, clickCount: 2, pressure: type == .leftMouseDown ? 1 : 0)!
                    NSApp.postEvent(event, atStart: false)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    guard deliveries == 1 else { print("FAIL: double click did not deliver exactly once (\(deliveries))"); fflush(stdout); exit(1) }
                    print("PASS: double click delivers exactly once")
                    observation = nil
                    checkPlainTextAlternate(model: model, controller: controller)
                    KeyboardInteractionChecks.run(model: model, controller: controller)
                }
            }
        }
    }
    /// The card menu's Paste item has a Plain Text-modifier alternate that pastes the whole selection as plain text.
    static func checkPlainTextAlternate(model: AppModel, controller: PanelController) {
        guard #available(macOS 15, *) else { print("SKIP: Paste as Plain Text alternate needs macOS 15"); return }
        func fail(_ message: String) -> Never { print("FAIL: \(message)"); fflush(stdout); exit(1) }
        let saved = model.deliver
        defer { model.deliver = saved }
        var deliveries: [(Int, Bool)] = []
        model.deliver = { item, plain in deliveries.append((item.payload.items.count, plain)) }
        model.selectAll()
        let location = NSPoint(x: 365, y: 130)
        guard let event = NSEvent.mouseEvent(with: .rightMouseDown, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: controller.panel.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 1),
              let root = controller.panel.contentView else { fail("could not build a right-click on a card") }
        var view = root.hitTest(root.convert(location, from: nil)); var menu: NSMenu?
        while let current = view, menu == nil { menu = current.menu(for: event); view = current.superview }
        guard let menu else { fail("right-clicking a card produced no menu") }
        guard let index = menu.items.firstIndex(where: { $0.title == String(localized: "Paste as Plain Text") }), index > 0 else { fail("card menu has no Paste as Plain Text item: \(menu.items.map(\.title))") }
        let alternate = menu.items[index], primary = menu.items[index - 1]
        guard alternate.isAlternate, alternate.keyEquivalentModifierMask == primary.keyEquivalentModifierMask.union(.shift), alternate.keyEquivalent == primary.keyEquivalent else {
            fail("Paste as Plain Text is not the ⇧ alternate of \(primary.title) (alternate \(alternate.isAlternate), mask \(alternate.keyEquivalentModifierMask.rawValue))")
        }
        menu.performActionForItem(at: index)
        guard deliveries.count == 1, deliveries[0].1, deliveries[0].0 == model.selectedItems.count, model.selectedItems.count > 1 else { fail("Paste as Plain Text delivered \(deliveries)") }
        menu.performActionForItem(at: index - 1)
        guard deliveries.count == 2, !deliveries[1].1 else { fail("Paste after the alternate delivered \(deliveries)") }
        print("PASS: holding ⇧ in the card menu offers Paste as Plain Text, which pastes the selection as plain text")
    }
}
#endif
