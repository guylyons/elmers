import Foundation

/// The filter chips Paste 6.3.11 offers under the search field while a word is typed.
///
/// Paste lists every chip of the filter popover (Type, App, Date, Device, in that order) whose title starts with the
/// word being typed, compared without case: "t" offers Text, Today and This week; "me" offers Messages. Only the start
/// of the whole title counts ("week" and "pro" offer nothing), a plural is not a title ("links" offers nothing), and a
/// chip already in the field is not offered again. The word stays ordinary search text until a chip is accepted.
public enum FilterSuggestions {
    /// The word being typed: the text after the last whitespace. Empty once the query ends in whitespace.
    public static func word(in query: String) -> Substring {
        query[(query.lastIndex(where: \.isWhitespace).map(query.index(after:)) ?? query.startIndex)...]
    }
    /// The chips offered for `query`, in the order of `chips`. `chips` pairs each chip with the title shown for it.
    public static func matching(_ query: String, among chips: [(filter: SearchFilter, title: String)], excluding chosen: SearchFilters) -> [SearchFilter] {
        let word = word(in: query)
        guard !word.isEmpty else { return [] }
        return chips.filter { chip in
            !chosen.contains(chip.filter) && chip.title.range(of: word, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
        }.map(\.filter)
    }
    /// The query once a chip replaces the word being typed; the text before the word stays, as in Paste.
    public static func accepting(_ query: String) -> String {
        String(query[..<word(in: query).startIndex])
    }
}
