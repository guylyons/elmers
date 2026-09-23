import SwiftUI
import AppKit
import ApplicationServices
import UniformTypeIdentifiers
import ElmersCore

/// Settings window modeled on Paste 6.3.11: a 200-pt sidebar with General, Privacy and Shortcuts under the
/// window's traffic lights, the pane title on the traffic-light row, and rounded groups of 36-pt rows.
/// Geometry and dark-mode colors were measured from 2× captures of Paste's window (640×592).
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var section: Section = {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["ELMERS_SETTINGS_SECTION"], let section = Section(rawValue: name) { return section }
        #endif
        return .general
    }()
    @State private var helpVisible = false
    enum Section: String, CaseIterable, Identifiable {
        case general = "General", privacy = "Privacy", shortcuts = "Shortcuts"
        var id: String { rawValue }
        var symbol: String {
            switch self { case .general: return "gearshape"; case .privacy: return "hand.raised"; case .shortcuts: return "keyboard" }
        }
        var title: LocalizedStringKey {
            switch self { case .general: return "General"; case .privacy: return "Privacy"; case .shortcuts: return "Shortcuts" }
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(Section.allCases) { item in
                        Button { section = item } label: {
                            HStack(spacing: 0) {
                                Image(systemName: item.symbol).font(.system(size: 18))
                                    .foregroundStyle(section == item ? Color.white : SettingsStyle.sidebarIcon).frame(width: 37)
                                Text(item.title).font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(section == item ? Color.white : Color.primary)
                                Spacer(minLength: 0)
                            }
                            .frame(height: 32).contentShape(Rectangle())
                            .background(section == item ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }.buttonStyle(.plain).accessibilityAddTraits(section == item ? .isSelected : [])
                    }
                }.padding(.horizontal, 10).padding(.top, 50)
                Spacer()
                Button { helpVisible = true } label: { Label("Help Center", systemImage: "questionmark.circle") }
                    .buttonStyle(.plain).font(.system(size: 13)).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 200).background(SettingsStyle.sidebar)
            VStack(alignment: .leading, spacing: 0) {
                Text(section.title).font(.system(size: 15, weight: .semibold)).frame(height: 18).padding(.top, 17).padding(.leading, 11)
                ScrollView {
                    Group {
                        switch section {
                        case .general: GeneralSettings(model: model)
                        case .privacy: PrivacySettings(model: model)
                        case .shortcuts: ShortcutSettingsView(model: model)
                        }
                    }.padding(.top, 17)
                }.scrollBounceBehavior(.basedOnSize)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 640, height: 592)
        .background(SettingsStyle.window)
        .ignoresSafeArea()
        .sheet(isPresented: $helpVisible) { KeyboardHelp() }
    }
}

/// Dark values are measured from Paste 6.3.11; light mode falls back to system colors and is not yet compared.
enum SettingsStyle {
    private static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light })
    }
    static let window = dynamic(dark: NSColor(white: 0x28 / 255.0, alpha: 1), light: .windowBackgroundColor)
    static let sidebar = dynamic(dark: NSColor(white: 0x2A / 255.0, alpha: 1), light: NSColor(white: 0.93, alpha: 1))
    static let group = dynamic(dark: NSColor(white: 0x2C / 255.0, alpha: 1), light: NSColor(white: 1, alpha: 0.7))
    static let groupBorder = dynamic(dark: NSColor(white: 0x3A / 255.0, alpha: 1), light: NSColor(white: 0, alpha: 0.08))
    static let separator = dynamic(dark: NSColor(white: 0x3A / 255.0, alpha: 1), light: NSColor(white: 0, alpha: 0.08))
    /// Paste's sidebar symbols are blue (#138DFF as captured in Display P3).
    static let sidebarIcon = Color(.displayP3, red: 0.075, green: 0.553, blue: 1)
    static let rowHeight: CGFloat = 36
}

