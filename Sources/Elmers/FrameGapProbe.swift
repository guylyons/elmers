#if DEBUG
import AppKit
import ElmersCore

/// ELMERS_RESIZE_PROFILE=frames with `--check-panel-resize`: switches Compact Mode on and off ten times (299 and 300 pt)
/// and records the gaps between display refreshes on the main thread for 0.4 s after each switch, which is when the
/// switch animates. A gap over 1.5 refreshes is a dropped frame.
@MainActor
final class FrameGapProbe: NSObject {
    private var stamps: [CFTimeInterval] = []
    private var link: CADisplayLink?
    static var current: FrameGapProbe?

    static func run(model: AppModel, window: NSWindow) {
        let probe = FrameGapProbe(); current = probe
        guard let screen = window.screen else { print("FAIL: no screen"); exit(1) }
        let link = screen.displayLink(target: probe, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common); probe.link = link
        var switches = 0, gaps: [Double] = [], dropped = 0, refresh = 1.0 / 60
        func next() {
            if switches == 10 {
                link.invalidate()
                let sorted = gaps.sorted()
                print(String(format: "RESULT: %d switches, %d refreshes, frame gap median %.1f ms, p95 %.1f ms, max %.1f ms, %d dropped",
                             switches, gaps.count, sorted[sorted.count / 2] * 1000, sorted[Int(Double(sorted.count - 1) * 0.95)] * 1000,
                             (sorted.last ?? 0) * 1000, dropped))
                fflush(stdout); exit(0)
            }
            probe.stamps = []
            model.panelHeight = switches % 2 == 0 ? 299 : 300; switches += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let intervals = zip(probe.stamps.dropFirst(), probe.stamps).map { $0 - $1 }
                if let shortest = intervals.min(), shortest > 0.004 { refresh = min(refresh, shortest) }
                gaps += intervals; dropped += intervals.filter { $0 > refresh * 1.5 }.count
                next()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { next() }
    }
    @objc private func tick(_ link: CADisplayLink) { stamps.append(link.timestamp) }
}
#endif
