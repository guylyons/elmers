import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel!
    var panelController: PanelController!
    var statusItem: NSStatusItem!
    let shortcut = GlobalShortcut()
    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        model.applyActivationPolicy()
        panelController = PanelController(model: model)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Elmers clipboard history")
            button.target = self; button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Elmers — Shift-Command-V · Right-click for Settings"
        }
        panelController.statusItemFrame = { [weak self] in self?.statusItem.button?.window?.frame }
        shortcut.onActivate = { [weak self] in self?.panelController.toggle() }
        model.shortcutsChanged = { [weak self] in
            guard let self else { return }
            self.model.shortcutConflict = self.shortcut.register(self.model.shortcuts.activation) ? nil : "The history shortcut is in use by another app. Quit Paste to use the same shortcut in Elmers."
        }
        model.shortcutRecordingChanged = { [weak self] recording in
            guard let self else { return }
            if recording { self.shortcut.register(nil) } else { self.model.shortcutsChanged?() }
        }
        model.shortcutsChanged?()
        let menu = NSMenu()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit Elmers", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let applicationItem = NSMenuItem(); applicationItem.submenu = applicationMenu; menu.addItem(applicationItem)
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }
        let editItem = NSMenuItem(); editItem.submenu = edit; menu.addItem(editItem)
        NSApp.mainMenu = menu
        #if DEBUG
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
        if ProcessInfo.processInfo.arguments.contains("--check-interaction") {
            precondition(model.isDemo, "Interaction checks require --demo")
            InteractionChecks.run(model: model, controller: panelController)
            return
        }
        #endif
        model.start(); panelController.show()
    }
    @objc func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { settings() }
        else { toggle() }
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
