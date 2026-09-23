import Foundation

/// A CSS/Core Animation style cubic timing curve from (0, 0) to (1, 1).
public struct TimingCurve: Equatable, Sendable {
    public let x1: Double, y1: Double, x2: Double, y2: Double
    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) { self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2 }

    /// Paste 6.3.11's history panel, fitted to 60 fps recordings: it rises in 0.15 s, covering over half the
    /// distance in the first 20 ms, and leaves in 0.18 s with a gentle ease-in-out.
    public static let panelIn = TimingCurve(0.30, 0.55, 0.05, 1)
    public static let panelOut = TimingCurve(0.35, 0, 0.70, 1)

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
