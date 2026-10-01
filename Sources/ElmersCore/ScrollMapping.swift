import Foundation

/// How the history row answers scroll input, as Paste 6.3.11 does (measured September 30 with synthetic scroll events on
/// its panel): a vertical mouse wheel scrolls the row sideways at the usual line distance, a sideways trackpad swipe
/// moves it about twice as far as the fingers travel (100 pt for 50 px, 69 pt for 40 px), and a vertical trackpad swipe
/// does not scroll it.
public enum ScrollMapping {
    public static let trackpadGain = 2.0
    /// The deltas the row should scroll by for an event's horizontal and vertical deltas. `precise` is a trackpad or
    /// Magic Mouse (pixel deltas, with momentum); otherwise a wheel that scrolls in lines. `pastEdge`: the row is at or
    /// past its start or end and the swipe pushes further out. Paste stretches there only about 8 pt per 100 px of swipe
    /// (29 per 400), which is AppKit's own rubber band for undoubled deltas, so the gain stops.
    public static func remap(dx: Double, dy: Double, precise: Bool, pastEdge: Bool = false) -> (dx: Double, dy: Double) {
        if precise { return (dx * (pastEdge ? 1 : trackpadGain), dy) }
        if dx == 0 { return (dy, 0) }
        return (dx, dy)
    }
}
