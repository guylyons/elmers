import SwiftUI
import ElmersCore

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @FocusState private var searchFocused: Bool
    @State private var boardDialog = false
    @State private var boardName = ""
    @State private var editingBoard: Pinboard?
    @State private var deletingBoard: Pinboard?
    @State private var helpVisible = false
    @State private var hoveredID: UUID?
    @State private var overflowAnchor = MenuAnchor.Holder()

    var body: some View {
        VStack(spacing: 0) {
            toolbar.frame(height: 60)
            if let message = model.message {
                HStack { Text(message).font(.system(size: 12)); Spacer(); Button { model.message = nil } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Close").buttonStyle(.plain) }
                    .padding(.horizontal, 24).padding(.bottom, 6)
            }
            if model.visibleItems.isEmpty { emptyState }
            else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 24) {
                            ForEach(Array(model.visibleItems.enumerated()), id: \.element.id) { index, item in
                                CardView(item: item, selected: model.selection.ids.contains(item.id), ringDimmed: hoveredID != nil && hoveredID != item.id, index: index,
                                         quickPasteNumber: model.quickPasteNumbersShown && index < 9 ? index + 1 : nil,
                                         renaming: model.renamingID == item.id, onRename: { model.finishRenaming(item, title: $0) },
                                         onBeginRename: { if model.canEdit { model.renamingID = item.id } })
                                    .id(item.id)
                                    .onHover { inside in if inside { hoveredID = item.id } else if hoveredID == item.id { hoveredID = nil } }
                                    .onTapGesture(count: 2) { model.activate(item) }
                                    .background(CardMouseObserver(onMouseDown: { event in
                                        model.select(item.id, modifiers: event.modifierFlags, rightClick: event.type == .rightMouseDown); searchFocused = false
                                        // Paste closes an empty search when a card is clicked.
                                        if !model.hasSearch { model.searchOpen = false; model.filtersOpen = false }
                                    },
                                                                  dragItems: { frame, image in
                                        let dragging = DragSupport.draggingItems(for: item, frame: frame, image: image)
                                        if !dragging.isEmpty { DragSupport.draggedItemIDs = [item.id] }
                                        return dragging
                                    }))
                                    .onDrop(of: [.item], isTargeted: nil) { _ in
                                        // Inside a pinboard, a card dropped on another moves in front of it.
                                        guard let board = model.boardID, !model.hasSearch, let ids = DragSupport.draggedItemIDs else { return false }
                                        model.movePinned(ids, before: item.id, in: board); return true
                                    }
                                    .contextMenu { itemMenu(item) }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityLabel("\(item.kind.title), \(item.source), \(String(item.text.prefix(140)))")
                                    .accessibilityValue(model.selection.ids.contains(item.id) ? "Selected" : "")
                                    .accessibilityAction { model.activate(item) }
                            }
                        }.padding(.horizontal, 24).padding(.vertical, 8)
                    }
                    // Paste 6.3.11: cards start 8 pt below the 60-pt toolbar and end 24 pt above the panel's bottom
                    // edge. A taller scroll view would center them vertically instead.
                    .frame(height: CardView.height + 16)
                    // `.hidden` still lets macOS show a scroller when scroll bars are set to always show (or a mouse
                    // is connected); that scroller took the bottom of the card row and clipped the cards. Paste shows none.
                    .scrollIndicators(.never)
                    .onChange(of: model.selectedID) { _, id in
                        if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
                    }
                }
                .id(model.activationGeneration)
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .topLeading) { suggestions }
        .coordinateSpace(name: SearchTextFrame.space)
        .onPreferenceChange(SearchTextFrame.self) { searchTextFrame = $0 }
        .onChange(of: searchFocused) { _, focused in model.searchIsFocused = focused }
        .onChange(of: model.query) { _, _ in model.reconcileSelection() }
        .onChange(of: model.filters) { _, _ in model.reconcileSelection() }
        .onChange(of: model.boardID) { _, _ in model.reconcileSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .elmersSearch)) { _ in openSearch() }
        .onReceive(NotificationCenter.default.publisher(for: .elmersNewBoard)) { _ in editingBoard = nil; boardName = ""; boardDialog = true }
        .onReceive(NotificationCenter.default.publisher(for: .elmersNewText)) { _ in model.openEditor?(nil) }
        .onReceive(NotificationCenter.default.publisher(for: .elmersResults)) { _ in searchFocused = false; model.filtersOpen = false }
        .onReceive(NotificationCenter.default.publisher(for: .elmersFilters)) { _ in model.searchOpen = true; model.filtersOpen.toggle() }
        .onReceive(NotificationCenter.default.publisher(for: .elmersEdit)) { _ in
            if let item = model.selected, !item.text.isEmpty || item.kind.isImage, model.canEdit { model.openEditor?(item) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .elmersRename)) { _ in
            if let item = model.selected, model.canEdit { model.renamingID = item.id }
        }
        .alert(editingBoard == nil ? "New Pinboard" : "Rename Pinboard", isPresented: $boardDialog) {
            TextField("Name", text: $boardName)
            Button("Cancel", role: .cancel) {}
            Button(editingBoard != nil ? "Save" : "Create") {
                if let board = editingBoard { model.renameBoard(board, name: boardName) } else { model.createBoard(name: boardName) }
            }.keyboardShortcut(.defaultAction).disabled(boardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Delete “\(deletingBoard?.name ?? "")”?", isPresented: Binding(get: { deletingBoard != nil }, set: { if !$0 { deletingBoard = nil } })) {
            Button("Delete", role: .destructive) { if let board = deletingBoard { model.deleteBoard(board) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The Pinboard and all its content will be deleted. You can undo this with ⌘Z.") }
        .sheet(isPresented: $helpVisible) { KeyboardHelp() }
    }
    @State private var searchTextFrame = CGRect.zero
    /// Paste's filter suggestions, just under the search field with their titles lined up with the typed word.
    @ViewBuilder private var suggestions: some View {
        let offered = model.filterSuggestions
        if !offered.isEmpty, searchTextFrame != .zero {
            let before = FilterSuggestions.accepting(model.query) as NSString
            let wordX = searchTextFrame.minX + before.size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
            FilterSuggestionList(model: model, suggestions: offered)
                .offset(x: wordX - FilterSuggestionList.titleInset, y: searchTextFrame.midY + SearchField.height / 2)
        }
    }
    private var searching: Bool { model.searchOpen || model.hasSearch }
    /// Follows `searching` without animation: Paste drops the pill names, the selection capsule and the + on the first
    /// frame of the change, while the frames around them animate. Kept apart from `searching` so the views still move.
    @State private var compact = false
    /// The field only exists once search mode is on, so focus it on the next turn.
    /// Opens search mode; the field focuses itself once it has finished growing (see `SearchField`).
    private func openSearch() {
        if searching { searchFocused = true; return }
        model.searchOpen = true
    }
    private var toolbar: some View {
        GeometryReader { geometry in
            ZStack {
                // One set of views in both states, placed by `ToolbarLayout`, so search mode morphs rather than cuts:
                // the field grows out of the magnifier, the pills ride along and lose their names, the + fades.
                ToolbarLayout(open: searching, fieldWidth: (geometry.size.width / 4).rounded()) {
                    SearchField(model: model, focused: $searchFocused, expanded: searching, open: openSearch)
                    boardPills(collapsed: compact)
                    Button { editingBoard = nil; boardName = ""; boardDialog = true } label: { Image(systemName: "plus").font(.system(size: 17)) }
                        .buttonStyle(.plain).frame(width: 34, height: 34).contentShape(Circle()).hoverHighlight(Circle())
                        .help("Create Pinboard (⇧⌘N)").accessibilityLabel("Create Pinboard").disabled(!model.canEdit)
                        .allowsHitTesting(!searching)
                        // Gone the moment search opens; closing, it fades back in over Paste's first two frames.
                        .animation(searching ? nil : .easeOut(duration: 0.06)) { $0.opacity(searching ? 0 : 1) }
                }
                .font(.system(size: 13))
                HStack {
                    if model.paused { Label("Paused", systemImage: "pause.fill").font(.caption).padding(.leading, 24) }
                    Spacer()
                    // A plain button that pops an AppKit menu: a borderless SwiftUI Menu re-renders its label as a
                    // control image with its own padding, which shrank the dots and pushed them off the hover circle.
                    Button { showOverflowMenu() } label: {
                        Image(systemName: "ellipsis").font(.system(size: 18, weight: .light)).frame(width: 34, height: 34).contentShape(Circle())
                    }
                    .buttonStyle(.plain).hoverHighlight(Circle()).background(MenuAnchor(holder: overflowAnchor))
                    .padding(.trailing, 15).help("More").accessibilityLabel("More")
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
            // Paste 6.3.11's timing, fitted to recordings (`TimingCurve.searchOpen` / `.searchClose`).
            .animation(searching ? .timingCurve(0.10, 0.40, 0.60, 0.90, duration: TimingCurve.searchOpenDuration)
                                 : .timingCurve(0.25, 0.40, 0.60, 0.90, duration: TimingCurve.searchCloseDuration), value: searching)
            .onAppear { compact = searching }
            .onChange(of: searching) { _, isSearching in
                var instant = Transaction(); instant.disablesAnimations = true
                withTransaction(instant) { compact = isSearching }
            }
        }
    }
    @ViewBuilder private func boardPills(collapsed: Bool) -> some View {
        boardPill(String(localized: "Clipboard History"), symbol: "clock.arrow.circlepath", color: nil, selected: model.boardID == nil, collapsed: collapsed) { model.boardID = nil }
            .layoutValue(key: CollapsedWidth.self, value: 34)
            .dropDestination(for: String.self) { ids, _ in
                // Dropping a pinboard on the history pill moves it to the front.
                guard let id = ids.first.flatMap(UUID.init), let first = model.history.boards.first?.id else { return false }
                model.reorderBoard(id, before: first); return true
            }
        ForEach(model.history.boards) { board in
            boardPill(board.name, symbol: nil, color: CardView.colors[board.colorIndex % CardView.colors.count], selected: model.boardID == board.id, collapsed: collapsed) { model.boardID = board.id }
                .draggable(board.id.uuidString)
                // A card dropped here is pinned to this pinboard (Paste: pin "by dragging it into a pinboard");
                // another pill dropped here moves before it.
                .onDrop(of: [.item], isTargeted: nil) { providers in
                    if let ids = DragSupport.draggedItemIDs { model.pin(model.history.items.filter { ids.contains($0.id) }, to: board); return true }
                    return DragSupport.droppedBoardID(providers) { id in if id != board.id { model.reorderBoard(id, before: board.id) } }
                }
                .contextMenu {
                    Button("Rename") { editingBoard = board; boardName = board.name; boardDialog = true }
                    Button("Delete…") { deletingBoard = board }
                    Divider()
                    Picker("Color", selection: Binding(get: { board.colorIndex }, set: { model.recolorBoard(board, color: $0) })) {
                        ForEach(0..<Pinboard.colorCount, id: \.self) { index in
                            Label((["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Pink", "Gray"] as [LocalizedStringKey])[index], systemImage: "circle.fill")
                                .tint(CardView.colors[index]).tag(index)
                        }
                    }.pickerStyle(.inline)
                }
        }
    }
    private func showOverflowMenu() {
        guard let anchor = overflowAnchor.view else { return }
        AppMenu.make(model: model) { helpVisible = true }.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: anchor)
    }
    private func boardPill(_ name: String, symbol: String?, color: Color?, selected: Bool, collapsed: Bool, action: @escaping () -> Void) -> some View {
        // Not a Button: a button's click tracking takes the mouse-drag events, so `.draggable` on a pinboard
        // pill never started a drag and pills could not be reordered.
        // While searching, Paste 6.3.11 shows only the icon or color dot, 36 pt apart, with no selection capsule. The
        // pill keeps its name and is narrowed by the toolbar layout, so the name is cut off as search opens.
        HStack(spacing: 6) {
            // The clock's ink is 14 pt wide in Paste; its symbol frame is wider and would push the dots right.
            if let symbol { Image(systemName: symbol).frame(width: 14) }
            if let color { Circle().fill(color).frame(width: 12, height: 12) }
            // Paste drops the names and the selection capsule on the first frame of the change; the pills' frames
            // then animate and clip what is left.
            Text(name).lineLimit(1).opacity(collapsed ? 0 : 1)
        }
        .padding(.leading, 10).padding(.trailing, 12).padding(.vertical, 6)
        // The selection capsule is clipped with the name while the pill narrows or widens, as in Paste's frames.
        .background(Capsule().fill(selected && !collapsed ? Color.primary.opacity(0.1) : Color.clear))
        .fixedSize()
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).clipped()
        .contentShape(Capsule())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { action() }
        .hoverHighlight(Capsule(), suppressed: selected && !collapsed)
        .help(collapsed ? name : "")
    }
    /// Paste 6.3.11's wording: "History is empty", "Pinboard is empty", "Nothing found". Its strings table has no
    /// subtitles for these states; the icon and layout are not yet compared with Paste.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: !model.hasSearch ? "doc.on.clipboard" : "magnifyingglass").font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
            Text(model.hasSearch ? "Nothing found" : model.boardID == nil ? "History is empty" : "Pinboard is empty").font(.system(size: 18, weight: .semibold))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    @ViewBuilder private func itemMenu(_ item: ClipboardItem) -> some View {
        let urls = item.text.components(separatedBy: "\n").compactMap { URL(string: $0) }.filter { ["http", "https", "file"].contains($0.scheme ?? "") }
        if item.kind == .link {
            Button("Open") { urls.forEach { NSWorkspace.shared.open($0) }; model.dismiss?() }.keyboardShortcut("o")
            Divider()
        }
        if item.kind == .file {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls); model.dismiss?() }
            Divider()
        }
        if item.screenshot != nil {
            Button("Show in Finder") { model.useScreenshotOriginal(item, copyFile: false) }
            Button("Copy File") { model.useScreenshotOriginal(item, copyFile: true) }
            Divider()
        }
        Button(model.directPaste ? "Paste to \(model.destinationApp ?? "current app")" : "Paste") { model.activate() }.keyboardShortcut(.return, modifiers: [])
        Button("Copy") { if let aggregate = model.selectedAggregate(), model.copy(aggregate) { model.showCopied?() } }.keyboardShortcut("c")
        Divider()
        Button("Edit") { model.openEditor?(item) }.keyboardShortcut("e").disabled((item.text.isEmpty && !item.kind.isImage) || !model.canEdit)
        if #available(macOS 15.2, *) {
            Button("Writing Tools") { model.openWritingTools?(item) }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(item.text.isEmpty || !model.canEdit)
        }
        Button("Rename") { model.select(item.id); model.renamingID = item.id }.keyboardShortcut("r").disabled(!model.canEdit)
        Button("Delete") { model.deleteItems(model.selectedItems) }.keyboardShortcut(.delete, modifiers: []).disabled(!model.canEdit)
        Divider()
        Menu("Pin") {
            ForEach(model.history.boards) { board in
                let pinned = model.selectedItems.allSatisfy { $0.boardIDs.contains(board.id) }
                Button { pinned ? model.unpin(model.selectedItems, from: board.id) : model.pin(model.selectedItems, to: board) } label: {
                    Label(board.name, systemImage: pinned ? "checkmark.circle.fill" : "circle.fill").tint(CardView.colors[board.colorIndex % CardView.colors.count])
                }
            }
            if !model.history.boards.isEmpty { Divider() }
            Button("Create Pinboard…") { editingBoard = nil; boardName = ""; boardDialog = true }
        }.disabled(!model.canEdit)
        if let board = model.boardID { Button("Unpin") { model.unpin(model.selectedItems, from: board) } }
        Divider()
        Button("Preview") { model.preview?(item) }.keyboardShortcut(.space, modifiers: [])
        if item.kind.isImage, let image = imagePreview(item) { ShareLink("Share…", item: Image(nsImage: image), preview: SharePreview(item.title ?? item.kind.title, image: Image(nsImage: image))) }
        else if let url = urls.first, item.kind == .link { ShareLink("Share…", item: url) }
        else if !item.text.isEmpty { ShareLink("Share…", item: item.text) }
    }
}

