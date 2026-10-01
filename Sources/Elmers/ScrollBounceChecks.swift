#if DEBUG
import AppKit
import ElmersCore

/// `--check-scroll-bounce`: a mouse wheel bounces the card row at its ends (the user's request, October 1). The row's
/// offset must move the drawn cards, a wheel notch past the start must nudge the row out and spring it back, and a notch
/// mid-row must scroll without a bounce.
@MainActor
enum ScrollBounceChecks {
    static func run(model: AppModel, controller: PanelController) {
        func fail(_ message: String) -> Never { print("FAIL: \(message)"); fflush(stdout); exit(1) }
        for index in 0..<30 { model.newText("bounce fixture \(index)") }
        controller.show()
        Task { @MainActor in
            for _ in 0..<100 where !controller.isSettled { try? await Task.sleep(nanoseconds: 50_000_000) }
            guard controller.isSettled else { fail("the panel did not finish sliding in") }
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let root = controller.panel.contentView else { fail("no panel content") }
            /// The x of the first card's left edge, along a row through the card headers (68 pt down to the cards, then
            /// 20 into the header): the first pixel that clearly differs from the panel behind them.
            @MainActor func firstCardX() -> Int? {
                guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return nil }
                root.cacheDisplay(in: root.bounds, to: rep)
                let scale = Double(rep.pixelsWide) / root.bounds.width, y = Int(88 * scale)
                guard let background = rep.colorAt(x: Int(12 * scale), y: y)?.usingColorSpace(.sRGB) else { return nil }
                for x in Int(12 * scale)..<rep.pixelsWide {
                    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    let d = abs(c.redComponent - background.redComponent) + abs(c.greenComponent - background.greenComponent) + abs(c.blueComponent - background.blueComponent)
                    if d > 0.15 { return Int(Double(x) / scale) }
                }
                return nil
            }
            // The cards draw a moment after the slide ends.
            var base = firstCardX()
            for _ in 0..<60 where base.map({ $0 > Int(root.bounds.width) - 20 }) ?? true {
                try? await Task.sleep(nanoseconds: 50_000_000); base = firstCardX()
            }
            KeyboardInteractionChecks.capturePanel(controller, name: "bounce-base")
            guard let base, base < Int(root.bounds.width) - 20 else { fail("no card drawn") }
            model.panelGeometry.rowBounce = 30
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let moved = firstCardX(), abs(moved - base - 30) <= 1 else { fail("a 30-pt row offset moved the first card from \(base) to \(String(describing: firstCardX()))") }
            model.panelGeometry.rowBounce = 0
            try? await Task.sleep(nanoseconds: 200_000_000)
            /// A mouse-wheel notch through the panel's own rewrite, as real input gets it.
            @MainActor func notch(_ lines: Int32) {
                guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: lines, wheel2: 0, wheel3: 0),
                      let event = NSEvent(cgEvent: cg), let scroll = Self.cardScroll(in: root) else { fail("no wheel event or scroll view") }
                scroll.scrollWheel(with: controller.remappedScroll(event))
            }
            notch(1)   // up, toward the start, where the row already is
            guard model.panelGeometry.rowBounce > 0 else { fail("a wheel notch past the start did not nudge the row out") }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard model.panelGeometry.rowBounce == 0 else { fail("the row did not spring back: \(model.panelGeometry.rowBounce)") }
            notch(-3)  // down, into the row
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard model.panelGeometry.rowBounce == 0, let scroll = Self.cardScroll(in: root), scroll.contentView.bounds.origin.x > 0 else {
                fail("a notch into the row bounced or did not scroll")
            }
            print("PASS: the mouse wheel bounces the card row at its start and scrolls it without a bounce elsewhere"); fflush(stdout); exit(0)
        }
    }
    static func cardScroll(in view: NSView) -> NSScrollView? {
        func all(_ view: NSView) -> [NSScrollView] { ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(all) }
        return all(view).max { $0.frame.height < $1.frame.height }
    }
}
#endif