/// A rounded group of rows, as in Paste's settings panes; rows are separated with `SettingsSeparator`.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
        .background(SettingsStyle.group, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(SettingsStyle.groupBorder, lineWidth: 0.5))
    }
}

/// Paste's switches are the small size (about 35×16 pt), smaller than the regular SwiftUI switch.
struct SettingsSwitch: View {
    @Binding var isOn: Bool
    var body: some View { Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small) }
}

/// Paste's settings buttons (Erase History…, Reset shortcuts…): 24 pt tall, a faint white fill over the page and
/// 13-pt text, flatter than a standard push button.
struct SettingsButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13)).padding(.horizontal, 12).frame(height: 24)
            .background(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45).contentShape(Rectangle())
    }
}

/// The hairline between rows of a group, inset 12 pt from both sides.
struct SettingsSeparator: View {
    var body: some View { Rectangle().fill(SettingsStyle.separator).frame(height: 0.5).padding(.horizontal, 12) }
}

/// A group heading between groups: 13-pt bold, 30 pt below the previous group and 10.5 pt above the next.
struct SettingsHeader: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 13, weight: .bold))
            if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary) }
        }.padding(.leading, 12).padding(.top, 30).padding(.bottom, 10.5).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A single-line row: label on the left, control on the right, 12-pt insets.
struct SettingsRow<Control: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var control: Control
    var body: some View {
        HStack { Text(title); Spacer(minLength: 8); control }
            .font(.system(size: 13)).padding(.horizontal, 12).frame(height: SettingsStyle.rowHeight)
    }
}

