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
    /// Compact Mode below 300 pt: seen at 299 and below, full size at 300 and above. Compact cards have no header band:
    /// content starts at the card's top edge, text 36 pt down under the title row and file thumbnails 45 pt down.
    func testCompactModeBelowThreeHundred() {
        XCTAssertTrue(PanelMetrics(height: 299).isCompact)
        XCTAssertTrue(PanelMetrics(height: 252).isCompact)
        XCTAssertTrue(!PanelMetrics(height: 300).isCompact)
        XCTAssertTrue(!PanelMetrics(height: 332).isCompact)
        XCTAssertEqual(PanelMetrics(height: 280).iconScale, 1)
        XCTAssertEqual(PanelMetrics(height: 280).contentTop, 0)
        XCTAssertEqual(PanelMetrics(height: 280).textTop, 36)
        XCTAssertEqual(PanelMetrics(height: 280).fileThumbnailTop, 45)
        XCTAssertEqual(PanelMetrics(height: 332).contentTop, 50)
        XCTAssertEqual(PanelMetrics(height: 332).textTop, 60)
        XCTAssertEqual(PanelMetrics(height: 332).fileThumbnailTop, 57)
    }
    /// Paste fills a card with a 600 × 400 image at full size (212 × 163 and 312 × 256 bodies) but fits it in a square
    /// compact card, and fits a 300 × 600 image everywhere.
    func testImagesFillOnlyWhenLittleIsCut() {
        let wide = CGSize(width: 600, height: 400), tall = CGSize(width: 300, height: 600)
        XCTAssertTrue(PanelMetrics.imageFills(wide, in: CGSize(width: 211, height: 163)))
        XCTAssertTrue(PanelMetrics.imageFills(wide, in: CGSize(width: 312, height: 256)))
        XCTAssertTrue(!PanelMetrics.imageFills(wide, in: CGSize(width: 190, height: 190)))
        XCTAssertTrue(!PanelMetrics.imageFills(tall, in: CGSize(width: 211, height: 163)))
        XCTAssertTrue(!PanelMetrics.imageFills(tall, in: CGSize(width: 152, height: 152)))
        XCTAssertTrue(PanelMetrics.imageFills(CGSize(width: 500, height: 500), in: CGSize(width: 152, height: 152)))
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
