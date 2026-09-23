import SwiftUI
import ElmersCore

/// Paste 6.3.11's open search field: a 32-pt capsule a quarter of the panel wide, centered on the panel, holding the
/// magnifier, the filter tokens, the query, a clear button and the filter button that opens the chip popover.
struct SearchField: View {
    @ObservedObject var model: AppModel
    var focused: FocusState<Bool>.Binding
    let width: CGFloat
    static let height: CGFloat = 32

    var body: some View {
        HStack(spacing: 0) {
            // Measured: magnifier ink 9 pt inside the edge, text and tokens from 27 pt.
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(.secondary).offset(y: -1.5)
                .frame(width: 14).padding(.leading, 8).padding(.trailing, 5).accessibilityHidden(true)
            HStack(spacing: 4) {
                ForEach(model.filters.tokens, id: \.self) { token in
                    FilterToken(filter: token, icon: model.sourceIcon(for: token))
                }
                TextField("Search", text: $model.query).textFieldStyle(.plain).font(.system(size: 13)).focused(focused)
                    .onSubmit { focused.wrappedValue = false; model.searchIsFocused = false }
                    .accessibilityLabel("Search")
            }
            if model.hasSearch {
                Button { model.clearSearch(); focused.wrappedValue = true } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(.secondary)
                }.buttonStyle(.plain).frame(width: 18, height: 18).padding(.trailing, 2).help("Clear").accessibilityLabel("Clear")
            }
            Button { model.filtersOpen.toggle() } label: {
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 13)).frame(width: 19, height: 34).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).padding(.trailing, 7).help("Filters (⌘F)").accessibilityLabel("filter")
            .popover(isPresented: $model.filtersOpen, arrowEdge: .top) { FilterPopover(model: model) }
        }
        .frame(width: width, height: Self.height)
        .background(Capsule().fill(Color.primary.opacity(0.09)))
        // The keyboard focus ring: 4 pt of the focus color hugging the outside of the capsule.
        .overlay(Capsule().inset(by: -1.5).stroke(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 4).opacity(focused.wrappedValue ? 1 : 0))
        .contentShape(Capsule())
        .onTapGesture { focused.wrappedValue = true }
    }
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
        .accessibilityElement(children: .combine).accessibilityLabel("Filter: \(filter.title)")
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
                section("App", apps.map(SearchFilter.app))
                section("Date", DateRangeFilter.allCases.map(SearchFilter.date))
                section("Device", [.device(AppModel.deviceName)])
            }.padding(.leading, 16).padding(.top, 10).padding(.bottom, 16).frame(width: 440, alignment: .leading)
        }
        .frame(width: 440, height: 320)
    }
    /// Paste 6.3.11 lists Unknown, Image, Color, File, Link, Text. Elmers adds its Screenshot type after Image.
    static let kinds: [ContentKind] = [.other, .image, .screenshot, .color, .file, .link, .text]
    private var apps: [String] { Array(Set(model.history.items.map(\.source))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }

    private func section(_ title: String, _ chips: [SearchFilter]) -> some View {
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
        case let .kind(kind): return kind == .other ? "Unknown" : kind.rawValue
        case let .app(name): return name
        case let .date(range): return range.title
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

extension AppModel {
    /// The icon of an App chip's source, found through the bundle ID recorded with its captures.
    func sourceIcon(for filter: SearchFilter) -> NSImage? {
        guard case let .app(name) = filter, let id = history.items.first(where: { $0.source == name && $0.sourceBundleID != nil })?.sourceBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return CardImageCache.shared.icon(for: id, url: url)
    }
}
