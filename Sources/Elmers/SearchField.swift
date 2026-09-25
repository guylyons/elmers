import SwiftUI
import ElmersCore

/// Paste 6.3.11's search control. Collapsed it is the toolbar's magnifier button; expanded it is the search field, a 32-pt
/// capsule holding the magnifier, the filter tokens, the query, a clear button and the filter button. The toolbar's
/// layout gives it its width, so opening search grows the field out of the button as Paste's does.
struct SearchField: View {
    @ObservedObject var model: AppModel
    var focused: FocusState<Bool>.Binding
    let expanded: Bool
    let open: () -> Void
    static let height: CGFloat = 32
    @State private var hovered = false
    /// True once the field has finished growing. The real text field (an AppKit view, which does not follow SwiftUI's
    /// frame animation) exists only then; while the field grows or shrinks, a SwiftUI stand-in rides along with the
    /// magnifier, as Paste's placeholder does.
    @State private var settled = false
    /// Whether the stand-in text shows. Closing, the stand-in replaces the real field at full opacity, then fades.
    @State private var textShown = false
    /// Set partway through opening, when Paste's focus ring starts closing in.
    @State private var ringArrived = false
    /// True from opening until the settled field has had time to take focus, so the ring doesn't blink in between.
    @State private var awaitingFocus = false

    var body: some View {
        ZStack(alignment: .leading) {
            // Leading: the magnifier, the tokens and the text. Laid out at their natural width and pinned to the field's
            // leading edge, so they ride that edge while the field grows or shrinks, instead of being re-flowed.
            HStack(spacing: 0) {
                // Measured: expanded, magnifier ink 9 pt inside the edge and text from 27 pt; collapsed, a 17-pt
                // magnifier centered in a 34-pt circle.
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(expanded ? .secondary : .primary)
                    .scaleEffect(expanded ? 1 : 17.0 / 13.0).offset(y: expanded ? -1.5 : 0)
                    .frame(width: 14).padding(.leading, expanded ? 8 : 10).padding(.trailing, 5).accessibilityHidden(true)
                HStack(spacing: 4) {
                    ForEach(model.filters.tokens, id: \.self) { token in
                        FilterToken(filter: token, icon: model.sourceIcon(for: token))
                    }
                    // Both stay in the tree, so nothing is inserted or removed mid-animation (a removed field lingered as
                    // a ghost, fading where it stood). Only the one in use shows.
                    ZStack(alignment: .leading) {
                        TextField("Search", text: $model.query).textFieldStyle(.plain).font(.system(size: 13)).focused(focused)
                            .onSubmit { focused.wrappedValue = false; model.searchIsFocused = false }
                            .accessibilityLabel("Search").accessibilityHidden(!settled)
                            .background(GeometryReader { geometry in Color.clear.preference(key: SearchTextFrame.self, value: geometry.frame(in: .named(SearchTextFrame.space))) })
                            .opacity(settled ? 1 : 0).allowsHitTesting(settled)
                        Text(model.query.isEmpty ? String(localized: "Search") : model.query).font(.system(size: 13))
                            .foregroundStyle(model.query.isEmpty ? Color(nsColor: .placeholderTextColor) : .primary).lineLimit(1).fixedSize()
                            // Paste's placeholder fades in right away when opening and is gone within two frames when closing.
                            // The fade is scoped to opacity alone; the text's position follows the field's own curve.
                            .animation(settled ? nil : .easeOut(duration: expanded ? 0.1 : 0.05)) { $0.opacity(!settled && textShown ? 1 : 0) }
                            .accessibilityHidden(true)
                    }
                }
                .padding(.trailing, expanded ? (model.hasSearch ? 46 : 26) : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Trailing: the clear and filter buttons stay on the right edge as it moves; closing, the filter glyph fades
            // only near the end, as in Paste.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if model.hasSearch && expanded {
                    Button { model.clearSearch(); focused.wrappedValue = true } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(.secondary)
                    }.buttonStyle(.plain).frame(width: 18, height: 18).padding(.trailing, 2).help("Clear").accessibilityLabel("Clear")
                }
                Button { model.filtersOpen.toggle() } label: {
                    Image(systemName: "line.3.horizontal.decrease").font(.system(size: 13)).frame(width: 19, height: 34).contentShape(Rectangle())
                        .animation(expanded ? .easeOut(duration: 0.12) : .easeIn(duration: TimingCurve.searchCloseDuration)) { $0.opacity(expanded ? 1 : 0) }
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).padding(.trailing, 7).help("Filters (⌘F)").accessibilityLabel("filter")
                .popover(isPresented: $model.filtersOpen, arrowEdge: .top) { FilterPopover(model: model) }
                .allowsHitTesting(expanded)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).frame(height: expanded ? Self.height : 34)
        .background(Capsule().fill(Color.primary.opacity(expanded ? 0.09 : hovered ? 0.07 : 0)))
        .clipShape(Capsule().inset(by: -6))
        // The keyboard focus ring: 4 pt of the focus color hugging the outside of the capsule. As AppKit's focus ring
        // does in Paste, it arrives partway through opening, closing in on the still-growing field from 12 pt out, soft, as it
        // fades in, and is gone the moment search closes or the field loses focus (never trailing the shrinking field).
        .overlay(FocusRing(spread: ringShown ? 1.5 : 12).stroke(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 4)
            .blur(radius: ringShown ? 0 : 3).opacity(ringShown ? 1 : 0)
            .animation(ringShown ? .easeOut(duration: 0.2) : nil, value: ringShown))
        .contentShape(Capsule())
        .onHover { hovered = $0 }
        .onTapGesture { if expanded { focused.wrappedValue = true } else { open() } }
        .help(expanded ? "" : "Search (⌘F)")
        .accessibilityElement(children: expanded ? .contain : .ignore)
        .accessibilityLabel(expanded ? "" : "Search")
        .accessibilityAddTraits(expanded ? [] : .isButton)
        .onAppear { settled = expanded; textShown = expanded; ringArrived = expanded }
        .onChange(of: expanded) { _, isExpanded in
            // Swapping the real field for the stand-in is never animated: an animated removal left the field's text
            // fading in place, drifting off the magnifier.
            var instant = Transaction(); instant.disablesAnimations = true
            guard isExpanded else {
                focused.wrappedValue = false
                withTransaction(instant) { settled = false; ringArrived = false; awaitingFocus = false }
                DispatchQueue.main.async { textShown = false }
                return
            }
            textShown = true; awaitingFocus = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { if expanded { ringArrived = true } }
            DispatchQueue.main.asyncAfter(deadline: .now() + TimingCurve.searchOpenDuration) {
                guard expanded else { return }
                withTransaction(instant) { settled = true }
                // Focus the real field now that it exists, with the insertion point after anything typed meanwhile.
                DispatchQueue.main.async {
                    focused.wrappedValue = true
                    DispatchQueue.main.async {
                        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
                        }
                    }
                }
                // Normally cleared when focus arrives (below); this only covers focus never arriving, e.g. the panel
                // losing key status meanwhile, so the ring doesn't stay on an unfocused field.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { if !focused.wrappedValue { awaitingFocus = false } }
            }
        }
        // FocusState reports the field's focus a few turns after it is requested. Clearing the wait any earlier left a
        // frame with neither, and the ring blinked out and closed in again from its halo.
        .onChange(of: focused.wrappedValue) { _, isFocused in if isFocused { awaitingFocus = false } }
    }
    /// Until the field settles and takes focus, the ring stands for the focus it is about to get.
    private var ringShown: Bool { expanded && ringArrived && (awaitingFocus || focused.wrappedValue) }
}

