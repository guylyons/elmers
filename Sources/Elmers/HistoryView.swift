import SwiftUI
import ElmersCore

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @State private var searchVisible = false
    @FocusState private var searchFocused: Bool
    @State private var boardDialog = false
    @State private var boardName = ""
    @State private var editingBoard: Pinboard?
    @State private var textDialog = false
    @State private var newText = ""
    @State private var editingItem: ClipboardItem?
    @State private var renamingItem: ClipboardItem?
    @State private var filtersVisible = false

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
                        LazyHStack(spacing: 22) {
                            ForEach(Array(model.visibleItems.enumerated()), id: \.element.id) { index, item in
                                CardView(item: item, selected: model.selection.ids.contains(item.id), index: index)
                                    .id(item.id)
                                    .onTapGesture(count: 2) { model.activate(item) }
                                    .background(CardMouseObserver { event in model.select(item.id, modifiers: event.modifierFlags, rightClick: event.type == .rightMouseDown); searchFocused = false })
                                    .contextMenu { itemMenu(item) }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityLabel("\(item.kind.rawValue), \(item.source), \(String(item.text.prefix(140)))")
                                    .accessibilityValue(model.selection.ids.contains(item.id) ? "Selected" : "")
                                    .accessibilityAction { model.activate(item) }
                            }
                        }.padding(.horizontal, 28).padding(.vertical, 5)
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
        .onReceive(NotificationCenter.default.publisher(for: .elmersNewText)) { _ in editingItem = nil; newText = ""; textDialog = true }
        .onReceive(NotificationCenter.default.publisher(for: .elmersResults)) { _ in searchFocused = false; filtersVisible = false }
        .onReceive(NotificationCenter.default.publisher(for: .elmersFilters)) { _ in searchVisible = true; filtersVisible.toggle() }
        .onReceive(NotificationCenter.default.publisher(for: .elmersEdit)) { _ in
            if let item = model.selected, !item.text.isEmpty, model.canEdit { editingItem = item; newText = item.text; textDialog = true }
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
        .sheet(isPresented: $textDialog) {
            VStack(alignment: .leading, spacing: 16) {
                Text(editingItem == nil ? "New Text Item" : "Edit Item").font(.title2.bold())
                TextEditor(text: $newText).font(.body).frame(width: 440, height: 220).border(.quaternary)
                HStack { Spacer(); Button("Cancel") { textDialog = false }; Button("Save") { if let item = editingItem { model.editItem(item, payload: .text(newText)) } else { model.newText(newText) }; textDialog = false }.keyboardShortcut(.defaultAction).disabled(newText.isEmpty) }
            }.padding(24)
        }
    }
    private var toolbar: some View {
        ZStack {
            HStack(spacing: 9) {
                if searchVisible || !model.query.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search clipboard history", text: $model.query).textFieldStyle(.plain).focused($searchFocused)
                            .onSubmit { searchFocused = false; model.searchIsFocused = false }
                        Button { model.query = ""; searchVisible = false; searchFocused = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                    }.padding(.horizontal, 10).frame(width: 240, height: 30).background(.primary.opacity(0.06), in: Capsule())
                } else {
                    Button { searchVisible = true; searchFocused = true } label: { Image(systemName: "magnifyingglass").font(.system(size: 17)) }
                        .buttonStyle(.plain).frame(width: 32, height: 32).help("Search (⌘F)")
                }
                if searchVisible || model.kind != nil {
                    Button { filtersVisible.toggle() } label: {
                        Image(systemName: model.kind == nil && model.sourceFilter == nil && model.afterDate == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    }.buttonStyle(.plain).frame(width: 24).help("Filters (⌘F)")
                        .popover(isPresented: $filtersVisible) { filterPanel }

                }
                boardPill("Clipboard History", symbol: "clock.arrow.circlepath", color: nil, selected: model.boardID == nil) { model.boardID = nil }
                ForEach(model.history.boards) { board in
                    boardPill(board.name, symbol: nil, color: CardView.colors[board.colorIndex % CardView.colors.count], selected: model.boardID == board.id) { model.boardID = board.id }
                        .contextMenu {
                            Button("Rename…") { renamingItem = nil; editingBoard = board; boardName = board.name; boardDialog = true }
                            Button("Delete Pinboard", role: .destructive) { model.deleteBoard(board) }
                        }
                }
                Button { renamingItem = nil; editingBoard = nil; boardName = ""; boardDialog = true } label: { Image(systemName: "plus").font(.system(size: 17)) }
                    .buttonStyle(.plain).frame(width: 32, height: 32).help("Create Pinboard (⇧⌘N)").disabled(!model.canEdit)
            }.font(.system(size: 12)).padding(.horizontal, 60)
            HStack {
                if model.paused { Label("Paused", systemImage: "pause.fill").font(.caption).padding(.leading, 24) }
                Spacer()
                Menu {
                    Button("New Text Item…") { editingItem = nil; newText = ""; textDialog = true }.disabled(!model.canEdit)
                    Button("Settings…") { model.showSettings?() }
                    Divider()
                    if model.paused { Button("Resume Capture") { model.resume() } }
                    else {
                        Menu("Pause Capture") {
                            Button("Pause") { model.pause(minutes: nil) }
                            ForEach([15, 30, 60, 180, 480], id: \.self) { minutes in Button("For \(minutes < 60 ? "\(minutes) minutes" : "\(minutes / 60) hours")") { model.pause(minutes: minutes) } }
                        }
                    }
                    Divider()
                    Button("Quit Elmers") { NSApp.terminate(nil) }
                } label: { Image(systemName: "ellipsis").font(.system(size: 19)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28).padding(.trailing, 22).help("More")
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
        }.buttonStyle(.plain)
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
        Button("Paste") { model.activate() }
        Button("Paste as Plain Text") { model.activate(plainText: true) }.disabled(item.text.isEmpty)
        Button("Copy") { if let aggregate = model.selectedAggregate(), model.copy(aggregate) { model.message = "Copied to clipboard." } }
        Button("Edit") { editingItem = item; newText = item.text; textDialog = true }.disabled(item.text.isEmpty || !model.canEdit)
        Button("Rename") { renamingItem = item; boardName = item.title ?? ""; boardDialog = true }.disabled(!model.canEdit)
        Button("Preview") { model.preview?(item) }
        Divider()
        Menu("Pin to") {
            ForEach(model.history.boards) { board in Button(board.name) { model.selectedItems.forEach { model.pin($0, to: board) } } }
            if model.history.boards.isEmpty { Text("Create a pinboard with + first") }
        }
        if let board = model.boardID { Button("Remove from Pinboard") { model.selectedItems.forEach { model.unpin($0, from: board) } } }
        Divider()
        Button("Delete", role: .destructive) { model.deleteItems(model.selectedItems) }
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