extension Notification.Name {
    static let elmersResults = Notification.Name("elmers.results")
    static let elmersFilters = Notification.Name("elmers.filters")
    static let elmersEdit = Notification.Name("elmers.edit")
    static let elmersRename = Notification.Name("elmers.rename")
    static let elmersSearch = Notification.Name("elmers.search")
    static let elmersNewBoard = Notification.Name("elmers.newBoard")
    static let elmersNewText = Notification.Name("elmers.newText")
}

/// Keyboard reference reachable from the overflow menu's Help submenu.
struct KeyboardHelp: View {
    @Environment(\.dismiss) private var dismiss
    /// Set when shown in its own window rather than as a sheet.
    var close: (() -> Void)?
    private let rows: [(LocalizedStringKey, String)] = [
        ("Show or hide Elmers", "⇧⌘V"), ("Move between items", "⇥ / ⇧⇥  ·  ← →"), ("Extend selection", "⇧← / ⇧→"), ("First / last item", "⌘↑ / ⌘↓"),
        ("Paste selected items", "↩"), ("Paste as plain text", "⇧↩"), ("Quick paste", "⌘1…⌘9"), ("Copy", "⌘C"),
        ("Preview", "Space"), ("Open link", "⌘O"), ("Edit / Rename", "⌘E / ⌘R"), ("Writing Tools", "⇧⌘E"), ("Delete", "⌫"), ("Undo / Redo", "⌘Z / ⇧⌘Z"),
        ("Search / Filters", "⌘F"), ("New text item", "⌘N"), ("New pinboard", "⇧⌘N"),
        ("Next / previous pinboard", "⌘→ / ⌘←"), ("Pause capture", "⌘T"), ("Settings", "⌘,")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keyboard Shortcuts").font(.title3.bold())
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                ForEach(rows.indices, id: \.self) { index in
                    GridRow { Text(rows[index].0); Text(rows[index].1).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary) }
                }
            }
            HStack { Spacer(); Button("Done") { if let close { close() } else { dismiss() } }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 420)
    }
}