/// A switch row with a title and a 12-pt description wrapping up to the switch, the switch aligned with the title.
struct SettingsDetailToggle: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @Binding var isOn: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            SettingsSwitch(isOn: $isOn)
        }.padding(.horizontal, 12).padding(.vertical, 10)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @State private var pendingRetention: Int?
    @State private var confirmErase = false
    @State private var trusted = AXIsProcessTrusted()
    private var retentionIndex: Binding<Double> {
        Binding(
            get: { Double(AppModel.retentionSteps.firstIndex(of: model.retentionDays) ?? 2) },
            set: { value in
                let days = AppModel.retentionSteps[Int(value.rounded())]
                guard days != model.retentionDays else { return }
                if model.unpinnedItemCount(olderThanRetentionDays: days) > 0 { pendingRetention = days } else { model.retentionDays = days }
            })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup {
                SettingsRow(title: "Open at login") { SettingsSwitch(isOn: $model.openAtLogin) }
                SettingsSeparator()
                SettingsRow(title: "Run in background") { SettingsSwitch(isOn: $model.runInBackground) }
                SettingsSeparator()
                SettingsRow(title: "iCloud sync") {
                    HStack(spacing: 6) {
                        Text("Not available").foregroundStyle(.secondary)
                        Image(systemName: "questionmark.circle").foregroundStyle(SettingsStyle.sidebarIcon)
                            .help("Elmers keeps history on this Mac. Syncing between devices is not implemented.")
                        SettingsSwitch(isOn: .constant(false)).disabled(true).padding(.leading, 8)
                    }
                }
                SettingsSeparator()
                SettingsRow(title: "Sound effects") { SettingsSwitch(isOn: $model.soundEffects) }
            }
            SettingsHeader(title: "Paste Items")
            SettingsGroup {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 14) {
                        option("To active app", "Paste selected items directly to the application you are currently using.", selected: model.directPaste) { model.directPaste = true }
                        option("To clipboard", "Copy selected items to the system clipboard to paste manually later.", selected: !model.directPaste) { model.directPaste = false }
                        if model.directPaste && !trusted {
                            Button("Enable accessibility access") {
                                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                                trusted = AXIsProcessTrustedWithOptions(options)
                            }.buttonStyle(.link).padding(.leading, 21)
                        }
                    }
                    PasteModeIllustration(directPaste: model.directPaste)
                }.padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 11.5)
                SettingsSeparator()
                HStack {
                    Toggle("Always paste as Plain Text", isOn: $model.alwaysPlainText).toggleStyle(.checkbox)
                    Spacer()
                }.font(.system(size: 13)).padding(.horizontal, 12).frame(height: SettingsStyle.rowHeight)
            }
            SettingsHeader(title: "Keep History")
            SettingsGroup {
                // Paste: slider 25 pt below the group top, labels 26 pt below the slider, Erase 40 pt below the labels.
                VStack(spacing: 8) {
                    RetentionSlider(value: retentionIndex).frame(height: 20)
                    RetentionLabels()
                    HStack { Spacer(); Button("Erase History…") { confirmErase = true }.buttonStyle(SettingsButtonStyle()).disabled(!model.canEdit) }.padding(.top, 15)
                }.padding(.horizontal, 12).padding(.top, 18).padding(.bottom, 12)
            }
        }
        .toggleStyle(.switch)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in trusted = AXIsProcessTrusted() }
        .alert("You have items older than the new history limit. Do you want to delete these older items and apply the new limit?",
               isPresented: Binding(get: { pendingRetention != nil }, set: { if !$0 { pendingRetention = nil } })) {
            Button("Delete", role: .destructive) { if let days = pendingRetention { model.retentionDays = days } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Pinned items and Pinboards won't be deleted. This action cannot be undone.") }
        .alert("Are you sure you want to erase your Clipboard History?", isPresented: $confirmErase) {
            Button("Erase", role: .destructive) { model.eraseHistory() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Pinned items and Pinboards won't be deleted. This action cannot be undone.") }
    }
    /// Radio rows with the indicator on the left and the description under the title, as in Paste's "Paste Items".
    private func option(_ title: LocalizedStringKey, _ detail: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 7) {
                RadioIndicator(selected: selected).padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A 14-pt radio indicator drawn like the system's: accent fill with a white dot when on, a gray well when off.
private struct RadioIndicator: View {
    let selected: Bool
    var body: some View {
        ZStack {
            if selected {
                Circle().fill(Color.accentColor)
                Circle().fill(.white).frame(width: 6, height: 6)
            } else {
                Circle().fill(Color.primary.opacity(0.14))
                Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            }
        }.frame(width: 14, height: 14)
    }
}

/// An original drawing beside the Paste Items choices: a history strip whose selected card goes either into an app
/// window (direct paste) or onto the clipboard. Paste shows its own artwork here; this is not a copy of it.
struct PasteModeIllustration: View {
    let directPaste: Bool
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(red: 0.97, green: 0.55, blue: 0.22), Color(red: 0.86, green: 0.30, blue: 0.16)], startPoint: .top, endPoint: .bottom)
            if directPaste {
                RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.55)).frame(width: 34, height: 30).offset(y: -26)
            } else {
                Image(systemName: "doc.on.clipboard.fill").font(.system(size: 18)).foregroundStyle(.white.opacity(0.9)).offset(x: 18, y: -26)
            }
            HStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5).fill(index == 2 ? Color.white : Color.white.opacity(0.35)).frame(width: 12, height: 10)
                }
            }.padding(.bottom, 4)
            Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .offset(x: directPaste ? -4 : 6, y: -16)
        }
        .frame(width: 96, height: 64).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A full-width native slider with five detents, like Paste's Keep History control. Tick marks are drawn separately
/// (`RetentionLabels`): with system tick marks macOS 26 swaps the round knob for a pill.
private struct RetentionSlider: NSViewRepresentable {
    @Binding var value: Double
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: 0, maxValue: 4, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.setAccessibilityLabel(String(localized: "Keep History"))
        return slider
    }
    func updateNSView(_ slider: NSSlider, context: Context) { context.coordinator.parent = self; slider.doubleValue = value }
    final class Coordinator: NSObject {
        var parent: RetentionSlider
        init(_ parent: RetentionSlider) { self.parent = parent }
        @objc func changed(_ slider: NSSlider) {
            let snapped = slider.doubleValue.rounded()
            if slider.doubleValue != snapped { slider.doubleValue = snapped }
            parent.value = snapped
        }
    }
}

