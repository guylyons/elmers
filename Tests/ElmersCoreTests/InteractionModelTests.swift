import Foundation
import ElmersCore

final class InteractionModelTests {
    func testPasteDefaultGlobalAndModifierBindings() {
        let settings = ShortcutSettings()
        XCTAssertEqual(settings.activation, KeyStroke(9, .command.union(.shift)))
        XCTAssertEqual(settings.stack, KeyStroke(8, .command.union(.shift)))
        XCTAssertEqual(settings.nextBoard, KeyStroke(124, .command))
        XCTAssertEqual(settings.previousBoard, KeyStroke(123, .command))
        XCTAssertEqual(settings.quickPasteModifier, .command)
        XCTAssertEqual(settings.plainTextModifier, .shift)
    }
    func testCustomShortcutsRoundTripAndConflicts() throws {
        var settings = ShortcutSettings()
        settings.activation = KeyStroke(9, [.control, .option])
        settings.nextBoard = KeyStroke(47, .control)
        settings.previousBoard = nil
        settings.quickPasteModifier = .option
        settings.plainTextModifier = .control
        let restored = try JSONDecoder().decode(ShortcutSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored, settings)
        XCTAssertNil(settings.validationError)
        XCTAssertEqual(KeyboardRouter.command(for: .init(47, .control), context: .results, settings: restored), .nextBoard)
        XCTAssertEqual(KeyboardRouter.command(for: .init(18, .option), context: .results, settings: restored), .quickPaste(0, plain: false))
        XCTAssertEqual(KeyboardRouter.command(for: .init(18, [.option, .control]), context: .results, settings: restored), .quickPaste(0, plain: true))
        XCTAssertEqual(KeyboardRouter.command(for: .init(36, .control), context: .results, settings: restored), .paste(plain: true))
        settings.plainTextModifier = .option
        XCTAssertNotNil(settings.validationError)
        settings.plainTextModifier = .shift
        settings.previousBoard = settings.nextBoard
        XCTAssertNotNil(settings.validationError)
        settings.previousBoard = nil
        settings.nextBoard = KeyStroke(3, .command)
        XCTAssertNotNil(settings.validationError)
        settings.nextBoard = nil
        settings.activation = KeyStroke(18, settings.quickPasteModifier)
        XCTAssertNotNil(settings.validationError)
        // A menu item's key equivalent is named, in Paste's wording.
        settings.activation = KeyStroke(43, .command)
        XCTAssertEqual(settings.validationError, "This shortcut cannot be used because it is already used by the menu item ‘Settings…’.")
    }
    func testPasteKeyboardMap() {
        let cases: [(KeyStroke, KeyboardCommand)] = [
            (.init(124), .move(1, extend: false)), (.init(123), .move(-1, extend: false)),
            (.init(124, .shift), .move(1, extend: true)), (.init(123, .shift), .move(-1, extend: true)),
            (.init(126, .command), .first), (.init(125, .command), .last),
            (.init(0, .command), .selectAll), (.init(36), .paste(plain: false)),
            (.init(36, .shift), .paste(plain: true)), (.init(18, .command), .quickPaste(0, plain: false)),
            (.init(25, [.command, .shift]), .quickPaste(8, plain: true)),
            (.init(8, .command), .copy), (.init(49), .preview), (.init(31, .command), .open),
            (.init(15, .command), .rename), (.init(14, .command), .edit), (.init(14, [.command, .shift]), .writingTools), (.init(45, .command), .newText),
            (.init(51), .delete), (.init(6, .command), .undo), (.init(6, [.command, .shift]), .redo),
            (.init(3, .command), .focusSearch), (.init(48), .move(1, extend: false)), (.init(48, .shift), .move(-1, extend: false)),
            (.init(45, [.command, .shift]), .newBoard), (.init(124, .command), .nextBoard),
            (.init(123, .command), .previousBoard), (.init(17, .command), .pause),
            (.init(43, .command), .settings), (.init(12, .command), .quit), (.init(53), .escape)
        ]
        for (stroke, expected) in cases {
            XCTAssertEqual(KeyboardRouter.command(for: stroke, context: .results), expected)
        }
    }
    func testSearchReturnPastesAndTextEditingKeepsItsKeys() {
        XCTAssertEqual(KeyboardRouter.command(for: .init(36), context: .search), .paste(plain: false))
        XCTAssertEqual(KeyboardRouter.command(for: .init(36, .shift), context: .search), .paste(plain: true))
        XCTAssertEqual(KeyboardRouter.command(for: .init(48), context: .search), .move(1, extend: false))
        XCTAssertEqual(KeyboardRouter.command(for: .init(48, .shift), context: .search), .move(-1, extend: false))
        XCTAssertNil(KeyboardRouter.command(for: .init(48), context: .editor))
        XCTAssertEqual(KeyboardRouter.command(for: .init(125), context: .search), .focusResults)
        XCTAssertNil(KeyboardRouter.command(for: .init(125), context: .results))
        XCTAssertEqual(KeyboardRouter.command(for: .init(3, .command), context: .search), .filters)
        XCTAssertEqual(KeyboardRouter.command(for: .init(123), context: .search), .move(-1, extend: false))
        XCTAssertEqual(KeyboardRouter.command(for: .init(124, .shift), context: .search), .move(1, extend: true))
        XCTAssertEqual(KeyboardRouter.command(for: .init(123, .option), context: .search), nil)
        XCTAssertEqual(KeyboardRouter.command(for: .init(51), context: .search), nil)
        XCTAssertEqual(KeyboardRouter.command(for: .init(8, .command), context: .editor), nil)
        XCTAssertEqual(KeyboardRouter.command(for: .init(18, [.command, .shift]), context: .search), .quickPaste(0, plain: true))
    }
    func testRangeSelectionCanExpandAndContract() {
        let ids = (0..<5).map { _ in UUID() }
        var selection = ItemSelection()
        selection.select(ids[1], in: ids)
        selection.move(1, extend: true, in: ids)
        selection.move(1, extend: true, in: ids)
        XCTAssertEqual(selection.ids, Set([ids[1], ids[2], ids[3]]))
        selection.move(-1, extend: true, in: ids)
        XCTAssertEqual(selection.ids, Set([ids[1], ids[2]]))
        selection.select(ids[4], toggle: true, in: ids)
        XCTAssertEqual(selection.ids, Set([ids[1], ids[2], ids[4]]))
        selection.selectAll(in: ids)
        XCTAssertEqual(selection.ids.count, 5)
    }
    func testCachedMetadataRefreshesWhenEditingAndReloading() throws {
        var item = ClipboardItem(payload: .text("before"), source: "Fixture")
        item.payload = .text("https://example.com")
        XCTAssertEqual(item.text, "https://example.com")
        XCTAssertEqual(item.kind, .link)
        let restored = try PropertyListDecoder().decode(ClipboardItem.self, from: PropertyListEncoder().encode(item))
        XCTAssertEqual(restored.kind, .link)
        XCTAssertEqual(restored.text, "https://example.com")
    }
}
