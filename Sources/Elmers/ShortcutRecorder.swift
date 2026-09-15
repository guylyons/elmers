import AppKit
import SwiftUI
import ElmersCore

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var binding: KeyStroke?
    var title: String
    var recordingChanged: (Bool) -> Void
    func makeNSView(context: Context) -> RecorderButton { RecorderButton() }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.binding = binding
        button.changed = { binding = $0 }
        button.recordingChanged = recordingChanged
        button.setAccessibilityLabel(title)
        button.refreshTitle()
    }

    final class RecorderButton: NSButton {
        var binding: KeyStroke?
        var changed: ((KeyStroke?) -> Void)?
        var recordingChanged: ((Bool) -> Void)?
        private(set) var recording = false
        private var windowObservers: [NSObjectProtocol] = []
        override var acceptsFirstResponder: Bool { true }
        init() {
            super.init(frame: .zero)
            bezelStyle = .rounded
            target = self; action = #selector(beginRecording)
            toolTip = "Click to record. Escape cancels; Delete clears."
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        func refreshTitle() { title = recording ? "Type shortcut…" : binding?.label ?? "Record Shortcut" }
        @objc func beginRecording() {
            window?.makeFirstResponder(self)
            recording = true; recordingChanged?(true); refreshTitle()
        }
        private func finish() { recording = false; recordingChanged?(false); refreshTitle() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
            windowObservers.removeAll()
            if recording { finish() }
            guard let window else { return }
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { if let self, self.recording { self.finish() } }
                })
            }
        }
        deinit { windowObservers.forEach { NotificationCenter.default.removeObserver($0) } }
        override func resignFirstResponder() -> Bool {
            if recording { finish() }
            return super.resignFirstResponder()
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event); return true
        }
        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            let stroke = KeyStroke(event.keyCode, KeyModifiers(event.modifierFlags))
            if stroke == KeyStroke(53) { finish(); return }
            if [51,117].contains(stroke.keyCode), stroke.modifiers.isEmpty {
                binding = nil; changed?(nil); finish(); return
            }
            guard !stroke.modifiers.intersection([.command, .control, .option]).isEmpty else {
                title = "Use ⌘, ⌃ or ⌥"; NSSound.beep(); return
            }
            binding = stroke; changed?(stroke); finish()
        }
    }
}
