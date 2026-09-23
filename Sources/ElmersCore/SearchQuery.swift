import Foundation

/// A search field query split into free-text terms and the filters spelled out in it.
///
/// Paste surfaces filters directly in the search field as the user types. Elmers reads a
/// content-type word ("image", "links", "URL", in any case) as a type filter rather than a
/// search term, so typing a category shows that category.
public struct SearchQuery: Equatable, Sendable {
    public var kind: ContentKind?
    /// The word that produced `kind`, so it can be put back when the filter is removed.
    public var kindWord: String?
    public var terms: [String]
    /// The query with the type word taken out.
    public var remainder: String { terms.joined(separator: " ") }

    /// Parses `raw`. When `recognizeKind` is false every word stays a search term, which is the
    /// right behavior when a type has already been chosen from the filter menu.
    public init(_ raw: String, recognizeKind: Bool = true) {
        var kind: ContentKind? = nil
        var kindWord: String? = nil
        var terms: [String] = []
        for token in raw.split(whereSeparator: \.isWhitespace).map(String.init) {
            if recognizeKind, kind == nil, let match = ContentKind.matching(keyword: token) { kind = match; kindWord = token } else { terms.append(token) }
        }
        self.kind = kind
        self.kindWord = kindWord
        self.terms = terms
    }
}

extension ContentKind {
    /// Words a user might type to mean this type, compared case-insensitively.
    var keywords: [String] {
        switch self {
        case .text: return ["text", "texts"]
        case .link: return ["link", "links", "url", "urls"]
        case .image: return ["image", "images", "photo", "photos", "picture", "pictures"]
        case .screenshot: return ["screenshot", "screenshots"]
        case .file: return ["file", "files"]
        case .color: return ["color", "colors", "colour", "colours"]
        case .other: return ["content"]
        }
    }
    static func matching(keyword: String) -> ContentKind? {
        allCases.first { kind in kind.keywords.contains { $0.compare(keyword, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame } }
    }
}
