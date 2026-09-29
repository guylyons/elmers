import Foundation

/// A CSS/Core Animation style cubic timing curve from (0, 0) to (1, 1).
public struct TimingCurve: Equatable, Sendable {
    public let x1: Double, y1: Double, x2: Double, y2: Double
    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) { self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2 }

    /// Paste 6.3.11's history panel, fitted to 60 fps recordings: it rises in 0.15 s, covering over half the
    /// distance in the first 20 ms, and leaves in 0.18 s with a gentle ease-in-out.
    public static let panelIn = TimingCurve(0.30, 0.55, 0.05, 1)
    public static let panelOut = TimingCurve(0.35, 0, 0.70, 1)
    /// Paste 6.3.11's search mode, fitted to recordings of its toolbar: the field grows out of the magnifier and the
    /// pinboards ride with its right edge (0.21 s), and closing reverses it (0.24 s).
    public static let searchOpen = TimingCurve(0.10, 0.40, 0.60, 0.90)
    public static let searchClose = TimingCurve(0.25, 0.40, 0.60, 0.90)
    public static let searchOpenDuration = 0.21, searchCloseDuration = 0.24

    /// Progress at elapsed fraction `x` (clamped to 0...1).
    public func value(at x: Double) -> Double {
        let x = min(max(x, 0), 1)
        if x == 0 || x == 1 { return x }
        // Solve bezierX(t) = x by bisection; the curve is monotonic in x for control x values in 0...1.
        var low = 0.0, high = 1.0, t = x
        for _ in 0..<40 {
            t = (low + high) / 2
            if Self.coordinate(t, x1, x2) < x { low = t } else { high = t }
        }
        return Self.coordinate(t, y1, y2)
    }
    private static func coordinate(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }
}

/// The menu bar character's "gulp" when an item lands in history: it squashes down as if swallowing, springs up
/// taller and narrower, then settles with a small wobble. Scales are applied about the icon's bottom center.
public enum GulpAnimation {
    public static let duration = 0.5
    public static let framesPerSecond = 60.0
    /// (time fraction, horizontal scale, vertical scale).
    static let keyframes: [(Double, Double, Double)] = [(0, 1, 1), (0.24, 1.12, 0.82), (0.52, 0.92, 1.10), (0.76, 1.03, 0.97), (1, 1, 1)]

    /// Horizontal and vertical scale at elapsed fraction `t` (clamped to 0...1), eased between keyframes.
    public static func scale(at t: Double) -> (x: Double, y: Double) {
        let t = min(max(t, 0), 1)
        guard let upper = keyframes.firstIndex(where: { $0.0 >= t }), upper > 0 else { return (1, 1) }
        let a = keyframes[upper - 1], b = keyframes[upper]
        let local = (t - a.0) / (b.0 - a.0), eased = local * local * (3 - 2 * local)
        return (a.1 + (b.1 - a.1) * eased, a.2 + (b.2 - a.2) * eased)
    }

    /// One scale per display frame, ending at rest.
    public static var frames: [(x: Double, y: Double)] {
        let count = Int((duration * framesPerSecond).rounded())
        return (1...count).map { scale(at: Double($0) / Double(count)) }
    }
}
