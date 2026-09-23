import Foundation
@testable import ElmersCore

final class ColorTests {
    func testOnlySixHexDigitsBecomeColors() {
        // Classified by Paste 6.3.11 on September 23, 2026.
        for text in ["#FF8800", "FF8800", "#123456"] {
            XCTAssertEqual(ClipboardPayload.text(text).kind, .color)
        }
        // Lowercase digits were not tried in Paste; Elmers accepts them.
        XCTAssertEqual(ClipboardPayload.text("#ff8800").kind, .color)
        for text in ["#abc", "#FF880080", "rgb(0, 128, 255)", "rgba(0,128,255,0.5)", "hsl(120, 50%, 50%)", "red", "0xFF8800",
                     " #ff8800 ", "#ff8800\n", "color: #FF8800", "#GG0000", "##FF8800"] {
            XCTAssertEqual(ClipboardPayload.text(text).kind, .text)
        }
    }

    func testColorComponentsDisplayAndContrast() {
        let orange = HexColor("FF8800")!
        XCTAssertEqual(orange.display, "#FF8800")
        XCTAssertEqual([orange.red, orange.green, orange.blue], [1, 136.0 / 255, 0])
        XCTAssertTrue(orange.luminance > 0.3)
        XCTAssertTrue(HexColor("#123456")!.luminance < 0.05)
        XCTAssertNil(HexColor("#12345"))
    }

    func testColorIsAFilterAndATypedKeyword() {
        var history = History()
        let color = history.capture(.text("#00AAFF"), source: "Fixture")
        _ = history.capture(.text("plain"), source: "Fixture")
        XCTAssertEqual(history.items.filter { SearchFilters([.kind(.color)]).matches($0) }.map(\.id), [color.id])
        XCTAssertEqual(SearchQuery("Colors blue").kind, .color)
    }
}
