import AppKit
import Combine
import ServiceManagement
import ElmersCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var history = History() { didSet { refreshVisibleItems() } }
    @Published var query = "" { didSet { refreshVisibleItems(); if !absorbingTypedFilter { DispatchQueue.main.async { self.absorbTypedFilter() } } } }
    @Published var kind: ContentKind? { didSet { if !absorbingTypedFilter { typedFilterWord = nil }; refreshVisibleItems() } }
    /// The word that became the type filter, returned to the field when Backspace removes the filter.
    private var typedFilterWord: String?
    /// The word just put back by Backspace; it is not absorbed again until the user changes it.
    private var restoredFilterWord: String?
    private var absorbingTypedFilter = false
    @Published var boardID: UUID? { didSet { refreshVisibleItems() } }
    @Published var selection = ItemSelection()
    @Published private(set) var visibleItems: [ClipboardItem] = []
    @Published var sourceFilter: String? { didSet { refreshVisibleItems() } }
    @Published var afterDate: Date? { didSet { refreshVisibleItems() } }
    @Published var searchIsFocused = false
    /// A fresh presentation discards the previous viewport, even if selection is unchanged.
    @Published private(set) var activationGeneration = 0
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
    @Published var paused = false { didSet { captureEpoch += 1; refreshScreenshotMonitoring() } }
    @Published var captureScreenshots: Bool { didSet { defaults.set(captureScreenshots, forKey: "captureScreenshots"); refreshScreenshotMonitoring(force: true) } }
    @Published private(set) var screenshotFolder: URL?
    @Published private(set) var screenshotStatus: String?
    @Published private(set) var screenshotNeedsAccess = false
    @Published var retentionDays: Int { didSet { defaults.set(retentionDays, forKey: "retentionDays"); prune(); persist() } }
    @Published var directPaste: Bool { didSet { defaults.set(directPaste, forKey: "directPaste") } }
    @Published var soundEffects: Bool { didSet { defaults.set(soundEffects, forKey: "soundEffects"); SoundEffects.shared.enabled = soundEffects } }
    @Published var alwaysPlainText: Bool { didSet { defaults.set(alwaysPlainText, forKey: "alwaysPlainText") } }
    @Published var runInBackground: Bool { didSet { defaults.set(runInBackground, forKey: "runInBackground"); applyActivationPolicy() } }
    @Published var linkPreviews: Bool { didSet { defaults.set(linkPreviews, forKey: "linkPreviews"); if linkPreviews { fetchLinkPreviews() } } }
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
    @Published var excludedApps: String { didSet { defaults.set(excludedApps, forKey: "excludedApps"); captureEpoch += 1; refreshScreenshotMonitoring(force: true) } }
    var showSettings: (() -> Void)?
    var deliver: ((ClipboardItem, Bool) -> Void)?
    var dismiss: (() -> Void)?
    /// Shows the Copied confirmation overlay (owned by the panel controller).
    var showCopied: (() -> Void)?
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
    private let previewFetcher = LinkPreviewFetcher()
    private var previewsInFlight = Set<UUID>()
    private var recognitionInFlight = Set<UUID>()
    private var captureEpoch = 0
    private var screenshotGeneration = 0
    private var lastScreenshotAllowed: Bool?
    private var lastCaptureAllowed: Bool?
    private let imageCaptureQueue = DispatchQueue(label: "app.elmers.image-identity", qos: .utility)
    private var pendingImageCaptures = 0
    private lazy var screenshotMonitor = ScreenshotMonitor { [weak self] update in self?.receiveScreenshots(update) }
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
    /// A type word in the query becomes the type filter and leaves the field, so what follows searches within that type.
    /// Runs one turn after the edit: the text field ignores a binding change made inside its own update.
    private func absorbTypedFilter() {
        guard kind == nil, !absorbingTypedFilter, query != restoredFilterWord else { return }
        restoredFilterWord = nil
        let parsed = SearchQuery(query)
        guard let typed = parsed.kind else { return }
        absorbingTypedFilter = true
        kind = typed; typedFilterWord = parsed.kindWord
        query = parsed.remainder
        absorbingTypedFilter = false
    }
    /// Backspace on an empty field removes the type filter. A typed word goes back into the field so it can be edited
    /// into something longer ("link" → "linkedin"). Returns false when there is nothing to remove.
    @discardableResult func removeTypedFilter() -> Bool {
        guard kind != nil, query.isEmpty else { return false }
        let word = typedFilterWord
        kind = nil
        if let word { absorbingTypedFilter = true; restoredFilterWord = word; query = word; absorbingTypedFilter = false }
        return true
    }

    init() {
        let demo = ProcessInfo.processInfo.arguments.contains("--demo")
        defaults = demo ? UserDefaults(suiteName: "app.elmers.demo")! : .standard
        defaults.register(defaults: ["retentionDays": 30, "directPaste": false, "ignoreConfidential": true, "ignoreTransient": true,
                                      "excludedApps": "com.apple.keychainaccess\ncom.apple.Passwords", "soundEffects": true,
                                      "alwaysPlainText": false, "runInBackground": true, "showDuringScreenSharing": true, "linkPreviews": false, "captureScreenshots": true])
        captureScreenshots = defaults.bool(forKey: "captureScreenshots")
        retentionDays = defaults.integer(forKey: "retentionDays")
        directPaste = defaults.bool(forKey: "directPaste")
        soundEffects = defaults.bool(forKey: "soundEffects")
        alwaysPlainText = defaults.bool(forKey: "alwaysPlainText")
        runInBackground = defaults.bool(forKey: "runInBackground")
        showDuringScreenSharing = defaults.bool(forKey: "showDuringScreenSharing")
        linkPreviews = defaults.bool(forKey: "linkPreviews")
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
        recognizeImageText()
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
        refreshScreenshotMonitoring()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self else { return }
                let source = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                self.poll()
                self.capturePolicy.transitioned(to: source)
                self.refreshScreenshotMonitoring()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }
    func poll() {
        if let until = pauseUntil, Date() >= until { paused = false; pauseUntil = nil }
        refreshScreenshotMonitoring()
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
                if payload.kind.isImage {
                    captureImage(payload, source: sourceName, sourceID: sourceID)
                } else {
                    let item = history.capture(payload, source: sourceName, sourceBundleID: sourceID)
                    SoundEffects.effect(forCaptured: item.kind).map(SoundEffects.shared.play)
                    if selectedID == nil { selectedID = item.id }
                    prune(); persist()
                    if item.kind == .link { fetchLinkPreviews() }
                }
            }
            lastChange = currentChange
        } catch PasteboardCodec.CaptureError.changedDuringRead {
            // Retry the current clipboard generation on the next poll.
        } catch { lastChange = currentChange; message = error.localizedDescription }
    }
    #if DEBUG
    /// Adds synthetic content for performance checks without going through the pasteboard.
    func captureForChecks(_ payload: ClipboardPayload, source: String) {
        let item = history.capture(payload, source: source)
        if selectedID == nil { selectedID = item.id }
    }
    #endif
    func pause(minutes: Int?) {
        paused = true
        pauseUntil = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
    }
    func resume() { paused = false; pauseUntil = nil }
    private var captureAllowed: Bool {
        !paused && archiveReadable && !excludedBundleIDs.contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
    }
    private func refreshScreenshotMonitoring(force: Bool = false) {
        guard !isDemo else { return }
        let allowed = captureAllowed
        if lastCaptureAllowed != allowed { captureEpoch += 1; lastCaptureAllowed = allowed }
        let enabled = captureScreenshots && allowed
        guard force || enabled != lastScreenshotAllowed else { return }
        lastScreenshotAllowed = enabled; screenshotGeneration += 1
        screenshotMonitor.configure(enabled: enabled, generation: screenshotGeneration, bookmark: defaults.data(forKey: "screenshotFolderAccess"))
    }
    private func receiveScreenshots(_ update: ScreenshotMonitor.Update) {
        guard update.generation == screenshotGeneration else { return }
        screenshotFolder = update.folder; screenshotStatus = update.status; screenshotNeedsAccess = update.needsAccess
        guard captureScreenshots, captureAllowed else { return }
        for capture in update.captures { ingestScreenshot(capture) }
    }
    /// Shared by live observation and synthetic interaction checks; never writes or removes the source file.
    func ingestScreenshot(_ capture: ScreenshotCapture) {
        guard captureScreenshots, captureAllowed else { return }
        let item = history.capture(capture.payload, source: "Screenshot", at: capture.date,
                                   screenshot: capture.origin, imageDigest: capture.imageDigest)
        if selectedID == nil { selectedID = item.id }
        prune(); persist(); recognizeImageText()
    }
    private func captureImage(_ payload: ClipboardPayload, source: String, sourceID: String?) {
        guard pendingImageCaptures < 4 else { message = "Image capture is busy. Please copy this image again in a moment."; return }
        pendingImageCaptures += 1
        let epoch = captureEpoch, capturedAt = Date()
        imageCaptureQueue.async { [weak self] in
            let digest = ScreenshotImage.digest(of: payload)
            Task { @MainActor in
                guard let self else { return }
                self.pendingImageCaptures -= 1
                guard self.captureEpoch == epoch, self.captureAllowed else { return }
                let item = self.history.capture(payload, source: source, sourceBundleID: sourceID, at: capturedAt, imageDigest: digest)
                SoundEffects.effect(forCaptured: item.kind).map(SoundEffects.shared.play)
                if self.selectedID == nil { self.selectedID = item.id }
                self.prune(); self.persist(); self.recognizeImageText()
            }
        }
    }
    func allowScreenshotFolderAccess() {
        guard let folder = screenshotFolder else { return }
        let chooser = NSOpenPanel()
        chooser.canChooseDirectories = true; chooser.canChooseFiles = false; chooser.allowsMultipleSelection = false
        chooser.directoryURL = folder; chooser.prompt = "Allow Access"
        chooser.message = "Choose your current macOS screenshot folder. Elmers will read new screenshots without changing where macOS saves them."
        guard chooser.runModal() == .OK, let chosen = chooser.url else { return }
        guard chosen.standardizedFileURL == folder.standardizedFileURL else {
            screenshotStatus = "Choose the folder configured in macOS Screenshot’s Options. Elmers does not change that destination."; return
        }
        do {
            let bookmark = try chosen.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: "screenshotFolderAccess"); refreshScreenshotMonitoring(force: true)
        } catch { screenshotStatus = "Folder access could not be saved. \(error.localizedDescription)" }
    }
    func useScreenshotOriginal(_ item: ClipboardItem, copyFile: Bool) {
        guard let origin = item.screenshot else { return }
        ScreenshotActions.resolve(origin) { [weak self] url in
            guard let self else { return }
            guard let url else { self.message = "The original screenshot file can’t be found. You can still copy or paste the image saved in Elmers."; return }
            if copyFile {
                let file = ClipboardItem(payload: .init(items: [["public.file-url": Data(url.absoluteString.utf8)]]), source: "Elmers")
                if self.copy(file) { self.showCopied?() }
            } else { NSWorkspace.shared.activateFileViewerSelecting([url]); self.dismiss?() }
        }
    }
    func reconcileSelection() { selection.reconcile(in: visibleItems.map(\.id)) }
    /// Opening the history starts from a known state, as Paste does: no search, no filters, the All pinboard,
    /// and the most recent item selected so Return pastes it straight away.
    func resetForActivation() {
        absorbingTypedFilter = true
        query = ""; kind = nil; typedFilterWord = nil; restoredFilterWord = nil
        absorbingTypedFilter = false
        sourceFilter = nil; afterDate = nil; boardID = nil
        selectedID = visibleItems.first?.id
        activationGeneration += 1
    }
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
    /// Fetches title/image for link items that have never been attempted. Only runs when the user enabled previews.
    func fetchLinkPreviews() {
        guard linkPreviews, canEdit else { return }
        let pending = history.items.filter { $0.kind == .link && $0.linkPreview == nil && !previewsInFlight.contains($0.id) }.prefix(8)
        for item in pending {
            previewsInFlight.insert(item.id)
            previewFetcher.fetch(item.text) { [weak self] preview in
                guard let self else { return }
                self.previewsInFlight.remove(item.id)
                guard self.history.items.contains(where: { $0.id == item.id }) else { return }
                self.history.setLinkPreview(item.id, preview); self.persist()
            }
        }
    }
    /// Runs on-device text recognition for image items that have not been processed yet.
    func recognizeImageText() {
        guard canEdit else { return }
        let pending = history.items.filter { $0.kind.isImage && $0.recognizedText == nil && !recognitionInFlight.contains($0.id) }.prefix(2)
        for item in pending {
            recognitionInFlight.insert(item.id)
            ImageTextRecognizer.recognize(item) { [weak self] text in
                guard let self else { return }
                self.recognitionInFlight.remove(item.id)
                guard self.history.items.contains(where: { $0.id == item.id }) else { return }
                self.history.setRecognizedText(item.id, text ?? ""); self.persist()
            }
        }
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
        if item.kind == .link { fetchLinkPreviews() }
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