/// Tick dots under the slider's five detents, then Day…Forever centered under them and kept inside the track at the ends.
private struct RetentionLabels: View {
    private let labels: [LocalizedStringKey] = ["Day", "Week", "Month", "Year", "Forever"]
    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 10, step = (geometry.size.width - 2 * inset) / 4
            ForEach(0..<5, id: \.self) { index in
                Circle().fill(Color.secondary.opacity(0.6)).frame(width: 3, height: 3).position(x: inset + CGFloat(index) * step, y: -2)
            }
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Text(label).font(.system(size: 12)).fixedSize()
                    .frame(width: 60, alignment: index == 0 ? .leading : index == 4 ? .trailing : .center)
                    .position(x: index == 0 ? 30 : index == 4 ? geometry.size.width - 30 : inset + CGFloat(index) * step, y: 8)
            }
        }.frame(height: 16)
    }
}

private struct PrivacySettings: View {
    @ObservedObject var model: AppModel
    @State private var selectedApp: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup {
                SettingsDetailToggle(title: "Show during screen sharing", detail: "Allow Elmers to appear to others when you share your screen.", isOn: $model.showDuringScreenSharing)
                SettingsSeparator()
                SettingsDetailToggle(title: "Generate link previews", detail: "Download web content for previews; may activate one-time or analytics-sensitive links.", isOn: $model.linkPreviews)
            }
            SettingsGroup {
                SettingsDetailToggle(title: "Ignore confidential content", detail: "Do not save passwords and sensitive data when detected.", isOn: $model.ignoreConfidential)
                SettingsSeparator()
                SettingsDetailToggle(title: "Ignore transient content", detail: "Do not save temporary data generated by other apps.", isOn: $model.ignoreTransient)
            }.padding(.top, 17)
            SettingsHeader(title: "Ignore Applications", detail: "Do not save content copied from the applications below.")
            SettingsGroup {
                ForEach(Array(model.excludedBundleIDs.enumerated()), id: \.element) { index, id in
                    if index > 0 { SettingsSeparator().padding(.leading, 36) }
                    HStack(spacing: 10) {
                        Image(nsImage: Self.icon(for: id)).resizable().frame(width: 28, height: 28)
                        Text(Self.name(for: id)).font(.system(size: 13))
                        Spacer()
                    }
                    .padding(.horizontal, 12).frame(height: 40)
                    .background(selectedApp == id ? Color.accentColor.opacity(0.25) : .clear)
                    .contentShape(Rectangle()).onTapGesture { selectedApp = selectedApp == id ? nil : id }
                    .accessibilityAddTraits(selectedApp == id ? [.isButton, .isSelected] : .isButton)
                }
                if model.excludedBundleIDs.isEmpty { Text("No items").font(.system(size: 13)).foregroundStyle(.secondary).frame(height: 40) }
                Rectangle().fill(SettingsStyle.separator).frame(height: 0.5)
                HStack(spacing: 0) {
                    Button { addApplication() } label: { Image(systemName: "plus").frame(width: 22, height: 22) }.help("Add Application")
                    Rectangle().fill(SettingsStyle.separator).frame(width: 0.5, height: 12)
                    Button { if let selectedApp { model.includeApp(bundleID: selectedApp); self.selectedApp = nil } } label: { Image(systemName: "minus").frame(width: 22, height: 22) }
                        .disabled(selectedApp == nil).help("Remove Application")
                    Spacer()
                }.buttonStyle(.borderless).font(.system(size: 12)).padding(.horizontal, 2).frame(height: 24)
            }
            // Elmers-only: Paste has no screenshot setting, so this group sits below Paste's layout.
            SettingsHeader(title: "Screenshots")
            SettingsGroup {
                SettingsDetailToggle(title: "Add saved screenshots to history", detail: "Screenshots stay in your macOS save location. Elmers keeps a copy for searching and pasting.", isOn: $model.captureScreenshots)
                if let folder = model.screenshotFolder {
                    SettingsSeparator()
                    HStack {
                        Label(folder.lastPathComponent, systemImage: "folder").lineLimit(1).truncationMode(.middle).help(folder.path)
                        Spacer()
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }.buttonStyle(.link)
                    }.font(.system(size: 12)).padding(.horizontal, 12).frame(height: SettingsStyle.rowHeight)
                }
                if model.captureScreenshots, let status = model.screenshotStatus {
                    SettingsSeparator()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(status).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if model.screenshotNeedsAccess { Button("Allow Folder Access…") { model.allowScreenshotFolderAccess() } }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    private func row(_ title: LocalizedStringKey, _ detail: LocalizedStringKey, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func addApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "Add"); panel.message = String(localized: "Choose applications whose copied content should not be saved.")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier { model.excludeApp(bundleID: id) }
        }
    }
    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
    static func icon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

