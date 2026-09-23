import AppKit
import SwiftUI
import ElmersCore

/// Paste Stack: ⇧⌘C opens a small floating list; while it is open every copy joins it, and ⌘V pastes its entries one
/// by one into the frontmost app, each disappearing once used (Paste 6.3.11's help). ⌘V is taken system-wide only while
/// the Stack is open, holds entries and Accessibility is granted; otherwise ⌘V is left to the system.
@MainActor
final class StackController: ObservableObject {
    @Published private(set) var stack = PasteStack()
    private let model: AppModel
    private let pasteShortcut = GlobalShortcut()
    private var panel: NSPanel?
    var isOpen: Bool { panel?.isVisible == true }

    init(model: AppModel) {
        self.model = model
        pasteShortcut.onActivate = { [weak self] in Task { @MainActor in self?.pasteNext() } }
        model.onCapture = { [weak self] payload, source in
            guard let self, self.isOpen else { return }
            self.stack.push(payload, source: source); self.refreshPasteShortcut()
        }
    }

    func toggle() { isOpen ? close() : open() }

    func open() {
        if panel == nil {
            let panel = NSPanel(contentRect: .init(x: 0, y: 0, width: 264, height: 120), styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow, .fullSizeContentView],
                                backing: .buffered, defer: false)
            panel.title = String(localized: "Paste Stack"); panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.becomesKeyOnlyIfNeeded = true; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.setFrameAutosaveName("Elmers Paste Stack")
            // The window follows the list's size: it grows with its entries, up to Paste's 438-pt storyboard height.
            let host = NSHostingController(rootView: StackView(controller: self))
            host.sizingOptions = .preferredContentSize
            panel.contentViewController = host
            if !panel.setFrameUsingName("Elmers Paste Stack"), let screen = NSScreen.main?.visibleFrame {
                panel.setFrameTopLeftPoint(NSPoint(x: screen.maxX - 264 - 24, y: screen.maxY - 24))
            }
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshPasteShortcut() }
            }
            self.panel = panel
        }
        panel?.orderFrontRegardless()
        refreshPasteShortcut()
    }

    func close() { panel?.close(); refreshPasteShortcut() }
    func reverse() { stack.reverse() }
    func remove(_ id: UUID) { stack.remove(id); refreshPasteShortcut() }

    /// ⌘V belongs to the Stack only while it can act on it.
    private func refreshPasteShortcut() {
        let active = isOpen && !stack.isEmpty && AXIsProcessTrusted()
        pasteShortcut.register(active ? KeyStroke(9, .command) : nil)
    }

    /// Puts the next entry on the clipboard and pastes it into the frontmost app. The entry leaves the Stack only
    /// once the clipboard write succeeded; the synthetic ⌘V goes out while the Stack's own ⌘V is released, so it
    /// reaches the app instead of coming back here.
    private func pasteNext() {
        guard let entry = stack.next else { refreshPasteShortcut(); return }
        guard model.copy(ClipboardItem(payload: entry.payload, source: entry.source)) else { return }
        pasteShortcut.register(nil)
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cgSessionEventTap)
        }
        stack.consume(entry.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.refreshPasteShortcut() }
    }
}

/// The Stack window's list, in paste order. Its look is provisional until Paste's own Stack window is compared.
private struct StackView: View {
    @ObservedObject var controller: StackController
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { controller.reverse() } label: { Image(systemName: "arrow.up.arrow.down") }
                    .buttonStyle(.plain).help("Reverse order").accessibilityLabel("Reverse order")
            }.padding(.horizontal, 10).frame(height: 28)
            if controller.stack.isEmpty {
                Text("Copy items to add them to the stack").font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(controller.stack.pasteOrder) { entry in
                            Text(entry.payload.text.isEmpty ? String(localized: "Image") : entry.payload.text)
                                .font(.system(size: 12)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                                .contextMenu { Button("Delete") { controller.remove(entry.id) } }
                        }
                    }.padding(8)
                }.frame(height: min(CGFloat(controller.stack.entries.count) * 52 + 8, 400))
            }
        }.frame(width: 264)
    }
}
