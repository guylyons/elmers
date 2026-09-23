import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel!
    var panelController: PanelController!
    var statusItem: NSStatusItem!
    let shortcut = GlobalShortcut()
    private var pausedObserver: AnyCancellable?
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
        model.shortcutsChanged = { [weak self] in
            guard let self else { return }
            self.model.shortcutConflict = self.shortcut.register(self.model.shortcuts.activation) ? nil : String(localized: "The history shortcut is in use by another app. Quit Paste to use the same shortcut in Elmers.")
        }
        model.shortcutRecordingChanged = { [weak self] recording in
            guard let self else { return }
            if recording { self.shortcut.register(nil) } else { self.model.shortcutsChanged?() }
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
        model.start(); panelController.show()
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