private struct ShortcutSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var confirmReset = false
    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            SettingsGroup {
                recorder("Activate Elmers", binding: $model.shortcuts.activation)
            }
            SettingsGroup {
                recorder("Show next Pinboard", binding: $model.shortcuts.nextBoard)
                SettingsSeparator()
                recorder("Show previous Pinboard", binding: $model.shortcuts.previousBoard)
            }.padding(.top, 21)
            SettingsGroup {
                SettingsRow(title: "Quick Paste") {
                    HStack(spacing: 6) {
                        Picker("", selection: $model.shortcuts.quickPasteModifier) {
                            Text("⌘ Command").tag(KeyModifiers.command)
                            Text("⌃ Control").tag(KeyModifiers.control)
                            Text("⌥ Option").tag(KeyModifiers.option)
                        }.labelsHidden().fixedSize().buttonStyle(.borderless)
                        Text("+ 1…9")
                    }
                }
                SettingsSeparator()
                SettingsRow(title: "Plain Text mode") {
                    Picker("", selection: $model.shortcuts.plainTextModifier) {
                        Text("⇧ Shift").tag(KeyModifiers.shift)
                        Text("⌃ Control").tag(KeyModifiers.control)
                        Text("⌥ Option").tag(KeyModifiers.option)
                    }.labelsHidden().fixedSize().buttonStyle(.borderless)
                }
            }.padding(.top, 21)
            Button("Reset shortcuts to default…") { confirmReset = true }.buttonStyle(SettingsButtonStyle()).padding(.top, 21)
            if let conflict = model.shortcutValidationError ?? model.shortcutConflict {
                Text(conflict).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.trailing).padding(.top, 8)
            }
        }
        .alert("Reset shortcuts to default?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { model.shortcuts = ShortcutSettings() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Are you sure you want to reset all shortcuts to their default values?") }
    }
    /// Paste's recorder: a 121×25 gray field with the shortcut centered and a small × inside its right end.
    private func recorder(_ title: String.LocalizationValue, binding: Binding<KeyStroke?>) -> some View {
        let title = String(localized: title)
        return SettingsRow(title: LocalizedStringKey(title)) {
            ZStack(alignment: .trailing) {
                ShortcutRecorder(binding: binding, title: title) { model.shortcutRecordingChanged?($0) }.frame(width: 121, height: 25)
                Button { binding.wrappedValue = nil } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).frame(width: 20, height: 25) }
                    .buttonStyle(.plain).foregroundStyle(Color.white.opacity(0.8)).opacity(binding.wrappedValue == nil ? 0 : 1)
                    .disabled(binding.wrappedValue == nil).help("Remove").padding(.trailing, 2)
            }
        }
    }
}
