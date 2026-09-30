import Foundation
import ElmersCore

struct PanelMetricsTests {
    /// Paste 6.3.11, logged September 30: square cards whose side is the panel height − 100, from 252 to 412 pt.
    func testCardsFollowThePanelHeight() {
        XCTAssertEqual(PanelMetrics.defaultHeight, 332)
        XCTAssertEqual(PanelMetrics(height: 332).cardSide, 232)
        XCTAssertEqual(PanelMetrics(height: 412).cardSide, 312)
        XCTAssertEqual(PanelMetrics(height: 252).cardSide, 152)
        // Heights from outside the range (an older or hand-edited setting) come back inside it.
        XCTAssertEqual(PanelMetrics(height: 600).height, 412)
        XCTAssertEqual(PanelMetrics(height: 100).height, 252)
        // The header and app icon grow a little with the card: 50 → 56 pt and 78 → 86 pt of Paste's icon frame.
        XCTAssertEqual(PanelMetrics(height: 332).headerHeight, 50)
        XCTAssertTrue(abs(PanelMetrics(height: 412).headerHeight - 56) < 0.01)
        XCTAssertEqual(PanelMetrics(height: 332).iconScale, 1)
        XCTAssertTrue(abs(PanelMetrics(height: 412).iconScale - 86.0 / 78) < 0.001)
    }
    /// Compact Mode below 300 pt: seen at 299 and below, full size at 300 and above; a 36-pt header.
    func testCompactModeBelowThreeHundred() {
        XCTAssertTrue(PanelMetrics(height: 299).isCompact)
        XCTAssertTrue(PanelMetrics(height: 252).isCompact)
        XCTAssertTrue(!PanelMetrics(height: 300).isCompact)
        XCTAssertTrue(!PanelMetrics(height: 332).isCompact)
        XCTAssertEqual(PanelMetrics(height: 280).headerHeight, 36)
        XCTAssertEqual(PanelMetrics(height: 280).iconScale, 1)
    }
    /// Dragging past a limit stretches with growing resistance (Paste reached 242 and 420) and never passes the
    /// stretch limit; letting go settles on the limit.
    func testDragRubberBandsPastTheLimits() {
        XCTAssertEqual(PanelMetrics.dragged(to: 350), 350)
        XCTAssertEqual(PanelMetrics.dragged(to: 252), 252)
        let below = PanelMetrics.dragged(to: 200), above = PanelMetrics.dragged(to: 480)
        XCTAssertTrue(below < 252 && below > 252 - PanelMetrics.stretch)
        XCTAssertTrue(above > 412 && above < 412 + PanelMetrics.stretch)
        XCTAssertTrue(PanelMetrics.dragged(to: 100) < below)
        XCTAssertTrue(PanelMetrics.dragged(to: -5000) > 252 - PanelMetrics.stretch)
        XCTAssertEqual(PanelMetrics(stretched: 236).cardSide, 136)
        XCTAssertTrue(PanelMetrics(stretched: 236).isCompact)
        XCTAssertEqual(PanelMetrics(height: below).height, 252)
        XCTAssertEqual(PanelMetrics(height: above).height, 412)
    }
}
