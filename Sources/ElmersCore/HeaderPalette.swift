import Foundation

/// Paste 6.3.11 paints a card's header in one of a fixed set of colors chosen from the source app's icon, not in the
/// icon's own color: Finder's and Safari's different blues both become #62A9F5, Calendar's and Reminders' reds both
/// #F0544D (measured September 30 from window captures of test cards copied with each app in front). These are the
/// colors seen so far; an icon is matched to the nearest by its dominant colorful hue, or to gray or black when it has
/// almost no color.
public enum HeaderPalette {
    public struct RGB: Equatable, Sendable {
        public let red: Double, green: Double, blue: Double
        public init(_ red: Double, _ green: Double, _ blue: Double) { self.red = red; self.green = green; self.blue = blue }
        public init(hex: UInt32) { self.init(Double(hex >> 16 & 0xFF) / 255, Double(hex >> 8 & 0xFF) / 255, Double(hex & 0xFF) / 255) }
    }
    /// Light blue (Finder, Safari), deep blue (Ghostty), indigo (Emacs), purple (Textual), green (Messages), red
    /// (Calendar, Reminders), orange-red (Brave), orange (VLC).
    public static let colors: [RGB] = [0x62A9F5, 0x0D3FCB, 0x2D37CB, 0x8542E6, 0x0DD04B, 0xF0544D, 0xF93C00, 0xDF7714].map(RGB.init(hex:))
    /// Calculator's body.
    public static let gray = RGB(hex: 0x5B5F61)
    /// Orca's mostly black icon.
    public static let black = RGB(hex: 0x020200)
    /// An icon counts as colorful when at least this share of its opaque pixels has color (saturation ≥ 0.3,
    /// brightness ≥ 0.25).
    public static let colorfulShare = 0.05

    /// The header for an icon whose dominant colorful hue averages to `dominant`, matched by RGB distance.
    public static func color(dominant: RGB) -> RGB {
        func distance(_ c: RGB) -> Double {
            let r = c.red - dominant.red, g = c.green - dominant.green, b = c.blue - dominant.blue
            return r * r + g * g + b * b
        }
        return colors.min { distance($0) < distance($1) }!
    }
    /// The header for an icon with almost no color, by the average brightness of its non-white gray pixels.
    public static func color(grayBrightness: Double) -> RGB { grayBrightness < 0.45 ? black : gray }
}