/// Where the search field's text sits in the history view, so the filter suggestions can open under the typed word.
struct SearchTextFrame: PreferenceKey {
    static let space = "history"
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { let next = nextValue(); if next != .zero { value = next } }
}

/// Paste 6.3.11's filter suggestions: a small list under the word being typed, one 24-pt row per chip whose title starts
/// with the word. Measured from Paste: the row titles line up with the typed word (37.5 pt in from the list's edge),
/// the list is at least 120 pt wide with 5 pt of padding, the typed part of each title is brighter than the rest, and
/// the highlight (Down, Up or the pointer) fills the row with the accent color.
struct FilterSuggestionList: View {
    @ObservedObject var model: AppModel
    let suggestions: [SearchFilter]
    static let titleInset: CGFloat = 37.5
    var body: some View {
        let word = String(FilterSuggestions.word(in: model.query))
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element) { index, filter in
                let highlighted = model.suggestionIndex == index
                HStack(spacing: 0) {
                    FilterIcon(filter: filter, icon: model.sourceIcon(for: filter), size: 13).frame(width: 16)
                        .foregroundStyle(highlighted ? Color.white : Color.primary)
                    title(filter.title, typed: word.count, highlighted: highlighted).padding(.leading, Self.titleInset - 5 - 8 - 16)
                    Spacer(minLength: 20)
                }
                .padding(.leading, 8).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(highlighted ? Color.accentColor : Color.clear))
                .contentShape(Rectangle())
                .onHover { inside in if inside { model.suggestionIndex = index } else if model.suggestionIndex == index { model.suggestionIndex = nil } }
                .onTapGesture { model.acceptSuggestion(filter) }
                .accessibilityElement(children: .ignore).accessibilityLabel(filter.title)
                .accessibilityAddTraits(highlighted ? [.isButton, .isSelected] : .isButton).accessibilityAction { model.acceptSuggestion(filter) }
            }
        }
        .padding(5).frame(minWidth: 120, alignment: .leading).fixedSize()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }
    /// The typed part of the title in full strength, the rest dimmed, as Paste draws it; white throughout when highlighted.
    private func title(_ title: String, typed: Int, highlighted: Bool) -> Text {
        let split = title.index(title.startIndex, offsetBy: min(typed, title.count))
        return (Text(verbatim: String(title[..<split])).foregroundColor(highlighted ? .white : .primary)
            + Text(verbatim: String(title[split...])).foregroundColor(highlighted ? .white : .secondary)).font(.system(size: 13))
    }
}

