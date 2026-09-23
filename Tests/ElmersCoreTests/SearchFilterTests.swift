import AppKit
import Foundation
@testable import ElmersCore

final class SearchFilterTests {
    private var calendar: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!; calendar.firstWeekday = 1; return calendar }
    private func date(_ day: Int, _ hour: Int = 12) -> Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))! }
    private func item(_ text: String, source: String, day: Int, hour: Int = 12) -> ClipboardItem {
        ClipboardItem(payload: .text(text), source: source, at: date(day, hour))
    }

    func testChipsInOneSectionWidenAndSectionsNarrow() {
        // Wednesday, September 23, 2026.
        let now = date(23, 15)
        let items = [item("plain words", source: "Safari", day: 23), item("https://example.com", source: "Safari", day: 22),
                     item("more words", source: "Notes", day: 22), item("https://example.org", source: "Notes", day: 10)]
        func shown(_ filters: [SearchFilter]) -> [String] { items.filter { SearchFilters(filters).matches($0, now: now, calendar: calendar) }.map(\.text) }
        XCTAssertEqual(shown([.kind(.text)]), ["plain words", "more words"])
        XCTAssertEqual(shown([.kind(.text), .kind(.link)]).count, 4)
        XCTAssertEqual(shown([.kind(.text), .date(.today)]), ["plain words"])
        XCTAssertEqual(shown([.kind(.text), .date(.today), .date(.yesterday)]), ["plain words", "more words"])
        XCTAssertEqual(shown([.app("Notes"), .kind(.link)]), ["https://example.org"])
        XCTAssertEqual(shown([.app("Notes"), .app("Safari"), .date(.last30Days)]).count, 4)
        XCTAssertEqual(shown([.device("This Mac")]), [])
        XCTAssertEqual(items.filter { SearchFilters([.device("This Mac")]).matches($0, now: now, calendar: calendar, localDevice: "This Mac") }.count, 4)
    }

    func testDateChipsCoverCalendarRanges() {
        let now = date(23, 15)
        func covers(_ range: DateRangeFilter, _ day: Int, _ hour: Int = 12) -> Bool {
            SearchFilters([.date(range)]).matches(item("x", source: "A", day: day, hour: hour), now: now, calendar: calendar)
        }
        XCTAssertTrue(covers(.today, 23, 0)); XCTAssertTrue(covers(.today, 23, 23)); XCTAssertTrue(!covers(.today, 22, 23))
        XCTAssertTrue(covers(.yesterday, 22, 0)); XCTAssertTrue(!covers(.yesterday, 23, 0)); XCTAssertTrue(!covers(.yesterday, 21, 23))
        // The week of September 20 (Sunday) to 26.
        XCTAssertTrue(covers(.thisWeek, 20, 0)); XCTAssertTrue(!covers(.thisWeek, 19, 23))
        XCTAssertTrue(covers(.lastWeek, 13, 0)); XCTAssertTrue(covers(.lastWeek, 19, 23)); XCTAssertTrue(!covers(.lastWeek, 20, 0)); XCTAssertTrue(!covers(.lastWeek, 12, 23))
        // Thirty days before 15:00 on September 23 is 15:00 on August 24.
        XCTAssertTrue(covers(.last30Days, 1)); XCTAssertTrue(!covers(.last30Days, -7))
    }

    func testTokensKeepPickOrderAndToggle() {
        var filters = SearchFilters()
        filters.toggle(.kind(.text)); filters.toggle(.kind(.link)); filters.toggle(.app("Safari")); filters.toggle(.date(.today)); filters.toggle(.app("Signal"))
        XCTAssertEqual(filters.tokens, [.kind(.text), .kind(.link), .app("Safari"), .date(.today), .app("Signal")])
        filters.toggle(.kind(.link))
        XCTAssertEqual(filters.tokens, [.kind(.text), .app("Safari"), .date(.today), .app("Signal")])
        XCTAssertEqual(filters.removeLast(), .app("Signal"))
        filters.add(.kind(.text))
        XCTAssertEqual(filters.kinds, [.text])
        filters.removeAll(); XCTAssertTrue(filters.isEmpty)
    }

    func testImageChipIncludesScreenshots() throws {
        var history = History()
        let image = history.capture(.init(items: [["public.png": try ScreenshotTests.image()]]), source: "Fixture")
        var marked = image
        marked.screenshot = ScreenshotOrigin(originalURL: URL(fileURLWithPath: "/tmp/fixture.png"), fileIdentity: "fixture")
        history.replaceItem(marked)
        let text = history.capture(.text("words"), source: "Fixture")
        XCTAssertEqual(history.items.filter { SearchFilters([.kind(.image)]).matches($0) }.map(\.id), [image.id])
        XCTAssertEqual(history.items.filter { SearchFilters([.kind(.screenshot), .kind(.text)]).matches($0) }.map(\.id).sorted { $0.uuidString < $1.uuidString },
                       [image.id, text.id].sorted { $0.uuidString < $1.uuidString })
    }
}
