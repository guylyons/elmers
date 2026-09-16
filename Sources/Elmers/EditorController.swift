import AppKit
import ElmersCore

final class EditorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Escape reaches the text view as `cancelOperation(_:)`; route it to the editor's Cancel.
final class EditorTextView: NSTextView {
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Floating rich-text editor modeled on Paste's "New Text Item" and "Edit" windows:
/// Cancel · Bold Italic Underline Strikethrough · Writing Tools · Create/Save, then the text,
/// then "N characters · N words · N lines".
@MainActor
final class EditorController: NSObject, NSTextViewDelegate {
    let panel: EditorPanel
    let textView: EditorTextView
    private let footer = NSTextField(labelWithString: "")
    private let confirmButton = NSButton(title: "Create", target: nil, action: nil)
    private var completion: ((ClipboardPayload?) -> Void)?
    private(set) var editingItem: ClipboardItem?

    override init() {
        panel = EditorPanel(contentRect: .init(x: 0, y: 0, width: 500, height: 360), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let scroll = NSScrollView()
        textView = EditorTextView(frame: .zero)
        textView.autoresizingMask = [.width]; textView.isVerticallyResizable = true; textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView; scroll.hasVerticalScroller = true
        super.init()
        textView.onCancel = { [weak self] in self?.cancel() }
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating; panel.isMovableByWindowBackground = true; panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "Elmers Editor"

        let material = NSVisualEffectView()
        // Paste's editor is a light, mostly opaque gray sheet in either appearance.
        material.material = .underWindowBackground; material.blendingMode = .behindWindow; material.state = .active
        material.appearance = NSAppearance(named: .aqua)
        material.wantsLayer = true; material.layer?.cornerRadius = 12; material.layer?.masksToBounds = true
        panel.contentView = material

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded; cancel.controlSize = .small; cancel.font = .systemFont(ofSize: 12)
        confirmButton.target = self; confirmButton.action = #selector(confirm)
        confirmButton.bezelStyle = .rounded; confirmButton.controlSize = .small; confirmButton.font = .systemFont(ofSize: 12)
        confirmButton.keyEquivalent = "\r"; confirmButton.keyEquivalentModifierMask = .command
        confirmButton.bezelColor = .controlAccentColor

        let formatting = NSStackView(views: [
            formatButton("B", weight: .bold, action: #selector(toggleBold), tip: "Bold (⌘B)"),
            formatButton("I", italic: true, action: #selector(toggleItalic), tip: "Italic (⌘I)"),
            formatButton("U", underline: true, action: #selector(toggleUnderline), tip: "Underline (⌘U)"),
            formatButton("S", strike: true, action: #selector(toggleStrikethrough), tip: "Strikethrough")
        ])
        formatting.spacing = 22
        if #available(macOS 15.2, *) {
            let tools = NSButton(image: NSImage(systemSymbolName: "apple.writing.tools", accessibilityDescription: "Writing Tools")
                                    ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Writing Tools")!,
                                 target: self, action: #selector(showWritingTools))
            tools.isBordered = false; tools.toolTip = "Writing Tools"; tools.setAccessibilityLabel("Writing Tools")
            formatting.addArrangedSubview(tools); formatting.setCustomSpacing(34, after: formatting.arrangedSubviews[3])
        }
        let leftSpacer = NSView(), rightSpacer = NSView()
        let toolbar = NSStackView(views: [cancel, leftSpacer, formatting, rightSpacer, confirmButton])
        toolbar.orientation = .horizontal; toolbar.distribution = .fill; toolbar.alignment = .centerY
        // Equal spacers keep the formatting group centered between Cancel and Create/Save, as in Paste.
        leftSpacer.widthAnchor.constraint(equalTo: rightSpacer.widthAnchor).isActive = true
        for spacer in [leftSpacer, rightSpacer] { spacer.setContentHuggingPriority(.defaultLow, for: .horizontal) }
        toolbar.edgeInsets = .init(top: 8, left: 10, bottom: 6, right: 10)

        textView.isRichText = true; textView.allowsUndo = true; textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 6, height: 8); textView.delegate = self
        textView.usesFindPanel = false; textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.setAccessibilityLabel("Text")
        scroll.borderType = .noBorder; scroll.drawsBackground = true; scroll.backgroundColor = .textBackgroundColor
        scroll.wantsLayer = true; scroll.layer?.cornerRadius = 8; scroll.layer?.masksToBounds = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        footer.font = .systemFont(ofSize: 12); footer.textColor = .secondaryLabelColor
        footer.setAccessibilityLabel("Statistics")
        let column = NSStackView(views: [toolbar, scroll, footer])
        column.orientation = .vertical; column.alignment = .leading; column.spacing = 6
        column.edgeInsets = .init(top: 0, left: 0, bottom: 10, right: 0)
        column.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: material.leadingAnchor), column.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            column.topAnchor.constraint(equalTo: material.topAnchor), column.bottomAnchor.constraint(equalTo: material.bottomAnchor),
            toolbar.widthAnchor.constraint(equalTo: column.widthAnchor),
            scroll.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 8), scroll.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -8),
            footer.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 14)
        ])
    }

    /// Opens the editor for a new item (`item == nil`) or an existing text item.
    /// `completion` receives the edited payload, or nil when cancelled.
    func open(_ item: ClipboardItem?, completion: @escaping (ClipboardPayload?) -> Void) {
        editingItem = item; self.completion = completion
        confirmButton.title = item == nil ? "Create" : "Save"
        textView.string = ""
        if let item {
            if let rtf = item.payload.items.first?[NSPasteboard.PasteboardType.rtf.rawValue], let text = NSAttributedString(rtf: rtf, documentAttributes: nil) {
                textView.textStorage?.setAttributedString(text)
            } else { textView.string = item.text }
        }
        textView.typingAttributes = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.textColor]
        refresh()
        let size = item == nil ? NSSize(width: 500, height: 360) : NSSize(width: 390, height: 316)
        // Same screen as the history panel: the one under the pointer, as Paste positions its editor.
        let screen = (NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main)?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2 + 120, width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
    }

    var statistics: String {
        let text = textView.string
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let lines = text.isEmpty ? 0 : text.components(separatedBy: .newlines).count
        return "\(text.count) character\(text.count == 1 ? "" : "s") · \(words) word\(words == 1 ? "" : "s") · \(lines) line\(lines == 1 ? "" : "s")"
    }
    private func refresh() {
        footer.stringValue = statistics
        confirmButton.isEnabled = !textView.string.isEmpty
    }
    func textDidChange(_ notification: Notification) { refresh() }

    /// Plain text always; RTF only when formatting was applied, so unformatted items stay plain when pasted.
    var payload: ClipboardPayload? {
        guard let storage = textView.textStorage, !storage.string.isEmpty else { return nil }
        var representations = [NSPasteboard.PasteboardType.string.rawValue: Data(storage.string.utf8)]
        if Self.hasFormatting(storage), let rtf = storage.rtf(from: NSRange(location: 0, length: storage.length), documentAttributes: [:]) {
            representations[NSPasteboard.PasteboardType.rtf.rawValue] = rtf
        }
        return ClipboardPayload(items: [representations])
    }
    static func hasFormatting(_ storage: NSAttributedString) -> Bool {
        var found = false
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, _, stop in
            if attributes[.underlineStyle] != nil || attributes[.strikethroughStyle] != nil { found = true }
            if let font = attributes[.font] as? NSFont, !font.fontDescriptor.symbolicTraits.intersection([.bold, .italic]).isEmpty { found = true }
            if found { stop.pointee = true }
        }
        return found
    }

    @objc func confirm() { guard let payload else { return }; finish(payload) }
    @objc func cancel() { finish(nil) }
    private func finish(_ payload: ClipboardPayload?) {
        panel.orderOut(nil)
        let completion = self.completion
        self.completion = nil; editingItem = nil
        completion?(payload)
    }

    // MARK: - Formatting

    @objc func toggleBold() { toggleTrait(.bold) }
    @objc func toggleItalic() { toggleTrait(.italic) }
    @objc func toggleUnderline() { toggleAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue) }
    @objc func toggleStrikethrough() { toggleAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue) }
    @objc func showWritingTools() {
        if #available(macOS 15.2, *) { NSApp.sendAction(#selector(NSResponder.showWritingTools(_:)), to: textView, from: self) }
    }
    private func toggleTrait(_ trait: NSFontDescriptor.SymbolicTraits) {
        guard let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        func toggled(_ font: NSFont) -> NSFont {
            var traits = font.fontDescriptor.symbolicTraits
            if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
            return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
        }
        if range.length == 0 {
            let font = (textView.typingAttributes[.font] as? NSFont) ?? .systemFont(ofSize: 13)
            textView.typingAttributes[.font] = toggled(font)
            return
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = (value as? NSFont) ?? .systemFont(ofSize: 13)
            storage.addAttribute(.font, value: toggled(font), range: subrange)
        }
        storage.endEditing()
        textView.didChangeText()
    }
    private func toggleAttribute(_ key: NSAttributedString.Key, value: Int) {
        guard let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            if textView.typingAttributes[key] != nil { textView.typingAttributes.removeValue(forKey: key) } else { textView.typingAttributes[key] = value }
            return
        }
        let present = storage.attribute(key, at: range.location, effectiveRange: nil) != nil
        storage.beginEditing()
        if present { storage.removeAttribute(key, range: range) } else { storage.addAttribute(key, value: value, range: range) }
        storage.endEditing()
        textView.didChangeText()
    }
    private func formatButton(_ title: String, weight: NSFont.Weight = .regular, italic: Bool = false, underline: Bool = false, strike: Bool = false, action: Selector, tip: String) -> NSButton {
        var font = NSFont.systemFont(ofSize: 13, weight: weight)
        if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        if underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        let button = NSButton(title: title, target: self, action: action)
        button.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        button.isBordered = false; button.toolTip = tip; button.setAccessibilityLabel(tip)
        return button
    }
}
