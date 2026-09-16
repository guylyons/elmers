import SwiftUI
import ElmersCore

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @State private var searchVisible = false
    @FocusState private var searchFocused: Bool
    @State private var boardDialog = false
    @State private var boardName = ""
    @State private var editingBoard: Pinboard?
    @State private var renamingItem: ClipboardItem?
    @State private var filtersVisible = false
    @State private var deletingBoard: Pinboard?
    @State private var helpVisible = false
    @State private var hoveredID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            toolbar.frame(height: 60)
            if let message = model.message {
                HStack { Text(message).font(.system(size: 12)); Spacer(); Button { model.message = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                    .padding(.horizontal, 24).padding(.bottom, 6)
            }
            if model.visibleItems.isEmpty { emptyState }
            else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 21) {
                            ForEach(Array(model.visibleItems.enumerated()), id: \.element.id) { index, item in
                                CardView(item: item, selected: model.selection.ids.contains(item.id), ringDimmed: hoveredID != nil && hoveredID != item.id, index: index)
                                    .id(item.id)
                                    .onHover { inside in if inside { hoveredID = item.id } else if hoveredID == item.id { hoveredID = nil } }
                                    .onTapGesture(count: 2) { model.activate(item) }
                                    .onDrag { DragSupport.itemProvider(for: item) }
                                    .background(CardMouseObserver { event in model.select(item.id, modifiers: event.modifierFlags, rightClick: event.type == .rightMouseDown); searchFocused = false })
                                    .contextMenu { itemMenu(item) }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityLabel("\(item.kind.rawValue), \(item.source), \(String(item.text.prefix(140)))")
                                    .accessibilityValue(model.selection.ids.contains(item.id) ? "Selected" : "")
                                    .accessibilityAction { model.activate(item) }
                            }
                        }.padding(.horizontal, 28).padding(.vertical, 6)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: model.selectedID) { _, id in
                        if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .onChange(of: searchFocused) { _, focused in model.searchIsFocused = focused }
        .onChange(of: model.query) { _, _ in model.reconcileSelection() }
        .onChange(of: model.kind) { _, _ in model.reconcileSelection() }
        .onChange(of: model.boardID) { _, _ in model.reconcileSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .elmersSearch)) { _ in searchVisible = true; searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .elmersNewBoard)) { _ in renamingItem = nil; editingBoard = nil; boardName = ""; boardDialog = true }
        .onReceive(NotificationCenter.default.publisher(for: .elmersNewText)) { _ in model.openEditor?(nil) }
        .onReceive(NotificationCenter.default.publisher(for: .elmersResults)) { _ in searchFocused = false; filtersVisible = false }
        .onReceive(NotificationCenter.default.publisher(for: .elmersFilters)) { _ in searchVisible = true; filtersVisible.toggle() }
        .onReceive(NotificationCenter.default.publisher(for: .elmersEdit)) { _ in
            if let item = model.selected, !item.text.isEmpty, model.canEdit { model.openEditor?(item) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .elmersRename)) { _ in
            if let item = model.selected, model.canEdit { renamingItem = item; boardName = item.title ?? ""; boardDialog = true }
        }
        .alert(renamingItem != nil ? "Rename Item" : (editingBoard == nil ? "New Pinboard" : "Rename Pinboard"), isPresented: $boardDialog) {
            TextField("Name", text: $boardName)
            Button("Cancel", role: .cancel) {}
            Button(renamingItem != nil || editingBoard != nil ? "Save" : "Create") {
                if let item = renamingItem { model.renameItem(item, title: boardName) } else if let board = editingBoard { model.renameBoard(board, name: boardName) } else { model.createBoard(name: boardName) }
            }.keyboardShortcut(.defaultAction).disabled(boardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Delete “\(deletingBoard?.name ?? "")”?", isPresented: Binding(get: { deletingBoard != nil }, set: { if !$0 { deletingBoard = nil } })) {
            Button("Delete", role: .destructive) { if let board = deletingBoard { model.deleteBoard(board) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The Pinboard will be deleted. Its items stay in Clipboard History. You can undo this with ⌘Z.") }
        .sheet(isPresented: $helpVisible) { KeyboardHelp() }
    }
    private var toolbar: some View {
        ZStack {
            HStack(spacing: 9) {
                if searchVisible || !model.query.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        if let activeKind = model.kind {
                            // Paste keeps active filters visible inside the search field; Backspace on an empty field removes it.
                            Label(activeKind.rawValue, systemImage: activeKind.symbolName).font(.system(size: 11, weight: .medium)).labelStyle(.titleAndIcon)
                                .padding(.horizontal, 7).padding(.vertical, 3).background(Color.accentColor.opacity(0.18), in: Capsule())
                                .accessibilityLabel("Type filter: \(activeKind.rawValue)").help("Showing \(activeKind.searchNoun) · ⌫ removes")
                        }
                        TextField(model.kind.map { "Search \($0.searchNoun)" } ?? "Search clipboard history", text: $model.query).textFieldStyle(.plain).focused($searchFocused)
                            .onSubmit { searchFocused = false; model.searchIsFocused = false }
                        Button { model.query = ""; model.kind = nil; searchVisible = false; searchFocused = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                    }.padding(.horizontal, 10).frame(width: 240, height: 30).background(.primary.opacity(0.06), in: Capsule())
                } else {
                    Button { searchVisible = true; searchFocused = true } label: { Image(systemName: "magnifyingglass").font(.system(size: 17)) }
                        .buttonStyle(.plain).frame(width: 34, height: 34).hoverHighlight(Circle()).help("Search (⌘F)")
                }
                if searchVisible || model.kind != nil {
                    Button { filtersVisible.toggle() } label: {
                        Image(systemName: model.kind == nil && model.sourceFilter == nil && model.afterDate == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    }.buttonStyle(.plain).frame(width: 28, height: 28).hoverHighlight(Circle()).help("Filters (⌘F)")
                        .popover(isPresented: $filtersVisible) { filterPanel }

                }
                boardPill("Clipboard History", symbol: "clock.arrow.circlepath", color: nil, selected: model.boardID == nil) { model.boardID = nil }
                    .dropDestination(for: String.self) { ids, _ in
                        // Dropping a pinboard on the history pill moves it to the front.
                        guard let id = ids.first.flatMap(UUID.init), let first = model.history.boards.first?.id else { return false }
                        model.reorderBoard(id, before: first); return true
                    }
                ForEach(model.history.boards) { board in
                    boardPill(board.name, symbol: nil, color: CardView.colors[board.colorIndex % CardView.colors.count], selected: model.boardID == board.id) { model.boardID = board.id }
                        .draggable(board.id.uuidString)
                        .dropDestination(for: String.self) { ids, _ in
                            guard let id = ids.first.flatMap(UUID.init), id != board.id else { return false }
                            model.reorderBoard(id, before: board.id); return true
                        }
                        .contextMenu {
                            Button("Rename") { renamingItem = nil; editingBoard = board; boardName = board.name; boardDialog = true }
                            Button("Delete…") { deletingBoard = board }
                            Divider()
                            Picker("Color", selection: Binding(get: { board.colorIndex }, set: { model.recolorBoard(board, color: $0) })) {
                                ForEach(0..<Pinboard.colorCount, id: \.self) { index in
                                    Label(["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Pink", "Gray"][index], systemImage: "circle.fill")
                                        .tint(CardView.colors[index]).tag(index)
                                }
                            }.pickerStyle(.inline)
                        }
                }
                Button { renamingItem = nil; editingBoard = nil; boardName = ""; boardDialog = true } label: { Image(systemName: "plus").font(.system(size: 17)) }
                    .buttonStyle(.plain).frame(width: 34, height: 34).hoverHighlight(Circle()).help("Create Pinboard (⇧⌘N)").disabled(!model.canEdit)
            }.font(.system(size: 12)).padding(.horizontal, 60)
            HStack {
                if model.paused { Label("Paused", systemImage: "pause.fill").font(.caption).padding(.leading, 24) }
                Spacer()
                Menu {
                    Button("About Elmers") { NSApp.orderFrontStandardAboutPanel(nil); NSApp.activate(ignoringOtherApps: true) }
                    Divider()
                    Button("New Text Item") { model.openEditor?(nil) }.keyboardShortcut("n").disabled(!model.canEdit)
                    Button("Settings…") { model.showSettings?() }.keyboardShortcut(",")
                    Divider()
                    Menu("Help") { Button("Keyboard Shortcuts") { helpVisible = true } }
                    Divider()
                    if model.paused { Button("Resume Elmers") { model.resume() } }
                    else {
                        Menu("Pause Elmers") {
                            Button("Pause") { model.pause(minutes: nil) }.keyboardShortcut("t")
                            ForEach([15, 30, 60, 180, 480], id: \.self) { minutes in Button("Pause for \(minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h")") { model.pause(minutes: minutes) } }
                        }
                    }
                    Button("Quit Elmers") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "ellipsis").font(.system(size: 19)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 34, height: 34).hoverHighlight(Circle()).padding(.trailing, 19).help("More")
            }
        }
    }
    private func boardPill(_ name: String, symbol: String?, color: Color?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol) }
                if let color { Circle().fill(color).frame(width: 10, height: 10) }
                Text(name).lineLimit(1)
            }.padding(.horizontal, 10).padding(.vertical, 6).background(selected ? Color.primary.opacity(0.1) : Color.clear, in: Capsule())
        }.buttonStyle(.plain).hoverHighlight(Capsule(), suppressed: selected)
    }
    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Type").font(.headline)
            Picker("Content", selection: $model.kind) {
                Text("All Types").tag(nil as ContentKind?)
                ForEach(ContentKind.allCases) { Text($0.rawValue).tag(Optional($0)) }
            }
            Text("App").font(.headline)
            Picker("Source", selection: $model.sourceFilter) {
                Text("All Apps").tag(nil as String?)
                ForEach(Array(Set(model.history.items.map(\.source))).sorted(), id: \.self) { Text($0).tag(Optional($0)) }
            }
            Text("Date").font(.headline)
            HStack {
                Button("Any time") { model.afterDate = nil }
                Button("Today") { model.afterDate = Calendar.current.startOfDay(for: Date()) }
                Button("This week") { model.afterDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) }
            }
            Button("Clear filters") { model.kind = nil; model.sourceFilter = nil; model.afterDate = nil }
        }.padding(20).frame(width: 320)
    }
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass").font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
            Text(model.query.isEmpty ? (model.boardID == nil ? "Your clipboard, remembered." : "Keep your favorites here.") : "No matching items").font(.system(size: 18, weight: .semibold))
            Text(model.query.isEmpty ? (model.boardID == nil ? "Copy something in any app to get started." : "Right-click a clipboard item to pin it here.") : "Try another search or content type.").font(.system(size: 13)).foregroundStyle(.secondary)
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
        Button(model.directPaste ? "Paste to \(model.destinationApp ?? "current app")" : "Paste") { model.activate() }.keyboardShortcut(.return, modifiers: [])
        Button("Copy") { if let aggregate = model.selectedAggregate(), model.copy(aggregate) { model.showCopied?() } }.keyboardShortcut("c")
        Divider()
        Button("Edit") { model.openEditor?(item) }.keyboardShortcut("e").disabled(item.text.isEmpty || !model.canEdit)
        Button("Rename") { renamingItem = item; boardName = item.title ?? ""; boardDialog = true }.keyboardShortcut("r").disabled(!model.canEdit)
        Button("Delete") { model.deleteItems(model.selectedItems) }.keyboardShortcut(.delete, modifiers: []).disabled(!model.canEdit)
        Divider()
        Menu("Pin") {
            ForEach(model.history.boards) { board in
                let pinned = model.selectedItems.allSatisfy { $0.boardIDs.contains(board.id) }
                Button { model.selectedItems.forEach { pinned ? model.unpin($0, from: board.id) : model.pin($0, to: board) } } label: {
                    Label(board.name, systemImage: pinned ? "checkmark.circle.fill" : "circle.fill").tint(CardView.colors[board.colorIndex % CardView.colors.count])
                }
            }
            if !model.history.boards.isEmpty { Divider() }
            Button("Create Pinboard…") { renamingItem = nil; editingBoard = nil; boardName = ""; boardDialog = true }
        }.disabled(!model.canEdit)
        if let board = model.boardID { Button("Unpin") { model.selectedItems.forEach { model.unpin($0, from: board) } } }
        Divider()
        Button("Preview") { model.preview?(item) }.keyboardShortcut(.space, modifiers: [])
        if item.kind == .image, let image = imagePreview(item) { ShareLink("Share…", item: Image(nsImage: image), preview: SharePreview(item.title ?? "Image", image: Image(nsImage: image))) }
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
    private let rows: [(String, String)] = [
        ("Show or hide Elmers", "⇧⌘V"), ("Move between items", "← →  ·  ⇧ extends"), ("First / last item", "⌘↑ / ⌘↓"),
        ("Paste selected items", "↩"), ("Paste as plain text", "⇧↩"), ("Quick paste", "⌘1…⌘9"), ("Copy", "⌘C"),
        ("Preview", "Space"), ("Open link", "⌘O"), ("Edit / Rename", "⌘E / ⌘R"), ("Delete", "⌫"), ("Undo / Redo", "⌘Z / ⇧⌘Z"),
        ("Search / Filters", "⌘F  ·  ⇥ switches focus"), ("New text item", "⌘N"), ("New pinboard", "⇧⌘N"),
        ("Next / previous pinboard", "⌘→ / ⌘←"), ("Pause capture", "⌘T"), ("Settings", "⌘,")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keyboard Shortcuts").font(.title3.bold())
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                ForEach(rows, id: \.0) { row in
                    GridRow { Text(row.0); Text(row.1).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary) }
                }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
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
