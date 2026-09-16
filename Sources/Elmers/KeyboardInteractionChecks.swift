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
            (48, [], { !model.searchIsFocused }, "Tab focuses results"),
            (48, .shift, { model.searchIsFocused }, "Shift-Tab returns to search"),
            (125, .command, { model.selectedID == ids.last && !model.searchIsFocused }, "Command-Down selects last and focuses results"),
            (126, .command, { model.selectedID == ids.first }, "Command-Up selects first"),
            (124, [], { model.selectedID == ids.last }, "Right selects next item"),
            (124, [], { model.selectedID == ids.last }, "Right stops at last item"),
            (3, .command, { model.searchIsFocused }, "Search can be focused again"),
            (123, [], { model.selectedID == ids[ids.count - 2] && model.searchIsFocused }, "Left moves the selection while search keeps focus"),
            (124, [], { model.selectedID == ids.last && model.searchIsFocused }, "Right moves the selection while search keeps focus"),
            (36, [], { deliveries == [false] }, "Return from search delivers with a single press"),
            (48, [], { !model.searchIsFocused }, "Tab focuses results"),
            (36, [], { deliveries == [false, false] }, "Return delivers selection"),
            (36, .shift, { deliveries == [false, false, true] }, "Shift-Return delivers plain text"),
            (18, .command, { deliveries == [false, false, true, false] }, "Command-1 quick pastes"),
            (18, [.command, .shift], { deliveries == [false, false, true, false, true] }, "Shift-Command-1 quick pastes plain text")
        ]
        func step(_ index: Int) {
            guard index < steps.count else { checkReopening(model: model, controller: controller); return }
            let (code, flags, verify, description) = steps[index]
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: controller.panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
            NSApp.postEvent(event, atStart: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                guard verify() else { print("FAIL: \(description)"); fflush(stdout); exit(1) }
                print("PASS: \(description)")
                step(index + 1)
            }
        }
        step(0)
    }
    static func checkReopening(model: AppModel, controller: PanelController) {
        NotificationCenter.default.post(name: .elmersSearch, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard model.searchIsFocused else { print("FAIL: reopen setup search focus"); exit(1) }
            controller.hide(restoreFocus: false)
            controller.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard !model.searchIsFocused, !(controller.panel.firstResponder is NSTextView) else {
                    print("FAIL: reopening left search consuming navigation keys"); exit(1)
                }
                print("PASS: reopening restores results keyboard focus")
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
    static func checkEditor(controller: PanelController) {
        let model = controller.model, editor = controller.editor
        let countBefore = model.history.items.count
        controller.openEditor(nil)
        guard editor.panel.isVisible, !controller.panel.isVisible else { print("FAIL: editor did not replace the panel"); fflush(stdout); exit(1) }
        editor.textView.insertText("Hello editor\nsecond line", replacementRange: NSRange(location: 0, length: 0))
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
        checkDrag(model: model)
    }
    /// The drag provider must hand back every stored representation under its own type.
    static func checkDrag(model: AppModel) {
        let payload = ClipboardPayload(items: [["public.utf8-plain-text": Data("dragged".utf8), "public.rtf": Data("{\\rtf1 dragged}".utf8)]])
        let item = ClipboardItem(payload: payload, source: "Check")
        let provider = DragSupport.itemProvider(for: item)
        guard Set(provider.registeredTypeIdentifiers) == ["public.utf8-plain-text", "public.rtf"] else { print("FAIL: drag types \(provider.registeredTypeIdentifiers)"); fflush(stdout); exit(1) }
        let done = DispatchSemaphore(value: 0)
        var loaded: Data?
        _ = provider.loadDataRepresentation(forTypeIdentifier: "public.rtf") { data, _ in loaded = data; done.signal() }
        guard done.wait(timeout: .now() + 2) == .success, loaded == Data("{\\rtf1 dragged}".utf8) else { print("FAIL: drag data did not load"); fflush(stdout); exit(1) }
        print("PASS: drag provider offers every representation")
        checkRecognition(model: model)
    }
    /// Renders text into a PNG and confirms Vision makes it searchable.
    static func checkRecognition(model: AppModel) {
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
            fflush(stdout); exit(0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { print("FAIL: recognition timed out"); fflush(stdout); exit(1) }
    }
}
#endif
