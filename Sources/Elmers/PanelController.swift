import AppKit
import SwiftUI
import ApplicationServices
import ElmersCore

final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let model: AppModel
    let panel: ClipboardPanel
    private var settingsWindow: NSWindow?
    private var previewWindow: NSWindow?
    let editor = EditorController()
    private var previousApp: NSRunningApplication?
    private var localMonitor: Any?
    private var outsideMonitor: Any?
    private var deliveryGeneration = 0
    /// Screen frame of the menu bar item that toggles the panel. Clicks there are handled by the
    /// status item action, so the outside-click monitor must not hide the panel first.
    var statusItemFrame: (() -> NSRect?)?

    init(model: AppModel) {
        self.model = model
        panel = ClipboardPanel(contentRect: .init(x: 0, y: 0, width: 1100, height: 332), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "Elmers Clipboard History"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1); panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false; panel.delegate = self
        let material = NSVisualEffectView()
        material.material = .hudWindow; material.blendingMode = .behindWindow; material.state = .active
        material.wantsLayer = true; material.layer?.cornerRadius = 24; material.layer?.masksToBounds = true
        let hosting = NSHostingView(rootView: HistoryView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(hosting)
        NSLayoutConstraint.activate([hosting.leadingAnchor.constraint(equalTo: material.leadingAnchor), hosting.trailingAnchor.constraint(equalTo: material.trailingAnchor), hosting.topAnchor.constraint(equalTo: material.topAnchor), hosting.bottomAnchor.constraint(equalTo: material.bottomAnchor)])
        panel.contentView = material
        model.deliver = { [weak self] item, plain in self?.paste(item, plainText: plain) }
        model.dismiss = { [weak self] in self?.hide() }
        model.showSettings = { [weak self] in self?.openSettings() }
        model.preview = { [weak self] in self?.openPreview($0) }
        model.openEditor = { [weak self] in self?.openEditor($0) }
        model.sharingChanged = { [weak self] in self?.applySharing() }
        applySharing()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            var result: NSEvent? = event
            MainActor.assumeIsolated { result = self?.handle(event) }
            return result
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel.attachedSheet == nil else { return }
                if let frame = self.statusItemFrame?(), frame.contains(NSEvent.mouseLocation) { return }
                self.hide(restoreFocus: false)
            }
        }
    }
    func toggle() { panel.isVisible ? hide() : show() }
    /// Paste's "Show during screen sharing" hides the clipboard windows from screen capture when off.
    private func applySharing() {
        let type: NSWindow.SharingType = model.showDuringScreenSharing ? .readOnly : .none
        for window in [panel, settingsWindow, previewWindow, editor.panel] { window?.sharingType = type }
    }
    func show() {
        deliveryGeneration += 1
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        model.destinationApp = previousApp?.localizedName
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let screen { panel.setFrame(NSRect(x: screen.frame.minX + 6, y: screen.frame.minY + 6, width: screen.frame.width - 12, height: 326), display: true) }
        model.reconcileSelection()
        panel.makeKeyAndOrderFront(nil)
        focusResults()
    }
    func hide(restoreFocus: Bool = true) {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        if restoreFocus { previousApp?.activate(options: []) }
    }
    private func paste(_ item: ClipboardItem, plainText: Bool) {
        guard model.copy(item, plainText: plainText) else { return }
        SoundEffects.shared.play(.paste)
        guard model.directPaste else { hide(); return }
        guard AXIsProcessTrusted() else {
            model.message = "Copied. Press ⌘V in your app, or enable Accessibility in Elmers Settings for direct paste."
            return
        }
        guard let target = previousApp, !target.isTerminated else {
            model.message = "Copied. The previous app is unavailable; use ⌘V in your destination."
            return
        }
        deliveryGeneration += 1
        let generation = deliveryGeneration
        hide(restoreFocus: false)
        guard target.activate(options: []) else { model.message = "Copied, but the destination could not be activated."; show(); return }
        let expectedChange = NSPasteboard.general.changeCount
        attemptPaste(to: target, generation: generation, expectedChange: expectedChange, attempts: 12)
    }
    private func attemptPaste(to target: NSRunningApplication, generation: Int, expectedChange: Int, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, generation == self.deliveryGeneration else { return }
            guard NSPasteboard.general.changeCount == expectedChange else { self.model.message = "Clipboard changed before paste. Please try again."; self.show(); return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                if attempts > 0 { self.attemptPaste(to: target, generation: generation, expectedChange: expectedChange, attempts: attempts - 1) }
                else { self.model.message = "Copied, but the destination did not become active. Paste manually with ⌘V."; self.show() }
                return
            }
            guard let source = CGEventSource(stateID: .combinedSessionState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
            down.flags = .maskCommand; up.flags = .maskCommand
            down.postToPid(target.processIdentifier); up.postToPid(target.processIdentifier)
        }
    }
    func openSettings() {
        hide(restoreFocus: false)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 640, height: 564), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Elmers Settings"; window.titleVisibility = .hidden; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model)); window.center(); settingsWindow = window
            applySharing()
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    /// As in Paste, the history panel closes while the editor is open and focus returns to the previous app afterwards.
    func openEditor(_ item: ClipboardItem?) {
        guard model.canEdit else { return }
        hide(restoreFocus: false)
        editor.open(item) { [weak self] payload in
            guard let self else { return }
            if let payload {
                if let item { self.model.editItem(item, payload: payload) } else { self.model.newItem(payload: payload) }
            }
            self.previousApp?.activate(options: [])
        }
    }
    func openPreview(_ item: ClipboardItem) {
        if previewWindow == nil {
            let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 640, height: 460), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.level = .floating; previewWindow = window
            applySharing()
        }
        previewWindow?.title = "\(item.kind.rawValue) — \(item.source)"
        previewWindow?.contentView = NSHostingView(rootView: ItemPreview(item: item))
        previewWindow?.center(); previewWindow?.makeKeyAndOrderFront(nil)
    }
    private func focusResults() {
        model.searchIsFocused = false
        NotificationCenter.default.post(name: .elmersResults, object: nil)
        panel.makeFirstResponder(nil)
    }
    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.window == previewWindow && event.keyCode == 53 { previewWindow?.orderOut(nil); return nil }
        if event.window == editor.panel {
            let stroke = KeyStroke(event.keyCode, KeyModifiers(event.modifierFlags))
            switch stroke {
            case KeyStroke(53): editor.cancel(); return nil
            case KeyStroke(11, .command): editor.toggleBold(); return nil
            case KeyStroke(34, .command): editor.toggleItalic(); return nil
            case KeyStroke(32, .command): editor.toggleUnderline(); return nil
            case KeyStroke(36, .command), KeyStroke(76, .command): editor.confirm(); return nil
            default: return event
            }
        }
        guard event.window == panel, panel.attachedSheet == nil else { return event }
        let stroke = KeyStroke(event.keyCode, KeyModifiers(event.modifierFlags))
        let context: KeyboardContext = model.searchIsFocused ? .search : .results
        if let action = KeyboardRouter.command(for: stroke, context: context, settings: model.shortcuts) {
            switch action {
            case let .move(offset, extend): model.moveSelection(offset, extend: extend)
            case .first: focusResults(); model.selectedID = model.visibleItems.first?.id
            case .last: focusResults(); model.selectedID = model.visibleItems.last?.id
            case .selectAll: model.selectAll()
            case let .paste(plain): model.activate(plainText: plain)
            case let .quickPaste(index, plain):
                if model.visibleItems.indices.contains(index) { model.activate(model.visibleItems[index], plainText: plain) }
            case .copy:
                if let item = model.selectedAggregate(), model.copy(item) { model.message = "Copied to clipboard." }
            case .preview: if let item = model.selected { openPreview(item) }
            case .open:
                if let item = model.selected, [.link, .file].contains(item.kind) {
                    for value in item.text.components(separatedBy: "\n") {
                        if let url = URL(string: value), ["http", "https", "file"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
                    }
                    hide()
                }
            case .rename: NotificationCenter.default.post(name: .elmersRename, object: nil)
            case .edit: NotificationCenter.default.post(name: .elmersEdit, object: nil)
            case .newText: if model.canEdit { NotificationCenter.default.post(name: .elmersNewText, object: nil) }
            case .delete: model.deleteItems(model.selectedItems)
            case .undo: model.undo()
            case .redo: model.redo()
            case .focusSearch: NotificationCenter.default.post(name: .elmersSearch, object: nil)
            case .focusResults: focusResults()
            case .filters: NotificationCenter.default.post(name: .elmersFilters, object: nil)
            case .newBoard: if model.canEdit { NotificationCenter.default.post(name: .elmersNewBoard, object: nil) }
            case .nextBoard: focusResults(); model.moveBoard(1)
            case .previousBoard: focusResults(); model.moveBoard(-1)
            case .pause: model.paused ? model.resume() : model.pause(minutes: nil)
            case .settings: openSettings()
            case .quit: NSApp.terminate(nil)
            case .escape:
                if !model.query.isEmpty || model.kind != nil || model.sourceFilter != nil || model.afterDate != nil {
                    model.query = ""; model.kind = nil; model.sourceFilter = nil; model.afterDate = nil
                    focusResults()
                } else if model.selection.ids.count > 1 { model.selectedID = model.selectedID }
                else { hide() }
            case .showInHistory:
                let id = model.selectedID; model.query = ""; model.kind = nil; model.boardID = nil
                model.sourceFilter = nil; model.afterDate = nil; model.selectedID = id
            }
            return nil
        }
        if panel.firstResponder is NSTextView { return event }
        if stroke.modifiers.isEmpty || stroke.modifiers == .shift, let characters = event.characters,
           !characters.isEmpty, characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 }) {
            model.query += characters
            NotificationCenter.default.post(name: .elmersSearch, object: nil)
            placeSearchCursorAtEnd()
            return nil
        }
        return event
    }
    /// Focusing the search field selects its whole text, so the next typed letter would replace the first one.
    /// Once the field editor takes focus, move the insertion point to the end instead.
    private func placeSearchCursorAtEnd(attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.016)) { [weak self] in
            guard let self else { return }
            if let editor = self.panel.firstResponder as? NSTextView, editor.window == self.panel {
                let end = (editor.string as NSString).length
                editor.setSelectedRange(NSRange(location: end, length: 0))
            } else if attempt < 12 { self.placeSearchCursorAtEnd(attempt: attempt + 1) }
        }
    }
}

extension KeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
    }
}
