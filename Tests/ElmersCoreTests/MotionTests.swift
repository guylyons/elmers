import ElmersCore

struct MotionTests {
    func testPanelCurvesMatchPasteRecordings() {
        let show = TimingCurve.panelIn, hide = TimingCurve.panelOut
        XCTAssertEqual(show.value(at: 0), 0); XCTAssertEqual(show.value(at: 1), 1)
        XCTAssertEqual(hide.value(at: -1), 0); XCTAssertEqual(hide.value(at: 2), 1)
        // Offsets Paste 6.3.11 reached (of 332 pt) at these times after the show began (t0 = 0.787 s, 0.15 s long).
        let shown: [(Double, Double)] = [(0.817, 144), (0.833, 71), (0.850, 37), (0.867, 20), (0.883, 9), (0.917, 1)]
        for (time, offset) in shown {
            XCTAssertTrue(abs(show.value(at: (time - 0.787) / 0.15) - (1 - offset / 332)) < 0.03)
        }
        let hidden: [(Double, Double)] = [(0.750, 17), (0.783, 74), (0.817, 163), (0.850, 252), (0.883, 321)]
        for (time, offset) in hidden {
            XCTAssertTrue(abs(hide.value(at: (time - 0.725) / 0.18) - offset / 332) < 0.05)
        }
        // Monotonic, so the panel never overshoots or backs up.
        var previous = 0.0
        for step in 1...100 { let value = show.value(at: Double(step) / 100); XCTAssertTrue(value >= previous - 1e-9); previous = value }
    }
}
