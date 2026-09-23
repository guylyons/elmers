import AppKit
import Combine
import WebKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel!
    var panelController: PanelController!
    var statusItem: NSStatusItem!
    let shortcut = GlobalShortcut()
    let stackShortcut = GlobalShortcut()
    var stackController: StackController!
    private var pausedObserver: AnyCancellable?
    private var onboarding: OnboardingController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        model.applyActivationPolicy()
        panelController = PanelController(model: model)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = StatusIcon.make()
            button.target = self; button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = String(localized: "Elmers — Shift-Command-V · Right-click for more")
        }
        panelController.statusItemFrame = { [weak self] in self?.statusItem.button?.window?.frame }
        pausedObserver = model.$paused.removeDuplicates().sink { [weak self] paused in self?.statusItem.button?.image = StatusIcon.make(paused: paused) }
        shortcut.onActivate = { [weak self] in self?.panelController.toggle() }
        stackController = StackController(model: model)
        stackShortcut.onActivate = { [weak self] in self?.stackController.toggle() }
        model.activateStack = { [weak self] in self?.stackController.toggle() }
        model.shortcutsChanged = { [weak self] in
            guard let self else { return }
            self.model.shortcutConflict = self.shortcut.register(self.model.shortcuts.activation) ? nil : String(localized: "The history shortcut is in use by another app. Quit Paste to use the same shortcut in Elmers.")
            self.stackShortcut.register(self.model.shortcuts.stack)
        }
        model.shortcutRecordingChanged = { [weak self] recording in
            guard let self else { return }
            if recording { self.shortcut.register(nil); self.stackShortcut.register(nil) } else { self.model.shortcutsChanged?() }
        }
        model.shortcutsChanged?()
        let menu = NSMenu()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: String(localized: "Settings…"), action: #selector(settings), keyEquivalent: ",").target = self
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: String(localized: "Quit Elmers"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let applicationItem = NSMenuItem(); applicationItem.submenu = applicationMenu; menu.addItem(applicationItem)
        let edit = NSMenu(title: String(localized: "Edit"))
        for (title, action, key) in [(String(localized: "Cut"), "cut:", "x"), (String(localized: "Copy"), "copy:", "c"), (String(localized: "Paste"), "paste:", "v"), (String(localized: "Select All"), "selectAll:", "a")] { edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }
        let editItem = NSMenuItem(); editItem.submenu = edit; menu.addItem(editItem)
        NSApp.mainMenu = menu
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--check-screenshots") {
            precondition(model.isDemo, "Screenshot checks require --demo")
            ScreenshotInteractionChecks.run(model: model, controller: panelController)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--check-scroll-performance") {
            precondition(model.isDemo, "Scroll checks require --demo")
            ScrollPerformanceChecks.run(model: model, controller: panelController)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--check-sounds") {
            SoundChecks.run()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--check-status-item") {
            precondition(model.isDemo)
            StatusItemChecks.run(delegate: self)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--check-global-shortcut") {
            precondition(model.isDemo)
            guard model.shortcutConflict == nil else { print("FAIL: shortcut registration conflict"); fflush(stdout); exit(1) }
            shortcut.onActivate = { print("PASS: system dispatched Shift-Command-V to Elmers"); fflush(stdout); exit(0) }
            NSApp.activate(ignoringOtherApps: true)
            print("READY: global shortcut registered"); fflush(stdout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { print("FAIL: global shortcut timed out"); fflush(stdout); exit(1) }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--check-editor") {
            precondition(model.isDemo, "Editor checks require --demo")
            KeyboardInteractionChecks.editorOnly = true
            KeyboardInteractionChecks.checkEditor(controller: panelController)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--check-interaction") {
            precondition(model.isDemo, "Interaction checks require --demo")
            InteractionChecks.run(model: model, controller: panelController)
            return
        }
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--check-link-preview-privacy") {
            LinkPreviewChecks.run(url: ProcessInfo.processInfo.arguments[index + 1])
            return
        }
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--check-link-browser") {
            // Opens the Space preview of a link item and prints the loaded page's title.
            precondition(model.isDemo, "Link browser checks require --demo")
            let url = ProcessInfo.processInfo.arguments[index + 1]
            model.start(); model.newText(url)
            guard let item = model.history.items.first(where: { $0.text == url }) else { print("FAIL: no link item"); exit(1) }
            panelController.openPreview(item)
            func poll(_ attempt: Int) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let web = NSApp.windows.compactMap { $0.contentView }.flatMap { [$0] + $0.allSubviews }.compactMap { $0 as? WKWebView }.first
                    guard let web, !web.isLoading, let title = web.title, !title.isEmpty else {
                        if attempt < 20 { poll(attempt + 1) } else { print("FAIL: page did not load"); exit(1) }
                        return
                    }
                    print("PASS: link preview loaded “\(title)”"); exit(0)
                }
            }
            poll(0)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--check-stack") {
            // Paste Stack without keyboard focus: copies join it in order while it is open, and it reverses, deletes and closes.
            precondition(model.isDemo, "Stack checks require --demo")
            let stack = stackController!
            func fail(_ message: String) -> Never { print("FAIL: \(message)"); fflush(stdout); exit(1) }
            model.onCapture?(.text("before opening"), "Notes")
            guard stack.stack.isEmpty else { fail("a copy joined the Stack while it was closed") }
            stack.open()
            model.onCapture?(.text("first"), "Notes"); model.onCapture?(.text("second"), "Notes"); model.onCapture?(.text("first"), "Notes")
            guard stack.isOpen, stack.stack.pasteOrder.map(\.payload.text) == ["first", "second", "first"] else { fail("Stack order \(stack.stack.pasteOrder.map(\.payload.text))") }
            stack.reverse()
            guard stack.stack.next?.payload.text == "first", stack.stack.pasteOrder.map(\.payload.text) == ["first", "second", "first"].reversed() else { fail("reverse") }
            if let second = stack.stack.entries.first(where: { $0.payload.text == "second" }) { stack.remove(second.id) }
            guard stack.stack.entries.count == 2 else { fail("delete") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let directory = ProcessInfo.processInfo.environment["ELMERS_CAPTURE_DIR"], let view = NSApp.windows.first(where: { $0.isVisible && $0.title == String(localized: "Paste Stack") })?.contentView,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("stack.png"))
                }
                stack.close()
                guard !stack.isOpen else { fail("close") }
                print("PASS: Paste Stack collects copies in order while open, reverses, deletes and closes"); exit(0)
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--demo-search-motion") {
            // For recording the search transition: opens search 0.8 s after the panel, closes it at 2.4 s, quits at 4 s.
            precondition(model.isDemo, "Motion demos require --demo")
            model.start(); panelController.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { NotificationCenter.default.post(name: .elmersSearch, object: nil) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { self.model.clearSearch(); self.model.searchOpen = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { exit(0) }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--show-panel"), let directory = ProcessInfo.processInfo.environment["ELMERS_CAPTURE_DIR"] {
            // Writes the demo panel as panel.png and quits, e.g. to check a translation. Requires --demo.
            precondition(model.isDemo, "Panel captures require --demo")
            model.start(); panelController.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                KeyboardInteractionChecks.capturePanel(self.panelController, name: "panel")
                // The menu bar icon, normal and paused, at 4× on a light and a dark bar.
                let icons = [StatusIcon.make(), StatusIcon.make(paused: true)]
                let sheet = NSImage(size: NSSize(width: 200, height: 200), flipped: false) { _ in
                    for (row, appearance) in [NSAppearance(named: .aqua)!, NSAppearance(named: .darkAqua)!].enumerated() {
                        appearance.performAsCurrentDrawingAppearance {
                            let bar = row == 0 ? NSColor(white: 0.93, alpha: 1) : NSColor(white: 0.15, alpha: 1)
                            bar.setFill()
                            NSRect(x: 0, y: CGFloat(row) * 100, width: 200, height: 100).fill()
                            for (column, icon) in icons.enumerated() { icon.draw(in: NSRect(x: 6 + CGFloat(column) * 100, y: CGFloat(row) * 100 + 6, width: 88, height: 88)) }
                        }
                    }
                    return true
                }
                if let tiff = sheet.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("status-icons.png"))
                }
                exit(0)
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--open-panel-later") {
            // For hands-on pointer tests: opens the demo panel 3 s after launch, the way the shortcut does, over whatever
            // app is frontmost by then (Elmers stays inactive, as in daily use).
            precondition(model.isDemo, "--open-panel-later requires --demo")
            model.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.panelController.show() }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--show-settings") {
            // For side-by-side captures: opens Settings on the pane named by ELMERS_SETTINGS_SECTION (General by default).
            model.start(); panelController.openSettings()
            // With ELMERS_CAPTURE_DIR set, write the pane as settings-<Section>.png and quit, e.g. to check a translation.
            if let directory = ProcessInfo.processInfo.environment["ELMERS_CAPTURE_DIR"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    let section = ProcessInfo.processInfo.environment["ELMERS_SETTINGS_SECTION"] ?? "General"
                    if let view = NSApp.windows.first(where: { $0.isVisible && $0.title == String(localized: "Elmers Settings") })?.contentView,
                       let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("settings-\(section).png"))
                    }
                    exit(0)
                }
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--check-live-storage-persistence") {
            precondition(!model.isDemo, "Live storage checks require the real store")
            StoragePersistenceChecks.run(model: model)
            return
        }
        #endif
        model.start()
        if model.needsOnboarding {
            // First run: the setup, then the panel on the Useful Links pinboard it leaves behind.
            let onboarding = OnboardingController(model: model)
            onboarding.finished = { [weak self] in
                guard let self else { return }
                self.model.seedUsefulLinks()
                self.model.boardID = self.model.history.boards.first { $0.name == String(localized: "Useful Links") }?.id
                self.panelController.show(resetState: false)
                self.onboarding = nil
            }
            self.onboarding = onboarding
            onboarding.show()
            #if DEBUG
            if let directory = ProcessInfo.processInfo.environment["ELMERS_CAPTURE_DIR"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    if let view = NSApp.windows.first(where: { $0.isVisible && $0.title == String(localized: "Welcome") })?.contentView,
                       let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: rep)
                        let step = ProcessInfo.processInfo.environment["ELMERS_ONBOARDING_STEP"] ?? "welcome"
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("onboarding-\(step).png"))
                    }
                    exit(0)
                }
            }
            #endif
            return
        }
        panelController.show()
    }
    @objc func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { presentStatusMenu(statusMenu()) }
        else { toggle() }
    }
    /// Right-clicking Paste's menu bar icon opens the same menu as the panel's … button.
    func statusMenu() -> NSMenu {
        AppMenu.make(model: model) { [weak self] in self?.panelController.showKeyboardHelp() }
    }
    /// Shows `menu` from the status item with the system's placement and highlight. Replaced by checks, which
    /// cannot drive a modal menu-tracking loop.
    lazy var presentStatusMenu: (NSMenu) -> Void = { [weak self] menu in
        guard let self, let button = self.statusItem.button else { return }
        self.statusItem.menu = menu
        button.performClick(nil)
        self.statusItem.menu = nil
    }
    @objc func toggle() { if model.shortcutConflict != nil { model.shortcutsChanged?() }; panelController.toggle() }
    @objc func settings() { panelController.openSettings() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { panelController.show(); return true }
    func applicationWillTerminate(_ notification: Notification) { model.flush() }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}

#if DEBUG
extension NSView {
    var allSubviews: [NSView] { subviews + subviews.flatMap(\.allSubviews) }
}
#endif
