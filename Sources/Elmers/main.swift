import AppKit
import Combine
import ElmersCore
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
        pausedObserver = model.$paused.removeDuplicates().sink { [weak self] paused in self?.gulpTimer?.invalidate(); self?.statusItem.button?.image = StatusIcon.make(paused: paused) }
        model.itemCaptured = { [weak self] in self?.gulp() }
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
        if ProcessInfo.processInfo.arguments.contains("--check-scroll-input") {
            precondition(model.isDemo, "Scroll checks require --demo")
            ScrollInputChecks.run(model: model, controller: panelController); return
        }
        if ProcessInfo.processInfo.arguments.contains("--check-scroll-performance") {
            precondition(model.isDemo, "Scroll checks require --demo")
            ScrollPerformanceChecks.run(model: model, controller: panelController)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--check-card-layout") {
            CardLayoutChecks.run()
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
        if ProcessInfo.processInfo.arguments.contains("--check-panel-resize") {
            // Paste's panel resizes from its top edge between 252 and 412 pt, rubber-bands past the limits, springs
            // back on release, switches to Compact Mode below 300 pt and keeps the height. Real mouse events, no focus.
            precondition(model.isDemo, "Resize checks require --demo")
            let model: AppModel = self.model, panelController: PanelController = self.panelController
            func fail(_ message: String) -> Never { print("FAIL: \(message)"); fflush(stdout); exit(1) }
            model.panelHeight = PanelMetrics.defaultHeight; model.savePanelHeight()
            for index in 0..<30 { model.newText("resize fixture \(index) " + String(repeating: "lorem ipsum dolor sit amet ", count: 8)) }
            panelController.show()
            let window = panelController.panel
            guard let handle = KeyboardInteractionChecks.subview(of: window.contentView, where: { $0 is PanelResizeHandle }) else { fail("no resize handle") }
            /// Presses on the handle, drags `dy` points up (negative is down) in steps and, if asked, lets go.
            func drag(_ dy: CGFloat, release: Bool = true) {
                let start = window.convertPoint(toScreen: handle.convert(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: nil))
                func post(_ type: NSEvent.EventType, _ screenY: CGFloat) {
                    let point = window.convertPoint(fromScreen: NSPoint(x: start.x, y: screenY))
                    let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                    window.sendEvent(event)
                }
                post(.leftMouseDown, start.y)
                for step in 1...10 { post(.leftMouseDragged, start.y + dy * CGFloat(step) / 10) }
                if release { post(.leftMouseUp, start.y + dy) }
            }
            /// ELMERS_RESIZE_PROFILE: times what one display refresh of a drag costs, 2 pt at a time from 332 up to 412,
            /// down to 252 and back, split into layout, display and the Core Animation commit. Before the fixes of
            /// September 30 a step took 17 ms (every card re-evaluated through the model); it should stay near 8 ms.
            func profile() {
                var durations: [Double] = []
                var parts = [0.0, 0.0, 0.0, 0.0]
                for dy in Array(stride(from: 2, through: 80, by: 2)) + Array(stride(from: 78, through: -80, by: -2)) + Array(stride(from: -78, through: 0, by: 2)) {
                    let begin = CFAbsoluteTimeGetCurrent()
                    model.panelHeight = PanelMetrics.defaultHeight + CGFloat(dy)
                    let t0 = CFAbsoluteTimeGetCurrent(); window.contentView?.layoutSubtreeIfNeeded()
                    let t1 = CFAbsoluteTimeGetCurrent(); window.displayIfNeeded()
                    let t2 = CFAbsoluteTimeGetCurrent(); CATransaction.flush()
                    let t3 = CFAbsoluteTimeGetCurrent()
                    durations.append((t3 - begin) * 1000)
                    parts[0] += (t0 - begin) * 1000; parts[1] += (t1 - t0) * 1000; parts[2] += (t2 - t1) * 1000; parts[3] += (t3 - t2) * 1000
                }
                let sorted = durations.sorted()
                print(String(format: "RESULT: %d resize steps, median %.2f ms, p95 %.2f ms, max %.2f ms, %d over 8.3 ms", durations.count,
                             sorted[sorted.count / 2], sorted[Int(Double(sorted.count - 1) * 0.95)], sorted.last ?? 0, durations.filter { $0 > 8.3 }.count))
                print(String(format: "PARTS per step: change %.2f ms, layout %.2f ms, display %.2f ms, commit %.2f ms", parts[0] / Double(durations.count),
                             parts[1] / Double(durations.count), parts[2] / Double(durations.count), parts[3] / Double(durations.count)))
                model.panelHeight = PanelMetrics.defaultHeight; model.savePanelHeight()
            }
            /// Runs `body` once the panel has slid in, with its handle along the window's top edge.
            func whenShown(_ body: @escaping () -> Void, deadline: Date = Date().addingTimeInterval(3)) {
                if handle.convert(handle.bounds, to: nil).maxY >= window.frame.height - 1 { body(); return }
                guard Date() < deadline else { fail("the panel did not slide in") }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { whenShown(body, deadline: deadline) }
            }
            whenShown {
                if ProcessInfo.processInfo.environment["ELMERS_RESIZE_PROFILE"] != nil { profile(); exit(0) }
                if ProcessInfo.processInfo.environment["ELMERS_RESIZE_DEMO"] != nil {
                    // ELMERS_RESIZE_DEMO, for recording with `screencapture -v`: a drag at 120 Hz from 332 up to 412, down to 252 and back, over 3 s, then release.
                    let start = window.convertPoint(toScreen: handle.convert(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: nil))
                    func post(_ type: NSEvent.EventType, _ dy: CGFloat) {
                        window.sendEvent(NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: NSPoint(x: start.x, y: start.y + dy)), modifierFlags: [],
                                                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
                    }
                    print("PANEL \(window.frame)"); fflush(stdout)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        post(.leftMouseDown, 0)
                        let began = CACurrentMediaTime()
                        Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { timer in
                            MainActor.assumeIsolated {
                                let t = (CACurrentMediaTime() - began) / 3
                                let dy: CGFloat = t < 0.25 ? 80 * t * 4 : t < 0.75 ? 80 - 160 * (t - 0.25) * 2 : -80 + 80 * (t - 0.75) * 4
                                if t >= 1 { post(.leftMouseUp, 0); timer.invalidate(); DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) } }
                                else { post(.leftMouseDragged, dy) }
                            }
                        }
                    }
                    return
                }
                drag(80)
                guard model.panelHeight == 412, window.frame.height == 412, model.panelMetrics.cardSide == 312 else { fail("dragging up 80 pt gave \(model.panelHeight), window \(window.frame.height)") }
                drag(60, release: false)
                // Heights asked for during a drag apply on the next display refresh.
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                guard model.panelHeight > 412, model.panelHeight < 412 + PanelMetrics.stretch else { fail("no rubber band past the top: \(model.panelHeight)") }
                window.sendEvent(NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    guard model.panelHeight == 412 else { fail("did not spring back to 412: \(model.panelHeight)") }
                    drag(-400)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        guard model.panelHeight == 252, window.frame.height == 252, model.panelMetrics.isCompact else { fail("dragging far down settled at \(model.panelHeight)") }
                        KeyboardInteractionChecks.capturePanel(panelController, name: "panel-compact")
                        panelController.hide(restoreFocus: false)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            panelController.show()
                            guard window.frame.height == 252 else { fail("the height was not kept: \(window.frame.height)") }
                            model.panelHeight = PanelMetrics.defaultHeight; model.savePanelHeight()
                            print("PASS: the panel resizes from its top edge, rubber-bands, springs back, goes compact below 300 pt and keeps its height"); exit(0)
                        }
                    }
                }
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--check-card-menu") {
            precondition(model.isDemo, "Card menu checks require --demo")
            CardMenuChecks.run(model: model, controller: panelController); return
        }
        if ProcessInfo.processInfo.arguments.contains("--check-delete-confirmation") {
            // Paste asks before deleting several items: Cancel keeps them, Delete removes them, one item goes without asking.
            precondition(model.isDemo, "Deletion checks require --demo")
            func fail(_ message: String) -> Never { print("FAIL: \(message)"); fflush(stdout); exit(1) }
            func controls(in view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(controls) }
            /// Answers the next alert with the button titled `button` after checking its title and button order.
            func answer(_ button: String) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    guard let content = NSApp.modalWindow?.contentView else { fail("no confirmation appeared") }
                    let views = controls(in: content)
                    let texts = views.compactMap { ($0 as? NSTextField)?.stringValue }
                    let buttons = views.compactMap { $0 as? NSButton }.filter { !$0.title.isEmpty }.sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
                    guard texts.contains(String(localized: "Delete selected items?")) else { fail("alert text \(texts)") }
                    guard buttons.map(\.title) == [String(localized: "Cancel"), String(localized: "Delete")] else { fail("alert buttons \(buttons.map(\.title))") }
                    buttons.first { $0.title == button }?.performClick(nil)
                }
            }
            for text in ["delete check one", "delete check two", "delete check three"] { model.newText(text) }
            panelController.show()
            model.selectAll()
            answer(String(localized: "Cancel")); model.deleteSelection()
            guard model.visibleItems.count == 3 else { fail("Cancel deleted items") }
            answer(String(localized: "Delete")); model.deleteSelection()
            guard model.visibleItems.isEmpty else { fail("Delete kept \(model.visibleItems.count) items") }
            model.newText("delete check single")
            if let item = model.visibleItems.first { model.select(item.id) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { if NSApp.modalWindow != nil { fail("asked before deleting one item") } }
            model.deleteSelection()
            guard model.visibleItems.isEmpty else { fail("single item was not deleted") }
            print("PASS: deleting several items asks first; Cancel keeps them, Delete removes them, one item goes at once"); exit(0)
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
            model.start(); panelController.show(); applyDemoQuery()
            /// Captures once the panel has slid in and its cards had a moment to draw (a fixed 1-s wait could catch an
            /// empty glass when launch work delayed the slide).
            func whenSettled(_ body: @escaping () -> Void, deadline: Date = Date().addingTimeInterval(5)) {
                let delay = Double(ProcessInfo.processInfo.environment["ELMERS_CAPTURE_DELAY"] ?? "") ?? 0.6
                if self.panelController.isSettled || Date() > deadline { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: body); return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { whenSettled(body, deadline: deadline) }
            }
            whenSettled {
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
                // Every frame of the capture gulp at 4× on a dark bar, left to right, with the resting icon's baseline marked.
                let frames = self.gulpFrames
                let strip = NSImage(size: NSSize(width: CGFloat(frames.count) * 100, height: 92), flipped: false) { bounds in
                    NSColor(white: 0.15, alpha: 1).setFill(); bounds.fill()
                    for (index, frame) in frames.enumerated() { frame.draw(in: NSRect(x: CGFloat(index) * 100 + 2, y: 2, width: 96, height: 88)) }
                    NSColor.systemRed.setFill(); NSRect(x: 0, y: 6, width: bounds.width, height: 1).fill()
                    return true
                }
                if let tiff = strip.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("status-gulp.png"))
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.panelController.show(); self.applyDemoQuery() }
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
    private var gulpTimer: Timer?
    private lazy var gulpFrames = StatusIcon.gulpFrames(of: StatusIcon.make())
    /// Plays the character's gulp in the menu bar; a capture during one restarts it.
    func gulp() {
        guard !model.paused, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let button = statusItem.button else { return }
        gulpTimer?.invalidate()
        var index = 0
        let timer = Timer(timeInterval: 1 / GulpAnimation.framesPerSecond, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                if index < self.gulpFrames.count { button.image = self.gulpFrames[index]; index += 1 }
                else { timer.invalidate(); button.image = StatusIcon.make(paused: self.model.paused) }
            }
        }
        RunLoop.main.add(timer, forMode: .common); gulpTimer = timer
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
    #if DEBUG
    /// For side-by-side captures of search states: `ELMERS_DEMO_QUERY` opens the demo panel's search with that text.
    func applyDemoQuery() {
        guard let query = ProcessInfo.processInfo.environment["ELMERS_DEMO_QUERY"] else { return }
        model.searchOpen = true; model.query = query
    }
    #endif
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
