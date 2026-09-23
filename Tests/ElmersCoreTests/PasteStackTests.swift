import Foundation
import ElmersCore

final class PasteStackTests {
    func testEntriesPasteInCopyOrderUntilReversed() {
        var stack = PasteStack()
        let a = stack.push(.text("a"), source: "Notes"), b = stack.push(.text("b"), source: "Notes")
        let again = stack.push(.text("a"), source: "Notes")
        // Repeated copies are separate entries.
        XCTAssertEqual(stack.pasteOrder.map(\.id), [a.id, b.id, again.id])
        XCTAssertEqual(stack.next?.id, a.id)
        stack.reverse()
        XCTAssertEqual(stack.next?.id, again.id)
        XCTAssertEqual(stack.pasteOrder.map(\.payload.text), ["a", "b", "a"])
        stack.reverse()
        // A used entry disappears; a failed paste consumes nothing.
        stack.consume(a.id)
        XCTAssertEqual(stack.next?.id, b.id)
        stack.remove(again.id)
        XCTAssertEqual(stack.entries.map(\.id), [b.id])
        stack.clear()
        XCTAssertTrue(stack.isEmpty)
        XCTAssertNil(stack.next)
    }
}
