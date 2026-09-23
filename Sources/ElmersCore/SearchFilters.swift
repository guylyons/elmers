import Foundation

/// Paste 6.3.11's date chips in the search filter popover.
public enum DateRangeFilter: String, CaseIterable, Codable, Sendable {
    case today, yesterday, thisWeek, lastWeek, last30Days
    public var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This week"
        case .lastWeek: return "Last week"
        case .last30Days: return "Last 30 days"
        }
    }
    /// The copy times the chip covers, start included and end excluded. Weeks follow the calendar's first
    /// weekday. The ranges are an Elmers reading of the chip titles; Paste's boundaries were not measured.
    public func interval(now: Date, calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        // Open-ended ranges run into the future, so a copy made after `now` was taken still counts.
        let end = Date.distantFuture
        switch self {
        case .today: return DateInterval(start: today, end: end)
        case .yesterday: return DateInterval(start: calendar.date(byAdding: .day, value: -1, to: today)!, end: today)
        case .thisWeek: return DateInterval(start: calendar.dateInterval(of: .weekOfYear, for: now)!.start, end: end)
        case .lastWeek:
            let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)!.start
            return DateInterval(start: calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek)!, end: thisWeek)
        case .last30Days: return DateInterval(start: calendar.date(byAdding: .day, value: -30, to: now)!, end: end)
        }
    }
}

/// One chip chosen in the filter popover, shown as a token in the search field.
public enum SearchFilter: Hashable, Sendable {
    case kind(ContentKind)
    case app(String)
    case date(DateRangeFilter)
    /// The device an item was copied on. Without sync every item comes from this Mac, so the local device's
    /// chip matches everything.
    case device(String)

    public enum Category: CaseIterable, Sendable { case kind, app, date, device }
    public var category: Category {
        switch self { case .kind: return .kind; case .app: return .app; case .date: return .date; case .device: return .device }
    }
}

/// The filters chosen in the search field, in the order the user picked them.
///
/// Paste 6.3.11 lets every section of the popover hold several chips. Chips in one section widen the
/// results (Text + Link shows both), and sections narrow each other (Text + Today shows today's text).
public struct SearchFilters: Equatable, Sendable {
    public private(set) var tokens: [SearchFilter] = []
    public init(_ tokens: [SearchFilter] = []) { tokens.forEach { add($0) } }

    public var isEmpty: Bool { tokens.isEmpty }
    public func contains(_ filter: SearchFilter) -> Bool { tokens.contains(filter) }
    public var kinds: [ContentKind] { tokens.compactMap { if case let .kind(kind) = $0 { return kind } else { return nil } } }

    public mutating func add(_ filter: SearchFilter) { if !tokens.contains(filter) { tokens.append(filter) } }
    public mutating func remove(_ filter: SearchFilter) { tokens.removeAll { $0 == filter } }
    public mutating func toggle(_ filter: SearchFilter) { if contains(filter) { remove(filter) } else { add(filter) } }
    @discardableResult public mutating func removeLast() -> SearchFilter? { tokens.popLast() }
    public mutating func removeAll() { tokens.removeAll() }

    /// `localDevice` names this Mac; items carry no device of their own, so they all belong to it.
    public func matches(_ item: ClipboardItem, now: Date = Date(), calendar: Calendar = .current, localDevice: String = "") -> Bool {
        SearchFilter.Category.allCases.allSatisfy { category in
            let chosen = tokens.filter { $0.category == category }
            return chosen.isEmpty || chosen.contains { filter in
                switch filter {
                case let .kind(kind): return item.kind == kind || (kind == .image && item.kind.isImage)
                case let .app(name): return item.source == name
                case let .date(range): let interval = range.interval(now: now, calendar: calendar); return interval.start <= item.copiedAt && item.copiedAt < interval.end
                case let .device(name): return name == localDevice
                }
            }
        }
    }
}
