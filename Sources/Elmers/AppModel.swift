import AppKit
import Combine
import ServiceManagement
import ElmersCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var history = History() { didSet { refreshVisibleItems() } }
    @Published var query = "" { didSet { refreshVisibleItems() } }
    @Published var kind: ContentKind? { didSet { refreshVisibleItems() } }
    @Published var boardID: UUID? { didSet { refreshVisibleItems() } }
    @Published var selection = ItemSelection()
    @Published private(set) var visibleItems: [ClipboardItem] = []
    @Published var sourceFilter: String? { didSet { refreshVisibleItems() } }
    @Published var afterDate: Date? { didSet { refreshVisibleItems() } }
    @Published var searchIsFocused = false
    @Published var shortcuts = ShortcutSettings() {
        didSet {
            if let error = shortcuts.validationError { shortcuts = oldValue; shortcutValidationError = error; return }
            shortcutValidationError = nil
            saveShortcuts()
        }
    }
    @Published var shortcutConflict: String?
    @Published var shortcutValidationError: String?
    @Published var heldModifiers: KeyModifiers = []
    var shortcutsChanged: (() -> Void)?
    var shortcutRecordingChanged: ((Bool) -> Void)?
    var activateStack: (() -> Void)?
    let undoManager = UndoManager()
    var selectedID: UUID? {
        get { selection.focus }
        set { if let newValue { selection.select(newValue, in: visibleItems.map(\.id)) } else { selection.clear() } }
    }
    @Published var message: String?
    /// Name of the app that will receive a paste, shown in the card context menu as "Paste to …".
    @Published var destinationApp: String?
    @Published var paused = false
    @Published var retentionDays: Int { didSet { defaults.set(retentionDays, forKey: "retentionDays"); prune(); persist() } }
    @Published var directPaste: Bool { didSet { defaults.set(directPaste, forKey: "directPaste") } }
    @Published var soundEffects: Bool { didSet { defaults.set(soundEffects, forKey: "soundEffects"); SoundEffects.shared.enabled = soundEffects } }
    @Published var alwaysPlainText: Bool { didSet { defaults.set(alwaysPlainText, forKey: "alwaysPlainText") } }
    @Published var runInBackground: Bool { didSet { defaults.set(runInBackground, forKey: "runInBackground"); applyActivationPolicy() } }
    @Published var showDuringScreenSharing: Bool { didSet { defaults.set(showDuringScreenSharing, forKey: "showDuringScreenSharing"); sharingChanged?() } }
    /// Mirrors the login item registration; setting it registers or unregisters the app with launchd.
    @Published var openAtLogin: Bool {
        didSet {
            guard !isDemo, openAtLogin != oldValue, openAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do { if openAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { message = "Login item could not be changed: \(error.localizedDescription)"; openAtLogin = oldValue }
        }
    }
    var sharingChanged: (() -> Void)?
    @Published var ignoreConfidential: Bool { didSet { defaults.set(ignoreConfidential, forKey: "ignoreConfidential") } }
    @Published var ignoreTransient: Bool { didSet { defaults.set(ignoreTransient, forKey: "ignoreTransient") } }
    @Published var excludedApps: String { didSet { defaults.set(excludedApps, forKey: "excludedApps") } }
    var showSettings: (() -> Void)?
    var deliver: ((ClipboardItem, Bool) -> Void)?
    var dismiss: (() -> Void)?
    var preview: ((ClipboardItem) -> Void)?
    /// Opens the floating editor for a new item (nil) or an existing one.
    var openEditor: ((ClipboardItem?) -> Void)?
    var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("--demo") }
    private let defaults: UserDefaults
    private let archive: Archive
    private let saveQueue = DispatchQueue(label: "app.elmers.persistence", qos: .utility)
    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount
    private var archiveReadable = true
    private var pauseUntil: Date?
    private var lastPrune = Date()
    private var activationObserver: NSObjectProtocol?
    private var capturePolicy = CapturePolicy(source: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    var canEdit: Bool { archiveReadable }

    var selectedItems: [ClipboardItem] { visibleItems.filter { selection.ids.contains($0.id) } }
    private func refreshVisibleItems() {
        // A query searches all pinboards, matching Paste's global search.
        visibleItems = history.filtered(query: query, kind: kind, boardID: query.isEmpty ? boardID : nil).filter {
            (sourceFilter == nil || $0.source == sourceFilter) && (afterDate == nil || $0.copiedAt >= afterDate!)
        }
        selection.reconcile(in: visibleItems.map(\.id))
    }
    var selected: ClipboardItem? { visibleItems.first { $0.id == selectedID } }

    init() {
        let demo = ProcessInfo.processInfo.arguments.contains("--demo")
        defaults = demo ? UserDefaults(suiteName: "app.elmers.demo")! : .standard
        defaults.register(defaults: ["retentionDays": 30, "directPaste": false, "ignoreConfidential": true, "ignoreTransient": true,
                                      "excludedApps": "com.apple.keychainaccess\ncom.apple.Passwords", "soundEffects": true,
                                      "alwaysPlainText": false, "runInBackground": true, "showDuringScreenSharing": true])
        retentionDays = defaults.integer(forKey: "retentionDays")
        directPaste = defaults.bool(forKey: "directPaste")
        soundEffects = defaults.bool(forKey: "soundEffects")
        alwaysPlainText = defaults.bool(forKey: "alwaysPlainText")
        runInBackground = defaults.bool(forKey: "runInBackground")
        showDuringScreenSharing = defaults.bool(forKey: "showDuringScreenSharing")
        openAtLogin = demo ? false : SMAppService.mainApp.status == .enabled
        ignoreConfidential = defaults.bool(forKey: "ignoreConfidential")
        ignoreTransient = defaults.bool(forKey: "ignoreTransient")
        excludedApps = defaults.string(forKey: "excludedApps") ?? ""
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Elmers")
        archive = Archive(url: directory.appendingPathComponent("history.plist"))
        if !demo {
            do { history = try archive.load(); prune() }
            catch { archiveReadable = false; message = "History could not be opened. The original archive is preserved. \(error.localizedDescription)" }
        }
        if let data = defaults.data(forKey: "shortcuts"), let stored = try? JSONDecoder().decode(ShortcutSettings.self, from: data) { shortcuts = stored }
        undoManager.levelsOfUndo = 30
        SoundEffects.shared.enabled = soundEffects
        refreshVisibleItems()
        selectedID = visibleItems.first?.id
    }
    private func saveShortcuts() {
        if let data = try? JSONEncoder().encode(shortcuts) { defaults.set(data, forKey: "shortcuts") }
        shortcutsChanged?()
    }

    func start() {
        guard !isDemo else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self else { return }
                let source = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                self.poll()
                self.capturePolicy.transitioned(to: source)
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }
    func poll() {
        if let until = pauseUntil, Date() >= until { paused = false; pauseUntil = nil }
        if Date().timeIntervalSince(lastPrune) > 60 { prune(); persist(); lastPrune = Date() }
        let board = NSPasteboard.general
        guard board.changeCount != lastChange else { return }
        let currentChange = board.changeCount
        guard !paused, archiveReadable else { lastChange = currentChange; return }
        let app = NSWorkspace.shared.frontmostApplication
        let excluded = Set(excludedApps.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
        let declaredSource = board.string(forType: .init("org.nspasteboard.source")).flatMap { $0.isEmpty ? nil : $0 }
        let sourceChanged = capturePolicy.sourceChanged(to: app?.bundleIdentifier)
        guard capturePolicy.accepts(currentSource: app?.bundleIdentifier, declaredSource: declaredSource, excluded: excluded) else { lastChange = currentChange; return }
        let sourceID = declaredSource ?? (sourceChanged ? nil : app?.bundleIdentifier)
        let sourceName = sourceID.flatMap { id in NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent } ?? (sourceChanged ? "Unknown App" : app?.localizedName ?? "Unknown App")
        do {
            if let payload = try PasteboardCodec.read(from: board, ignoreConfidential: ignoreConfidential, ignoreTransient: ignoreTransient) {
                let item = history.capture(payload, source: sourceName, sourceBundleID: sourceID)
                SoundEffects.shared.play(.copy)
                if selectedID == nil { selectedID = item.id }
                prune(); persist()
            }
            lastChange = currentChange
        } catch PasteboardCodec.CaptureError.changedDuringRead {
            // Retry the current clipboard generation on the next poll.
        } catch { lastChange = currentChange; message = error.localizedDescription }
    }
    func pause(minutes: Int?) {
        paused = true
        pauseUntil = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
    }
    func resume() { paused = false; pauseUntil = nil }
    func reconcileSelection() { selection.reconcile(in: visibleItems.map(\.id)) }
    func select(_ id: UUID, modifiers: NSEvent.ModifierFlags = [], rightClick: Bool = false) {
        if rightClick, selection.ids.contains(id) { return }
        selection.select(id, extend: modifiers.contains(.shift), toggle: modifiers.contains(.command), in: visibleItems.map(\.id))
    }
    func moveSelection(_ offset: Int, extend: Bool = false) { selection.move(offset, extend: extend, in: visibleItems.map(\.id)) }
    func selectAll() { selection.selectAll(in: visibleItems.map(\.id)) }
    func moveBoard(_ offset: Int) {
        let boards: [UUID?] = [nil] + history.boards.map { Optional($0.id) }
        let current = boards.firstIndex(of: boardID) ?? 0
        query = ""; kind = nil; sourceFilter = nil; afterDate = nil
        boardID = boards[(current + offset + boards.count) % boards.count]
    }
    func selectedAggregate() -> ClipboardItem? {
        let items = selectedItems
        guard let first = items.first else { return nil }
        if items.count == 1 { return first }
        return ClipboardItem(payload: .init(items: items.flatMap { $0.payload.items }), source: first.source, sourceBundleID: first.sourceBundleID)
    }
    func copy(_ item: ClipboardItem, plainText: Bool = false) -> Bool {
        guard PasteboardCodec.write(item.payload, to: .general, plainText: plainText) else {
            message = plainText ? "This item has no plain-text representation." : "The clipboard could not be written."
            return false
        }
        lastChange = NSPasteboard.general.changeCount
        return true
    }
    func activate(_ item: ClipboardItem? = nil, plainText: Bool = false) { if let item = item ?? selectedAggregate() { deliver?(item, plainText || alwaysPlainText) } }
    func applyActivationPolicy() { NSApp.setActivationPolicy(runInBackground ? .accessory : .regular) }
    /// Paste's history limit steps: Day, Week, Month, Year, Forever (0).
    static let retentionSteps = [1, 7, 30, 365, 0]
    func unpinnedItemCount(olderThanRetentionDays days: Int) -> Int {
        guard days > 0 else { return 0 }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        return history.items.filter { $0.boardIDs.isEmpty && $0.copiedAt < cutoff }.count
    }
    func eraseHistory() { deleteItems(history.items.filter { $0.boardIDs.isEmpty }); selection.clear() }
    var excludedBundleIDs: [String] {
        excludedApps.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    func excludeApp(bundleID: String) {
        guard !excludedBundleIDs.contains(bundleID) else { return }
        excludedApps = (excludedBundleIDs + [bundleID]).joined(separator: "\n")
    }
    func includeApp(bundleID: String) { excludedApps = excludedBundleIDs.filter { $0 != bundleID }.joined(separator: "\n") }
    private func rememberUndo(_ action: @escaping @MainActor (AppModel) -> Void) {
        undoManager.registerUndo(withTarget: self) { target in MainActor.assumeIsolated { action(target) } }
    }
    func pin(_ item: ClipboardItem, to board: Pinboard) {
        guard canEdit, !item.boardIDs.contains(board.id) else { return }
        rememberUndo { $0.unpin(item, from: board.id) }; history.pin(item.id, to: board.id); persist()
    }
    func unpin(_ item: ClipboardItem, from board: UUID) {
        guard canEdit, let pinboard = history.boards.first(where: { $0.id == board }) else { return }
        rememberUndo { model in if let current = model.history.items.first(where: { $0.id == item.id }) { model.pin(current, to: pinboard) } }
        history.unpin(item.id, from: board); persist()
    }
    func delete(_ item: ClipboardItem) { deleteItems([item]) }
    func deleteItems(_ items: [ClipboardItem]) {
        guard canEdit else { return }
        let ids = Set(items.map(\.id))
        let items = history.items.filter { ids.contains($0.id) }
        guard !items.isEmpty else { return }
        rememberUndo { $0.restore(items) }
        for item in items { history.delete(item.id) }
        persist()
    }
    private func restore(_ items: [ClipboardItem]) {
        rememberUndo { $0.deleteItems(items) }; history.restoreItems(items); persist()
    }
    func createBoard(name: String) {
        guard canEdit, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let board = history.createBoard(name: name)
        rememberUndo { $0.deleteBoard(board) }
        query = ""; boardID = board.id; persist()
    }
    func renameBoard(_ board: Pinboard, name: String) {
        guard canEdit else { return }
        rememberUndo { model in if let current = model.history.boards.first(where: { $0.id == board.id }) { model.renameBoard(current, name: board.name) } }
        history.renameBoard(board.id, to: name); persist()
    }
    func deleteBoard(_ board: Pinboard) {
        guard canEdit, let index = history.boards.firstIndex(where: { $0.id == board.id }) else { return }
        let pinned = Set(history.items.filter { $0.boardIDs.contains(board.id) }.map(\.id))
        rememberUndo { $0.restore(board, at: index, pins: pinned) }
        history.deleteBoard(board.id); if boardID == board.id { boardID = nil }; persist()
    }
    private func restore(_ board: Pinboard, at index: Int, pins: Set<UUID>) {
        rememberUndo { $0.deleteBoard(board) }; history.restoreBoard(board, at: index, pinnedIDs: pins); persist()
    }
    func recolorBoard(_ board: Pinboard, color: Int) {
        guard canEdit else { return }; history.recolorBoard(board.id, color: color); persist()
    }
    func reorderBoard(_ id: UUID, before target: UUID) { guard canEdit else { return }; history.moveBoard(id, before: target); persist() }
    func newText(_ text: String) { newItem(payload: .text(text)) }
    func newItem(payload: ClipboardPayload) {
        guard canEdit, !payload.text.isEmpty else { return }
        let previous = history.items.first { $0.fingerprint == payload.fingerprint }
        let item = history.capture(payload, source: "Elmers", sourceBundleID: "app.elmers.clipboard")
        if let boardID { history.pin(item.id, to: boardID) }
        if let previous { rememberUndo { $0.restoreItem(previous) } }
        else { rememberUndo { $0.delete(item) } }
        selectedID = item.id; persist()
    }
    private func restoreItem(_ item: ClipboardItem) {
        if let current = history.items.first(where: { $0.id == item.id }) {
            rememberUndo { $0.restoreItem(current) }
        }
        history.replaceItem(item); persist()
    }
    func renameItem(_ item: ClipboardItem, title: String?) {
        guard canEdit else { return }
        rememberUndo { model in if let current = model.history.items.first(where: { $0.id == item.id }) { model.renameItem(current, title: item.title) } }
        history.renameItem(item.id, title: title?.isEmpty == true ? nil : title); persist()
    }
    func editItem(_ item: ClipboardItem, payload: ClipboardPayload) {
        guard canEdit else { return }
        rememberUndo { model in if let current = model.history.items.first(where: { $0.id == item.id }) { model.editItem(current, payload: item.payload) } }
        history.editItem(item.id, payload: payload); persist()
    }
    func undo() { if canEdit { undoManager.undo() } }
    func redo() { if canEdit { undoManager.redo() } }
    private func prune() {
        let cutoff = retentionDays == 0 ? Date.distantPast : Date().addingTimeInterval(-Double(retentionDays) * 86400)
        history.prune(before: cutoff, limit: 2000)
        reconcileSelection()
    }
    private func persist() {
        guard archiveReadable, !isDemo else { return }
        let snapshot = history, archive = archive
        saveQueue.async { [weak self] in
            do { try archive.save(snapshot) }
            catch { let description = error.localizedDescription; Task { @MainActor in self?.message = "History could not be saved: \(description)" } }
        }
    }
    func flush() { saveQueue.sync {} }
}
