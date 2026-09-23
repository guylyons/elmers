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
            // Paste's recorder is a flat gray field (#60605F in dark mode) with the shortcut centered in light text.
            isBordered = false; wantsLayer = true
            layer?.cornerRadius = 6; layer?.cornerCurve = .continuous
            target = self; action = #selector(beginRecording)
            toolTip = "Click to record. Escape cancels; Delete clears."
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        func refreshTitle() {
            // Paste 6.3.11's recorder reads "Recording" while it listens and "None" when no shortcut is set.
            let text = recording ? "Recording" : binding?.label ?? "None"
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            attributedTitle = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
        }
        override var wantsUpdateLayer: Bool { true }
        override func updateLayer() {
            let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            layer?.backgroundColor = (recording ? NSColor.controlAccentColor.withAlphaComponent(0.35) : dark ? NSColor(white: 0x60 / 255.0, alpha: 1) : NSColor(white: 0, alpha: 0.09)).cgColor
        }
        @objc func beginRecording() {
            window?.makeFirstResponder(self)
            recording = true; recordingChanged?(true); refreshTitle(); needsDisplay = true
        }
        private func finish() { recording = false; recordingChanged?(false); refreshTitle(); needsDisplay = true }
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
