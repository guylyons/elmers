#if DEBUG
import AppKit
import ElmersCore

@MainActor
final class KeyboardInteractionChecks {
    static func run(model: AppModel, controller: PanelController) {
        var deliveries: [Bool] = []
        model.deliver = { _, plain in deliveries.append(plain) }
        let ids = model.visibleItems.map(\.id)
        model.selectedID = ids[0]
        let steps: [(UInt16, NSEvent.ModifierFlags, () -> Bool, String)] = [
            (0, .command, { model.selection.ids.count == ids.count }, "Command-A selects all"),
            (123, [], { model.selection.ids.count == 1 }, "Left collapses selection"),
            (124, .shift, { model.selection.ids.count == 2 }, "Shift-Right extends selection"),
            (3, .command, { model.searchIsFocused }, "Command-F focuses search"),
            (48, [], { !model.searchIsFocused && model.selectedID == ids.last && model.selectedItems.count == 1 }, "Tab advances and focuses results"),
            (48, .shift, { !model.searchIsFocused && model.selectedID == ids.first }, "Shift-Tab selects previous card"),
            (125, .command, { model.selectedID == ids.last && !model.searchIsFocused }, "Command-Down selects last and focuses results"),
            (126, .command, { model.selectedID == ids.first }, "Command-Up selects first"),
            (124, [], { model.selectedID == ids.last }, "Right selects next item"),
            (124, [], { model.selectedID == ids.last }, "Right stops at last item"),
            (3, .command, { model.searchIsFocused }, "Search can be focused again"),
            (123, [], { model.selectedID == ids[ids.count - 2] && model.searchIsFocused }, "Left moves the selection while search keeps focus"),
            (124, [], { model.selectedID == ids.last && model.searchIsFocused }, "Right moves the selection while search keeps focus"),
            (36, [], { deliveries == [false] }, "Return from search delivers with a single press"),
            (48, [], { !model.searchIsFocused && model.selectedID == ids.last && model.selectedItems.count == 1 }, "Tab advances and focuses results"),
            (36, [], { deliveries == [false, false] }, "Return delivers selection"),
            (36, .shift, { deliveries == [false, false, true] }, "Shift-Return delivers plain text"),
            (18, .command, { deliveries == [false, false, true, false] }, "Command-1 quick pastes"),
            (18, [.command, .shift], { deliveries == [false, false, true, false, true] }, "Shift-Command-1 quick pastes plain text")
        ]
        func step(_ index: Int) {
            guard index < steps.count else { checkTypingIntoSearch(model: model, controller: controller); return }
            let (code, flags, verify, description) = steps[index]
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: controller.panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
            NSApp.postEvent(event, atStart: false)
            // Give the event 80 ms, then keep checking for up to 1.5 s: a fixed delay failed whenever the machine
            // was busy, although every step eventually reached its state.
            let deadline = Date().addingTimeInterval(1.5)
            func check() {
                if verify() { print("PASS: \(description)"); step(index + 1); return }
                guard Date() < deadline else {
                    print("FAIL: \(description) [editor=\(controller.panel.firstResponder is NSTextView) focused=\(model.searchIsFocused) open=\(model.searchOpen) selIndex=\(model.selectedID.flatMap { ids.firstIndex(of: $0) } ?? -1) count=\(model.selection.ids.count)]"); fflush(stdout); exit(1)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: check)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: check)
        }
        step(0)
    }
    /// Typing while results have focus must produce the whole word: the first letter opens the search field and
    /// the following letters go into it without replacing a select-all.
    static func checkTypingIntoSearch(model: AppModel, controller: PanelController) {
        NotificationCenter.default.post(name: .elmersResults, object: nil)
        model.query = ""
        func type(_ character: String, _ code: UInt16, then next: @escaping () -> Void) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: controller.panel.windowNumber, context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: code)!
            NSApp.postEvent(event, atStart: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: next)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            type("p", 35) { type("a", 0) { type("i", 34) {
                guard model.query == "pai" else { print("FAIL: typed 'pai' but the query is '\(model.query)'"); fflush(stdout); exit(1) }
                print("PASS: typing into a fresh search keeps the first letter")
                checkTypingCategory(model: model, controller: controller)
            } } }
        }
    }
    /// Paste 6.3.11's filter suggestions: typing "im" offers the Image chip under the field while "im" stays search text;
    /// Down highlights it, Return turns it into a token and drops the typed word, and Backspace removes the token.
    static func checkTypingCategory(model: AppModel, controller: PanelController) {
        let image = NSImage(size: NSSize(width: 160, height: 100), flipped: false) { rect in NSColor.systemTeal.setFill(); rect.fill(); return true }
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { print("FAIL: category fixture image"); exit(1) }
        model.newItem(payload: ClipboardPayload(items: [["public.png": png, NSPasteboard.PasteboardType.string.rawValue: Data("Category fixture".utf8)]]))
        model.query = ""
        NotificationCenter.default.post(name: .elmersResults, object: nil)
        func fail(_ message: String) { print("FAIL: \(message)"); fflush(stdout); exit(1) }
        func key(_ character: String, _ code: UInt16) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: controller.panel.windowNumber, context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: code)!
            NSApp.postEvent(event, atStart: false)
        }
        func after(_ then: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: then) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            key("i", 34); after { key("m", 46); after {
                guard model.query == "im", model.filters.isEmpty, model.filterSuggestions.first == .kind(.image), model.suggestionIndex == nil else {
                    return fail("typing 'im' left query '\(model.query)', filters \(model.filters.tokens), suggestions \(model.filterSuggestions)")
                }
                capturePanel(controller, name: "search-suggestions")
                print("PASS: typing the start of a chip title offers it and keeps the text")
                key("", 125); after {
                    guard model.suggestionIndex == 0, model.searchIsFocused else { return fail("Down did not highlight the first suggestion (index \(String(describing: model.suggestionIndex)))") }
                    key("\r", 36); after {
                        guard model.query.isEmpty, model.filters.tokens == [.kind(.image)], model.searchIsFocused, !model.visibleItems.isEmpty,
                              model.visibleItems.allSatisfy({ $0.kind.isImage }) else {
                            return fail("Down, Return left query '\(model.query)', filters \(model.filters.tokens), focused \(model.searchIsFocused), showing \(model.visibleItems.map(\.kind))")
                        }
                        capturePanel(controller, name: "search-image-filter")
                        print("PASS: Down and Return turn the suggestion into a token and keep search focused")
                        key("\u{7F}", 51); after {
                            guard model.filters.isEmpty, model.query.isEmpty else { return fail("Backspace left filters \(model.filters.tokens) and query '\(model.query)'") }
                            print("PASS: Backspace on the empty field removes the token")
                            model.query = ""
                            checkSearchMode(model: model, controller: controller)
                        }
                    }
                }
            } }
        }
    }
    /// Writes a PNG of the panel to $ELMERS_CAPTURE_DIR when set, so a demo run can be inspected by eye without touching real history.
    static func capturePanel(_ controller: PanelController, name: String) {
        guard let directory = ProcessInfo.processInfo.environment["ELMERS_CAPTURE_DIR"], let view = controller.panel.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }
    /// Paste 6.3.11's search mode: ⌘F opens the field, a second ⌘F opens the filter chips, chips combine as tokens,
    /// and Escape steps back one layer at a time (popover, then query and tokens, then search mode).
    static func checkSearchMode(model: AppModel, controller: PanelController) {
        func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = []) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: controller.panel.windowNumber,
                                         context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
            NSApp.postEvent(event, atStart: false)
        }
        func fail(_ message: String) -> Never { print("FAIL: \(message)"); fflush(stdout); exit(1) }
        func after(_ delay: Double, _ body: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: body) }
        NotificationCenter.default.post(name: .elmersResults, object: nil)
        model.clearSearch(); model.searchOpen = false
        // Let SwiftUI report the field's lost focus first, or ⌘F would count as the in-search ⌘F that opens filters.
        after(0.2) { key(3, "f", .command) }
        after(0.45) {
            guard model.searchOpen, model.searchIsFocused, !model.filtersOpen else { fail("⌘F did not open and focus the search field (open \(model.searchOpen), focused \(model.searchIsFocused), filters \(model.filtersOpen))") }
            key(3, "f", .command)
            after(0.4) {
                guard model.filtersOpen else { fail("a second ⌘F did not open the filter chips") }
                if let directory = ProcessInfo.processInfo.environment["ELMERS_CAPTURE_DIR"],
                   let popover = NSApp.windows.first(where: { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }), let view = popover.contentView,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("filter-popover.png"))
                }
                model.newText("#FF8800")
                model.filters = SearchFilters([.kind(.color)])
                guard model.visibleItems.count == 1, model.visibleItems.first?.kind == .color else { fail("Color chip should show only the copied color") }
                capturePanel(controller, name: "color-card")
                model.filters.removeAll()
                model.newText("https://example.com/search-mode-fixture")
                model.filters.toggle(.kind(.text)); model.filters.toggle(.kind(.link)); model.filters.toggle(.date(.today))
                let now = Date(), start = Calendar.current.startOfDay(for: now)
                guard model.filters.tokens == [.kind(.text), .kind(.link), .date(.today)], !model.visibleItems.isEmpty,
                      model.visibleItems.allSatisfy({ [.text, .link].contains($0.kind) && $0.copiedAt >= start }),
                      model.visibleItems.contains(where: { $0.kind == .link }) else { fail("Text + Link + Today did not show today's text and links: \(model.visibleItems.map(\.kind))") }
                capturePanel(controller, name: "search-tokens")
                key(53, "\u{1B}")
                after(0.3) {
                    guard !model.filtersOpen, model.filters.tokens.count == 3, model.searchOpen else { fail("first Escape should only close the filter chips") }
                    key(53, "\u{1B}")
                    after(0.2) {
                        guard model.filters.isEmpty, model.query.isEmpty, model.searchOpen, controller.isShown else { fail("second Escape should clear the tokens and keep search open") }
                        capturePanel(controller, name: "search-open")
                        key(53, "\u{1B}")
                        after(0.2) {
                            guard !model.searchOpen, controller.isShown else { fail("third Escape should close search mode and keep the panel") }
                            print("PASS: search mode: ⌘F, filter chips as tokens, and Escape one layer at a time")
                            checkInlineRename(model: model, controller: controller)
                        }
                    }
                }
            }
        }
    }
    /// ⌘R edits the selected card's title in place (Paste: "click the item's title and type a new one"): typed keys go
    /// to the title, Return saves, and Escape cancels without saving.
    static func checkInlineRename(model: AppModel, controller: PanelController) {
        func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = []) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: controller.panel.windowNumber,
                                         context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
            NSApp.postEvent(event, atStart: false)
        }
        func fail(_ message: String) -> Never { print("FAIL: \(message)"); fflush(stdout); exit(1) }
        func after(_ delay: Double, _ body: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: body) }
        NotificationCenter.default.post(name: .elmersResults, object: nil)
        guard let target = model.visibleItems.first else { fail("rename needs an item") }
        model.selectedID = target.id
        after(0.2) {
            key(15, "r", .command)
            after(0.4) {
                guard model.renamingID == target.id, controller.panel.firstResponder is NSTextView else { fail("⌘R did not open the title for editing") }
                for (code, character) in [(0 as UInt16, "a"), (11, "b")] { key(code, character) }
                capturePanel(controller, name: "rename")
                after(0.3) {
                    key(36, "\r")
                    after(0.3) {
                        guard model.renamingID == nil, model.history.items.first(where: { $0.id == target.id })?.title?.hasSuffix("ab") == true else {
                            fail("Return did not save the typed title (\(String(describing: model.history.items.first { $0.id == target.id }?.title)))")
                        }
                        key(15, "r", .command)
                        after(0.4) {
                            key(0, "a"); key(53, "\u{1B}")
                            after(0.3) {
                                guard model.renamingID == nil, model.history.items.first(where: { $0.id == target.id })?.title?.hasSuffix("ab") == true else { fail("Escape should cancel the rename") }
                                model.renameItem(model.history.items.first { $0.id == target.id }!, title: target.title)
                                print("PASS: ⌘R renames the card title in place; Return saves, Escape cancels")
                                checkReopening(model: model, controller: controller)
                            }
                        }
                    }
                }
            }
        }
    }
    static func checkReopening(model: AppModel, controller: PanelController) {
        NotificationCenter.default.post(name: .elmersSearch, object: nil)
        // The field takes focus once it has finished growing open.
        DispatchQueue.main.asyncAfter(deadline: .now() + TimingCurve.searchOpenDuration + 0.15) {
            guard model.searchIsFocused else { print("FAIL: reopen setup search focus"); exit(1) }
            controller.hide(restoreFocus: false)
            controller.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard !model.searchIsFocused, !(controller.panel.firstResponder is NSTextView) else {
                    print("FAIL: reopening left search consuming navigation keys"); exit(1)
                }
                print("PASS: reopening restores results keyboard focus")
                checkScrollReset(model: model, controller: controller)
            }
        }
    }
    /// Reopening must reset the actual viewport even when selection has not changed.
    static func checkScrollReset(model: AppModel, controller: PanelController) {
        for index in 0..<24 { model.newText("Scroll fixture \(index)") }
        controller.show()
        func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, scroll.documentView?.bounds.width ?? 0 > scroll.contentSize.width { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let root = controller.panel.contentView, let scroll = scrollView(in: root) else {
                print("FAIL: history scroll view not found"); exit(1)
            }
            scroll.contentView.scroll(to: NSPoint(x: 150, y: 0))
            scroll.reflectScrolledClipView(scroll.contentView)
            guard scroll.contentView.bounds.minX > 100 else { print("FAIL: scroll fixture did not move"); exit(1) }
            let selected = model.selectedID
            controller.hide(restoreFocus: false)
            controller.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let current = scrollView(in: root), abs(current.contentView.bounds.minX) < 0.5,
                      model.selectedID == selected else {
                    print("FAIL: reopening did not reset unchanged selection to the left edge"); exit(1)
                }
                print("PASS: reopening resets the actual viewport with unchanged selection")
                checkRecorder(controller: controller)
            }
        }
    }
    static func checkRecorder(controller: PanelController) {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 400, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        let button = ShortcutRecorder.RecorderButton()
        button.frame = NSRect(x: 20, y: 30, width: 250, height: 30)
        window.contentView?.addSubview(button)
        window.makeKeyAndOrderFront(nil)
        let original = KeyStroke(9, [.command, .shift])
        button.binding = original
        var recorded: KeyStroke?
        button.changed = { recorded = $0 }
        func send(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
            NSApp.sendEvent(event)
        }
        button.beginRecording(); send(53)
        guard button.binding == original, !button.recording else { print("FAIL: recorder cancellation"); fflush(stdout); exit(1) }
        button.beginRecording(); send(9, [.control, .option])
        guard recorded == KeyStroke(9, [.control, .option]), !button.recording else { print("FAIL: recorder capture"); fflush(stdout); exit(1) }
        button.beginRecording(); send(51)
        guard button.binding == nil, !button.recording else { print("FAIL: recorder clearing"); fflush(stdout); exit(1) }
        button.beginRecording()
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        guard !button.recording else { print("FAIL: recorder window cancellation"); fflush(stdout); exit(1) }
        print("PASS: shortcut recorder capture, cancellation, clearing, and window deactivation")
        window.orderOut(nil)
        checkEditor(controller: controller)
    }
    /// Exercises the floating editor with real text storage: counters, bold on a range, RTF-only-when-formatted, cancel.
    /// Set by `--check-editor`: run only the editor checks, which need no keyboard focus.
    static var editorOnly = false
    static func checkEditor(controller: PanelController) {
        let model = controller.model, editor = controller.editor
        let countBefore = model.history.items.count
        controller.openEditor(nil)
        guard editor.panel.isVisible, !controller.isShown else { print("FAIL: editor did not replace the panel"); fflush(stdout); exit(1) }
        editor.textView.insertText("Hello editor\nsecond line", replacementRange: NSRange(location: 0, length: 0))
        if let directory = ProcessInfo.processInfo.environment["ELMERS_CAPTURE_DIR"], let view = editor.panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep); try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("editor-text.png"))
        }
        guard editor.statistics == "24 characters · 4 words · 2 lines" else { print("FAIL: editor statistics: \(editor.statistics)"); fflush(stdout); exit(1) }
        editor.textView.setSelectedRange(NSRange(location: 0, length: 5))
        editor.toggleBold()
        let bolded = (editor.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true
        let plainTail = (editor.textView.textStorage?.attribute(.font, at: 8, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == false
        guard bolded, plainTail else { print("FAIL: bold was not applied to the selection only"); fflush(stdout); exit(1) }
        editor.confirm()
        guard !editor.panel.isVisible, model.history.items.count == countBefore + 1 else { print("FAIL: create did not add an item"); fflush(stdout); exit(1) }
        let created = model.history.items[0]
        guard created.text == "Hello editor\nsecond line", created.payload.items[0]["public.rtf"] != nil else { print("FAIL: created item lacks text or RTF"); fflush(stdout); exit(1) }
        print("PASS: editor counters, bold range, and formatted create")
        controller.openEditor(nil)
        editor.textView.insertText("plain only", replacementRange: NSRange(location: 0, length: 0))
        editor.confirm()
        guard model.history.items[0].payload.items[0]["public.rtf"] == nil, model.history.items[0].text == "plain only" else { print("FAIL: unformatted text should stay plain"); fflush(stdout); exit(1) }
        print("PASS: unformatted create stays plain text")
        controller.openEditor(created)
        guard editor.textView.string == created.text, editor.panel.isVisible else { print("FAIL: edit did not load the item"); fflush(stdout); exit(1) }
        editor.textView.insertText("CHANGED", replacementRange: NSRange(location: 0, length: 5))
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: editor.panel.windowNumber, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53)!
        NSApp.sendEvent(escape)
        guard !editor.panel.isVisible else { print("FAIL: Escape did not cancel the editor"); fflush(stdout); exit(1) }
        guard model.history.items.first(where: { $0.id == created.id })?.text == created.text else { print("FAIL: cancel changed the item"); fflush(stdout); exit(1) }
        controller.openEditor(created)
        editor.textView.insertText("CHANGED", replacementRange: NSRange(location: 0, length: 5))
        editor.confirm()
        guard model.history.items.first(where: { $0.id == created.id })?.text == "CHANGED editor\nsecond line" else { print("FAIL: save did not update the item"); fflush(stdout); exit(1) }
        print("PASS: editor cancel preserves and save updates the item")
        let square = NSImage(size: NSSize(width: 160, height: 100), flipped: false) { rect in NSColor.systemTeal.setFill(); rect.fill(); return true }
        guard let squareTIFF = square.tiffRepresentation, let squarePNG = NSBitmapImageRep(data: squareTIFF)?.representation(using: .png, properties: [:]) else { print("FAIL: rotation fixture"); fflush(stdout); exit(1) }
        model.newItem(payload: ClipboardPayload(items: [["public.png": squarePNG]]))
        let picture = model.history.items[0]
        controller.openEditor(picture)
        guard editor.panel.isVisible, !editor.imageView.isHidden, editor.imageView.image != nil, editor.textView.isHidden else { print("FAIL: an image item should open in the editor's image mode"); fflush(stdout); exit(1) }
        if let directory = ProcessInfo.processInfo.environment["ELMERS_CAPTURE_DIR"], let view = editor.panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep); try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("editor-image.png"))
        }
        editor.rotateLeft(); editor.rotateLeft(); editor.rotateRight()
        editor.confirm()
        guard let rotated = model.history.items.first(where: { $0.id == picture.id }).flatMap(imagePreview), let rep = rotated.representations.first,
              rep.pixelsWide == 100, rep.pixelsHigh == 160 else { print("FAIL: Rotate left twice and right once should save the image turned a quarter"); fflush(stdout); exit(1) }
        print("PASS: image editor rotates and saves the turned image")
        if editorOnly { print("PASS: editor checks"); fflush(stdout); exit(0) }
        checkDrag(model: model, controller: controller)
    }
    /// A card drag must carry every stored item with every representation, and file URLs must be the originals.
    static func checkDrag(model: AppModel, controller: PanelController) {
        let fileURL = URL(fileURLWithPath: "/tmp/Elmers check.txt")
        let payload = ClipboardPayload(items: [
            ["public.utf8-plain-text": Data("dragged".utf8), "public.rtf": Data("{\\rtf1 dragged}".utf8)],
            [NSPasteboard.PasteboardType.fileURL.rawValue: fileURL.dataRepresentation],
        ])
        let item = ClipboardItem(payload: payload, source: "Check")
        let dragging = DragSupport.draggingItems(for: item, frame: NSRect(x: 0, y: 0, width: 235, height: 236), image: nil)
        let written = dragging.compactMap { $0.item as? NSPasteboardItem }
        guard written.count == 2,
              Set(written[0].types.map(\.rawValue)) == ["public.utf8-plain-text", "public.rtf", DragSupport.itemIDsType.rawValue],
              written[0].string(forType: DragSupport.itemIDsType) == item.id.uuidString, written[1].types.count == 1,
              written[0].data(forType: .rtf) == Data("{\\rtf1 dragged}".utf8),
              written[1].data(forType: .fileURL) == fileURL.dataRepresentation else {
            print("FAIL: drag items \(written.map { $0.types.map(\.rawValue) })"); fflush(stdout); exit(1)
        }
        print("PASS: card drag carries every item and representation")
        model.newText("Pointer drag fixture")
        controller.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let board = NSPasteboard(name: .drag)
            board.clearContents()
            let start = NSPoint(x: 145, y: 130), end = NSPoint(x: 220, y: 130)
            func mouse(_ type: NSEvent.EventType, at point: NSPoint, pressure: Float) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: controller.panel.windowNumber, context: nil, eventNumber: 73,
                                   clickCount: 1, pressure: pressure)!
            }
            NSApp.postEvent(mouse(.leftMouseDown, at: start, pressure: 1), atStart: false)
            NSApp.postEvent(mouse(.leftMouseDragged, at: end, pressure: 1), atStart: false)
            NSApp.postEvent(mouse(.leftMouseUp, at: end, pressure: 0), atStart: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let types = Set((board.types ?? []).map(\.rawValue))
                guard types.contains(NSPasteboard.PasteboardType.string.rawValue) else {
                    print("FAIL: pointer drag did not start a card drag session; drag types: \(types.sorted())")
                    fflush(stdout); exit(1)
                }
                print("PASS: pointer drag starts a card drag session")
                checkRecognition(model: model, controller: controller)
            }
        }
    }
    /// The Copied HUD appears for about a second after a clipboard-mode paste or ⌘C, then fades out on its own.
    static func checkCopiedHUD(model: AppModel, controller: PanelController) {
        model.clearSearch(); model.boardID = nil
        model.directPaste = false
        model.newText("https://pasteapp.io/help/keyboard-shortcuts")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            capturePanel(controller, name: "panel")
            controller.showCopied()
            guard controller.copiedHUD.isVisible, controller.copiedHUD.panel.frame.size == NSSize(width: 200, height: 200) else { print("FAIL: Copied HUD did not appear"); fflush(stdout); exit(1) }
            if let directory = ProcessInfo.processInfo.environment["ELMERS_CAPTURE_DIR"], let view = controller.copiedHUD.panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("copied-hud.png"))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard controller.copiedHUD.isVisible else { print("FAIL: Copied HUD vanished early"); fflush(stdout); exit(1) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard !controller.copiedHUD.isVisible else { print("FAIL: Copied HUD stayed visible"); fflush(stdout); exit(1) }
                    print("PASS: Copied HUD shows for about a second, then fades")
                    fflush(stdout); exit(0)
                }
            }
        }
    }
    /// Renders text into a PNG and confirms Vision makes it searchable.
    static func checkRecognition(model: AppModel, controller: PanelController) {
        let image = NSImage(size: NSSize(width: 600, height: 160), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("ELMERS OCR 4711" as NSString).draw(at: NSPoint(x: 30, y: 50), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 48), .foregroundColor: NSColor.black])
            return true
        }
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { print("FAIL: fixture image"); exit(1) }
        let item = ClipboardItem(payload: ClipboardPayload(items: [["public.png": png]]), source: "Check")
        ImageTextRecognizer.recognize(item, level: .fast) { text in
            guard let text, text.contains("4711") else { print("FAIL: recognition returned \(text ?? "nil")"); fflush(stdout); exit(1) }
            print("PASS: image text recognition finds rendered text")
            fflush(stdout)
            checkCopiedHUD(model: model, controller: controller)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { print("FAIL: recognition timed out"); fflush(stdout); exit(1) }
    }
}
#endif
