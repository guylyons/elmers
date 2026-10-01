import Foundation

/// How the history row answers scroll input, as Paste 6.3.11 does (measured September 30 with synthetic scroll events on
/// its panel): a vertical mouse wheel scrolls the row sideways at the usual line distance, a sideways trackpad swipe
/// moves it about twice as far as the fingers travel (100 pt for 50 px, 69 pt for 40 px), and a vertical trackpad swipe
/// does not scroll it.
public enum ScrollMapping {
    public static let trackpadGain = 2.0
    /// The deltas the row should scroll by for an event's horizontal and vertical deltas. `precise` is a trackpad or
    /// Magic Mouse (pixel deltas, with momentum); otherwise a wheel that scrolls in lines.
    public static func remap(dx: Double, dy: Double, precise: Bool) -> (dx: Double, dy: Double) {
        if precise { return (dx * trackpadGain, dy) }
        if dx == 0 { return (dy, 0) }
        return (dx, dy)
    }
}
