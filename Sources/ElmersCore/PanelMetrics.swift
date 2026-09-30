import CoreGraphics

/// The history panel's size and the card layout that follows from it, as Paste 6.3.11 does it (logged September 30):
/// the panel is resized by dragging its top edge between 252 and 412 pt; cards stay square with a side of the panel
/// height − 100 (a 60-pt toolbar, 8 pt above and below the cards, and the 8-pt inset under the glass, plus the ring);
/// and below 300 pt the cards switch to Compact Mode.
public struct PanelMetrics: Equatable, Sendable {
    public static let defaultHeight: CGFloat = 332
    public static let minimumHeight: CGFloat = 252
    public static let maximumHeight: CGFloat = 412
    /// Paste showed full-size cards at 300 pt and Compact Mode at 299 pt, in both drag directions.
    public static let compactBelow: CGFloat = 300
    /// How far a drag can stretch the panel past a limit before it stops giving (Paste reached 10 and 8 pt past).
    public static let stretch: CGFloat = 24

    public let height: CGFloat
    public init(height: CGFloat) { self.height = min(max(height, Self.minimumHeight), Self.maximumHeight) }
    /// The layout at a height a drag has stretched past a limit: Paste's cards keep following the panel there
    /// (136-pt compact cards at 236 pt, 332-pt cards at 432 pt) until it springs back.
    public init(stretched height: CGFloat) { self.height = height }

    public var cardSide: CGFloat { height - 100 }
    public var isCompact: Bool { height < Self.compactBelow }
    /// Full size: 50 pt at the default 232-pt card, 56 pt at 312 (the header's title, time and icon centers moved
    /// down 3.5–4 pt). Compact: one 36-pt line with the title, the short time and a 22-pt icon.
    public var headerHeight: CGFloat { isCompact ? 36 : 50 + (cardSide - 232) * 0.075 }
    /// The app icon grows with the card: Paste's icon frame is 78 pt at the default size and 86 pt at the largest.
    public var iconScale: CGFloat { isCompact ? 1 : 1 + (cardSide - 232) / 80 * (8.0 / 78) }

    /// The height shown while the top edge is dragged to `proposed`: free inside the limits, and past them a
    /// stretch that resists more the further it goes and never exceeds `stretch`. Releasing settles on
    /// `PanelMetrics(height:)`, the nearest limit.
    public static func dragged(to proposed: CGFloat) -> CGFloat {
        func band(_ excess: CGFloat) -> CGFloat { stretch * (1 - 1 / (excess * 0.55 / stretch + 1)) }
        if proposed < minimumHeight { return minimumHeight - band(minimumHeight - proposed) }
        if proposed > maximumHeight { return maximumHeight + band(proposed - maximumHeight) }
        return proposed
    }
}