/// A capsule drawn `spread` points outside its frame; the spread animates, so the ring can close in on the field.
private struct FocusRing: Shape {
    var spread: CGFloat
    var animatableData: CGFloat { get { spread } set { spread = newValue } }
    func path(in rect: CGRect) -> Path { Capsule().path(in: rect.insetBy(dx: -spread, dy: -spread)) }
}

/// A chosen filter inside the search field: a 16-pt gray capsule with the chip's icon and title.
struct FilterToken: View {
    let filter: SearchFilter
    let icon: NSImage?
    var body: some View {
        HStack(spacing: 3) {
            FilterIcon(filter: filter, icon: icon, size: 10)
            Text(filter.title).font(.system(size: 13)).foregroundStyle(.primary).lineLimit(1)
        }
        .padding(.leading, 6).padding(.trailing, 8).frame(height: 16)
        .background(Capsule().fill(Color.primary.opacity(0.09)))
        .accessibilityElement(children: .combine).accessibilityLabel(String(localized: "Filter: \(filter.title)"))
    }
}

struct FilterIcon: View {
    let filter: SearchFilter
    let icon: NSImage?
    let size: CGFloat
    var body: some View {
        if let icon {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size + 4, height: size + 4)
        } else {
            Image(systemName: filter.symbolName).font(.system(size: size))
        }
    }
}

/// Paste's filter popover: Type, App, Date and Device sections of chips, three to a row. Chips toggle; a chosen chip
/// fills with the accent color and appears as a token in the search field.
struct FilterPopover: View {
    @ObservedObject var model: AppModel
    private let columns = Array(repeating: GridItem(.fixed(126.3), spacing: 6), count: 3)

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                section("Type", Self.kinds.map(SearchFilter.kind))
                section("App", model.filterApps.map(SearchFilter.app))
                section("Date", DateRangeFilter.allCases.map(SearchFilter.date))
                section("Device", [.device(AppModel.deviceName)])
            }.padding(.leading, 16).padding(.top, 10).padding(.bottom, 16).frame(width: 440, alignment: .leading)
        }
        .frame(width: 440, height: 320)
    }
    /// Paste 6.3.11 lists Unknown, Image, Color, File, Link, Text. Elmers adds its Screenshot type after Image.
    static let kinds: [ContentKind] = [.other, .image, .screenshot, .color, .file, .link, .text]

    private func section(_ title: LocalizedStringKey, _ chips: [SearchFilter]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).frame(height: 15)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(chips, id: \.self) { chip in FilterChip(filter: chip, icon: model.sourceIcon(for: chip), selected: model.filters.contains(chip)) { model.filters.toggle(chip) } }
            }.frame(width: 391, alignment: .leading)
        }.padding(.bottom, 18)
    }
}

struct FilterChip: View {
    let filter: SearchFilter
    let icon: NSImage?
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        HStack(spacing: 6) {
            FilterIcon(filter: filter, icon: icon, size: 12).frame(width: 16)
            Text(filter.title).font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.leading, 11).padding(.trailing, 8).frame(height: 28)
        .background(Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(hovered ? 0.12 : 0.07)))
        .contentShape(Capsule())
        .onTapGesture(perform: action)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine).accessibilityLabel(filter.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton).accessibilityAction { action() }
    }
}

extension SearchFilter {
    var title: String {
        switch self {
        case let .kind(kind): return kind.title
        case let .app(name): return name
        case let .date(range): return range.localizedTitle
        case let .device(name): return name
        }
    }
    var symbolName: String {
        switch self {
        case let .kind(kind): return kind == .other ? "questionmark.square" : kind.symbolName
        case .app: return "app"
        case .date: return "calendar"
        case .device: return "laptopcomputer"
        }
    }
}

extension DateRangeFilter {
    var localizedTitle: String {
        switch self {
        case .today: return String(localized: "Today")
        case .yesterday: return String(localized: "Yesterday")
        case .thisWeek: return String(localized: "This week")
        case .lastWeek: return String(localized: "Last week")
        case .last30Days: return String(localized: "Last 30 days")
        }
    }
}

extension AppModel {
    /// The icon of an App chip's source, found through the bundle ID recorded with its captures.
    func sourceIcon(for filter: SearchFilter) -> NSImage? {
        guard case let .app(name) = filter, let id = history.items.first(where: { $0.source == name && $0.sourceBundleID != nil })?.sourceBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return CardImageCache.shared.icon(for: id, url: url)
    }
}
