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
            (36, [], { !model.searchIsFocused && deliveries.isEmpty }, "Return leaves search without pasting"),
            (36, [], { deliveries == [false] }, "Return delivers selection"),
            (36, .shift, { deliveries == [false, true] }, "Shift-Return delivers plain text"),
            (18, .command, { deliveries == [false, true, false] }, "Command-1 quick pastes"),
            (18, [.command, .shift], { deliveries == [false, true, false, true] }, "Shift-Command-1 quick pastes plain text")
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
        fflush(stdout); exit(0)
    }
}
#endif