/// Paste's toolbar hover feedback: a faint capsule on pinboard pills and a faint circle on icon buttons.
private struct HoverHighlight<S: Shape>: ViewModifier {
    let shape: S
    let suppressed: Bool
    @State private var hovered = false
    func body(content: Content) -> some View {
        content
            .background(shape.fill(Color.primary.opacity(hovered && !suppressed ? 0.07 : 0)))
            .onHover { hovered = $0 }
    }
}

extension View {
    func hoverHighlight<S: Shape>(_ shape: S, suppressed: Bool = false) -> some View { modifier(HoverHighlight(shape: shape, suppressed: suppressed)) }
}

/// Exposes the NSView behind a SwiftUI control so an AppKit menu can pop up from it.
struct MenuAnchor: NSViewRepresentable {
    final class Holder { weak var view: NSView? }
    let holder: Holder
    func makeNSView(context: Context) -> NSView { let view = NSView(); holder.view = view; return view }
    func updateNSView(_ view: NSView, context: Context) { holder.view = view }
}

/// How narrow a pinboard pill becomes in search mode: the clock pill 34 pt, a color dot 32 pt (Paste: 36-pt pitch).
private struct CollapsedWidth: LayoutValueKey { static let defaultValue: CGFloat = 32 }

/// Places the search control, the pinboard pills and the + button. Closed, the group is centered with Paste's spacing
/// (7.5 pt between items, 7 pt more around the buttons). Open, the field takes a quarter of the panel, centered, and the
/// pills trail it as icons 36 pt apart, 11.5 pt after its edge. Changing `open` inside an animation moves every subview
/// from one placement to the other.
private struct ToolbarLayout: Layout {
    var open: Bool
    var fieldWidth: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { proposal.replacingUnspecifiedDimensions() }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count >= 2, let search = subviews.first, let plus = subviews.last else { return }
        let pills = subviews.dropFirst().dropLast()
        let y = bounds.midY
        if open {
            var x = bounds.midX - fieldWidth / 2
            search.place(at: CGPoint(x: x, y: y), anchor: .leading, proposal: ProposedViewSize(width: fieldWidth, height: nil))
            x += fieldWidth + 11.5
            for pill in pills {
                let width = pill[CollapsedWidth.self]
                pill.place(at: CGPoint(x: x, y: y), anchor: .leading, proposal: ProposedViewSize(width: width, height: nil))
                x += width + 4
            }
            plus.place(at: CGPoint(x: x + 7, y: y), anchor: .leading, proposal: ProposedViewSize(width: 34, height: 34))
        } else {
            let widths = pills.map { $0.sizeThatFits(.unspecified).width }
            let total = (34 + 14) * 2 + widths.reduce(0, +) + 7.5 * CGFloat(widths.count + 1)
            var x = bounds.midX - total / 2 + 7
            search.place(at: CGPoint(x: x, y: y), anchor: .leading, proposal: ProposedViewSize(width: 34, height: 34))
            x += 34 + 7 + 7.5
            for (pill, width) in zip(pills, widths) {
                pill.place(at: CGPoint(x: x, y: y), anchor: .leading, proposal: ProposedViewSize(width: width, height: nil))
                x += width + 7.5
            }
            plus.place(at: CGPoint(x: x + 7, y: y), anchor: .leading, proposal: ProposedViewSize(width: 34, height: 34))
        }
    }
}
