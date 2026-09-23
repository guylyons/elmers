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
    /// The glass panel and the history above it. The window stays put on the screen's bottom edge while this
    /// view's frame slides.
    private var glass: NSView!
    private var restingScreen: NSScreen?
    /// False from the moment `hide()` starts, even while the slide-out is still on screen.
    private(set) var isShown = false
    private var transitionGeneration = 0
    static let windowHeight: CGFloat = 332
    static let inset: CGFloat = 8
    static let cornerRadius: CGFloat = 25
    /// Measured from 60 fps recordings of Paste 6.3.11: the panel rises 332 pt in 0.15 s, covering over half the
    /// distance in the first 20 ms, and leaves in 0.18 s with a gentle ease-in-out.
    static let showDuration: TimeInterval = 0.15
    static let hideDuration: TimeInterval = 0.18
    private var slideLink: CADisplayLink?
    private var slideStart: CFTimeInterval = 0
    private var slideFrom: CGFloat = 0, slideTo: CGFloat = 0
    private var slideDuration: TimeInterval = 0
    private var slideCurve = TimingCurve.panelIn
    private var slideCompletion: (() -> Void)?
    private var settingsWindow: NSWindow?
    private var previewWindow: NSWindow?
    private var helpWindow: NSWindow?
    let editor = EditorController()
    let copiedHUD = CopiedHUD()
    private var previousApp: NSRunningApplication?
    private var localMonitor: Any?
    private var outsideMonitor: Any?
    private var deliveryGeneration = 0
    /// Screen frame of the menu bar item that toggles the panel. Clicks there are handled by the
    /// status item action, so the outside-click monitor must not hide the panel first.
    var statusItemFrame: (() -> NSRect?)?

    init(model: AppModel) {
        self.model = model
        panel = ClipboardPanel(contentRect: .init(x: 0, y: 0, width: 1100, height: Self.windowHeight), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = String(localized: "Elmers Clipboard History")
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1); panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false; panel.delegate = self
        panel.animationBehavior = .none // the slide is the only transition; no system fade on order in/out
        // Paste 6.3.11 keeps a full-width window flush with the bottom of the screen and slides a Liquid Glass
        // panel inside it, inset 8 pt from the sides and bottom and flush with the window's top edge.
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1100, height: Self.windowHeight))
        let hosting = NSHostingView(rootView: HistoryView(model: model))
        glass = Self.makeGlass(content: hosting)
        glass.frame = NSRect(x: Self.inset, y: Self.inset, width: root.bounds.width - 2 * Self.inset, height: root.bounds.height - Self.inset)
        glass.autoresizingMask = [.width, .height]
        root.addSubview(glass)
        panel.contentView = root
        model.deliver = { [weak self] item, plain in self?.paste(item, plainText: plain) }
        model.dismiss = { [weak self] in self?.hide() }
        model.showCopied = { [weak self] in self?.showCopied() }
        copiedHUD.openSettings = { [weak self] in self?.openSettings() }
        model.showSettings = { [weak self] in self?.openSettings() }
        model.preview = { [weak self] in self?.openPreview($0) }
        model.openEditor = { [weak self] in self?.openEditor($0) }
        model.openWritingTools = { [weak self] in self?.openWritingTools($0) }
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
    func toggle() { isShown ? hide() : show() }
    /// The glass is only the panel's background, with the history view layered above it rather than inside it:
    /// an `NSGlassEffectView.contentView` is drawn vibrant, which turned the toolbar's 85 % label color pure white
    /// and brightened pinboard colors, unlike Paste's.
    private static func makeGlass(content: NSView) -> NSView {
        let container = NSView()
        let background: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular; glass.cornerRadius = cornerRadius
            background = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .hudWindow; material.blendingMode = .behindWindow; material.state = .active
            material.wantsLayer = true; material.layer?.cornerRadius = cornerRadius; material.layer?.masksToBounds = true
            background = material
        }
        for view in [background, content] {
            view.frame = container.bounds; view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        return container
    }
    private var animatesTransitions: Bool { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Slides the glass panel to `visible` (its resting place, inset from the window's sides and bottom) or one
    /// window-height lower, below the screen edge. Liquid Glass is composited at its view's model frame, so a
    /// Core Animation move would leave the glass behind; like Paste's own animator, the frame is stepped on every
    /// display refresh instead. The window itself stays still: fast window moves were not composited in step.
    private func slide(visible: Bool, completion: (() -> Void)? = nil) {
        let target = visible ? Self.inset : Self.inset - Self.windowHeight
        slideLink?.invalidate(); slideLink = nil
        slideCompletion = nil
        let from = glass.frame.origin.y
        // Driven by the screen the panel rests on, so the refresh rate is that display's.
        guard animatesTransitions, from != target, let screen = restingScreen ?? panel.screen ?? NSScreen.main else {
            glass.setFrameOrigin(NSPoint(x: Self.inset, y: target)); completion?(); return
        }
        slideFrom = from; slideTo = target
        slideDuration = visible ? Self.showDuration : Self.hideDuration
        slideCurve = visible ? .panelIn : .panelOut
        slideCompletion = completion
        // Opening the history lays out the freshly reset cards during the next refresh; starting the clock a refresh
        // later keeps that work from swallowing the slide's first, largest step.
        slideStart = visible ? -1 : 0
        let link = screen.displayLink(target: self, selector: #selector(stepSlide(_:)))
        link.add(to: .main, forMode: .common)
        slideLink = link
    }
    @objc private func stepSlide(_ link: CADisplayLink) {
        if slideStart < 0 { slideStart = 0; return }
        if slideStart == 0 { slideStart = link.timestamp }
        let elapsed = (link.targetTimestamp - slideStart) / slideDuration
        let progress = CGFloat(slideCurve.value(at: elapsed))
        glass.setFrameOrigin(NSPoint(x: Self.inset, y: (slideFrom + (slideTo - slideFrom) * progress).rounded()))
        guard elapsed >= 1 else { return }
        link.invalidate(); slideLink = nil
        let completion = slideCompletion; slideCompletion = nil
        completion?()
    }
    /// Paste's "Show during screen sharing" hides the clipboard windows from screen capture when off.
    private func applySharing() {
        let type: NSWindow.SharingType = model.showDuringScreenSharing ? .readOnly : .none
        for window in [panel, settingsWindow, previewWindow, helpWindow, editor.panel, copiedHUD.panel] { window?.sharingType = type }
    }
    /// A fresh activation starts from the default state; a re-show after a failed paste keeps what was on screen.
    func show(resetState: Bool = true) {
        deliveryGeneration += 1
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        model.destinationApp = previousApp?.localizedName
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        // Start one window-height below the screen edge, unless the panel is already up or a slide-out is still
        // running, which then reverses from where it is.
        if let screen, !(panel.isVisible && (isShown || slideLink != nil)) {
            restingScreen = screen
            panel.setFrame(NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: Self.windowHeight), display: true)
            glass.setFrameOrigin(NSPoint(x: Self.inset, y: Self.inset - Self.windowHeight))
        }
        if resetState { model.resetForActivation() } else { model.reconcileSelection() }
        ThumbnailCache.shared.prewarm(model.visibleItems.prefix(40))
        transitionGeneration += 1
        panel.ignoresMouseEvents = false
        isShown = true
        panel.makeKeyAndOrderFront(nil)
        slide(visible: true)
        focusResults()
    }
    func hide(restoreFocus: Bool = true) {
        guard isShown else { return }
        isShown = false
        transitionGeneration += 1
        let generation = transitionGeneration
        panel.ignoresMouseEvents = true
        if restoreFocus { previousApp?.activate(options: []) }
        slide(visible: false) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.transitionGeneration else { return }
                self.panel.orderOut(nil)
                self.panel.ignoresMouseEvents = false
            }
        }
    }
    private func paste(_ item: ClipboardItem, plainText: Bool) {
        guard model.copy(item, plainText: plainText) else { return }
        guard model.directPaste else { hide(); showCopied(); return }
        SoundEffects.shared.play(.paste)
        guard AXIsProcessTrusted() else { askForAccessibility(); return }
        guard let target = previousApp, !target.isTerminated else {
            model.message = String(localized: "Copied. The previous app is unavailable; use ⌘V in your destination.")
            return
        }
        deliveryGeneration += 1
        let generation = deliveryGeneration
        hide(restoreFocus: false)
        guard target.activate(options: []) else { model.message = String(localized: "Copied, but the destination could not be activated."); show(resetState: false); return }
        let expectedChange = NSPasteboard.general.changeCount
        attemptPaste(to: target, generation: generation, expectedChange: expectedChange, attempts: 12)
    }
    /// Paste 6.3.11's prompt when "To active app" is chosen without Accessibility access (wording from its strings
    /// table; its presentation was not observed). The item is already on the clipboard either way.
    private func askForAccessibility() {
        let alert = NSAlert()
        let destination = previousApp?.localizedName ?? String(localized: "the current app")
        alert.messageText = String(localized: "Do you want to paste directly to \(destination)?")
        alert.informativeText = String(localized: "Elmers needs accessibility access to paste directly to other apps.")
        alert.addButton(withTitle: String(localized: "Enable Accessibility Access"))
        alert.addButton(withTitle: String(localized: "Not Now, Copy to Clipboard"))
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard let self else { return }
            self.hide()
            if response == .alertFirstButtonReturn {
                _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
            } else { self.showCopied() }
        }
    }
    /// Paste confirms a copy with a HUD near the bottom of the screen instead of a message in the panel.
    func showCopied() {
        SoundEffects.shared.play(.copy)
        copiedHUD.show(on: panel.screen, offerDirectPaste: !model.directPaste)
    }
    private func attemptPaste(to target: NSRunningApplication, generation: Int, expectedChange: Int, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, generation == self.deliveryGeneration else { return }
            guard NSPasteboard.general.changeCount == expectedChange else { self.model.message = String(localized: "Clipboard changed before paste. Please try again."); self.show(resetState: false); return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                if attempts > 0 { self.attemptPaste(to: target, generation: generation, expectedChange: expectedChange, attempts: attempts - 1) }
                else { self.model.message = String(localized: "Copied, but the destination did not become active. Paste manually with ⌘V."); self.show(resetState: false) }
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
            // Paste's settings window: 640×592 overall, content under a transparent unified title bar so the sidebar runs
            // to the top and the traffic lights sit 25 pt down, level with the pane title.
            let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 640, height: 592), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = String(localized: "Elmers Settings"); window.titleVisibility = .hidden; window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.toolbar = NSToolbar(identifier: "settings"); window.toolbarStyle = .unified
            let hosting = NSHostingView(rootView: SettingsView(model: model))
            hosting.sizingOptions = []
            window.contentView = hosting
            window.setFrame(NSRect(x: 0, y: 0, width: 640, height: 592), display: false)
            window.center(); settingsWindow = window
            applySharing()
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    /// Keyboard Shortcuts from the menu bar icon's menu, when there is no panel to host it as a sheet.
    func showKeyboardHelp() {
        if helpWindow == nil {
            let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 420, height: 480), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = String(localized: "Keyboard Shortcuts"); window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: KeyboardHelp { [weak window] in window?.close() })
            window.setContentSize(window.contentView?.fittingSize ?? window.frame.size)
            window.center(); helpWindow = window
            applySharing()
        }
        NSApp.activate(ignoringOtherApps: true); helpWindow?.makeKeyAndOrderFront(nil)
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
    /// Paste 6.3.11's Writing Tools ⇧⌘E: the item opens in the editor with the system Writing Tools over its text.
    func openWritingTools(_ item: ClipboardItem) {
        guard model.canEdit, !item.text.isEmpty else { return }
        openEditor(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.editor.showWritingToolsForAllText() }
    }
    func openPreview(_ item: ClipboardItem) {
        if previewWindow == nil {
            let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 640, height: 460), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.level = .floating; previewWindow = window
            applySharing()
        }
        previewWindow?.title = "\(item.kind.title) — \(item.source)"
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
        guard isShown else { return nil }
        let stroke = KeyStroke(event.keyCode, KeyModifiers(event.modifierFlags))
        let context: KeyboardContext = model.searchIsFocused ? .search : .results
        if context == .search, stroke == KeyStroke(51), model.removeLastFilter() { return nil }
        if let action = KeyboardRouter.command(for: stroke, context: context, settings: model.shortcuts) {
            switch action {
            case let .move(offset, extend):
                if event.keyCode == 48 { focusResults() }
                model.moveSelection(offset, extend: extend)
            case .first: focusResults(); model.selectedID = model.visibleItems.first?.id
            case .last: focusResults(); model.selectedID = model.visibleItems.last?.id
            case .selectAll: model.selectAll()
            case let .paste(plain): model.activate(plainText: plain)
            case let .quickPaste(index, plain):
                if model.visibleItems.indices.contains(index) { model.activate(model.visibleItems[index], plainText: plain) }
            case .copy:
                if let item = model.selectedAggregate(), model.copy(item) { showCopied() }
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
            case .writingTools: if let item = model.selected, !item.text.isEmpty { openWritingTools(item) }
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
                // Paste 6.3.11 steps back one layer per press: the filter popover, then the query and tokens,
                // then search mode itself, and only then the panel.
                if model.filtersOpen { model.filtersOpen = false }
                else if model.hasSearch { model.clearSearch() }
                else if model.searchOpen { model.searchOpen = false; focusResults() }
                else if model.selection.ids.count > 1 { model.selectedID = model.selectedID }
                else { hide() }
            case .showInHistory:
                let id = model.selectedID; model.clearSearch(); model.searchOpen = false; model.boardID = nil; model.selectedID = id
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
