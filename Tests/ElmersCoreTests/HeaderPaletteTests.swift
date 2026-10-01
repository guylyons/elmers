import ElmersCore

struct HeaderPaletteTests {
    /// Dominant colors measured from real app icons, mapped as Paste 6.3.11 painted those apps' headers.
    func testIconColorsSnapToPastesPalette() {
        func hex(_ c: HeaderPalette.RGB) -> String { String(format: "#%02X%02X%02X", Int((c.red * 255).rounded()), Int((c.green * 255).rounded()), Int((c.blue * 255).rounded())) }
        let cases: [(UInt32, String)] = [(0x02ABF8, "#62A9F5"), (0x0B9BFE, "#62A9F5"), (0xE88E1F, "#DF7714"), (0x3ADB55, "#0DD04B"),
                                         (0xFF4853, "#F0544D"), (0x192D8F, "#0D3FCB"), (0xFA4A23, "#F93C00"), (0x7348BA, "#8542E6")]
        for (dominant, paste) in cases { XCTAssertEqual(hex(HeaderPalette.color(dominant: .init(hex: dominant))), paste) }
        XCTAssertEqual(hex(HeaderPalette.color(grayBrightness: 0.60)), "#5B5F61")
        XCTAssertEqual(hex(HeaderPalette.color(grayBrightness: 0.38)), "#020200")
    }
}
