import ElmersCore

struct ScrollMappingTests {
    /// Paste 6.3.11, measured September 30 with synthetic scroll events on its panel: a vertical mouse wheel scrolls the
    /// row sideways, a sideways trackpad swipe moves it about twice as far as the fingers, and a vertical swipe does not
    /// scroll it.
    func testScrollInputMapsAsPaste() {
        let swipe = ScrollMapping.remap(dx: -10, dy: 0, precise: true)
        XCTAssertEqual(swipe.dx, -20); XCTAssertEqual(swipe.dy, 0)
        let verticalSwipe = ScrollMapping.remap(dx: 0, dy: -10, precise: true)
        XCTAssertEqual(verticalSwipe.dx, 0); XCTAssertEqual(verticalSwipe.dy, -10)
        let wheel = ScrollMapping.remap(dx: 0, dy: -3, precise: false)
        XCTAssertEqual(wheel.dx, -3); XCTAssertEqual(wheel.dy, 0)
        let sideways = ScrollMapping.remap(dx: -1, dy: 0, precise: false)
        XCTAssertEqual(sideways.dx, -1); XCTAssertEqual(sideways.dy, 0)
    }
}
