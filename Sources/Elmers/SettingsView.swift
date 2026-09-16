import SwiftUI
import AppKit
import ApplicationServices
import UniformTypeIdentifiers
import ElmersCore

/// Settings window modeled on Paste 6.3.11: a sidebar with General, Privacy and Shortcuts,
/// grouped form rows in the detail area, and a Help Center link at the bottom of the sidebar.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var section: Section = .general
    @State private var helpVisible = false
    enum Section: String, CaseIterable, Identifiable {
        case general = "General", privacy = "Privacy", shortcuts = "Shortcuts"
        var id: String { rawValue }
        var symbol: String {
            switch self { case .general: return "gearshape"; case .privacy: return "hand.raised"; case .shortcuts: return "keyboard" }
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 2) {
                    ForEach(Section.allCases) { item in
                        Button { section = item } label: {
                            Label(item.rawValue, systemImage: item.symbol).font(.system(size: 13, weight: .medium))
                                .foregroundStyle(section == item ? Color.white : Color.primary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 30)
                                .background(section == item ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).accessibilityAddTraits(section == item ? .isSelected : [])
                    }
                }.padding(.horizontal, 10).padding(.top, 12)
                Spacer()
                Button { helpVisible = true } label: { Label("Help Center", systemImage: "questionmark.circle") }
                    .buttonStyle(.plain).font(.system(size: 13)).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 200).background(.bar)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(section.rawValue).font(.system(size: 15, weight: .semibold)).padding(.horizontal, 30).padding(.top, 18)
                switch section {
                case .general: GeneralSettings(model: model)
                case .privacy: PrivacySettings(model: model)
                case .shortcuts: ShortcutSettingsView(model: model)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 640, height: 564)
        .sheet(isPresented: $helpVisible) { KeyboardHelp() }
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
        Form {
            Section {
                Toggle("Open at login", isOn: $model.openAtLogin)
                Toggle("Run in background", isOn: $model.runInBackground)
                LabeledContent("iCloud sync") {
                    HStack(spacing: 6) {
                        Text("Not available").foregroundStyle(.secondary)
                        Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                            .help("Elmers keeps history on this Mac. Syncing between devices is not implemented.")
                        Toggle("", isOn: .constant(false)).labelsHidden().disabled(true)
                    }
                }
                Toggle("Sound effects", isOn: $model.soundEffects)
            }
            Section("Paste Items") {
                option("To active app", "Paste selected items directly to the application you are currently using.", selected: model.directPaste) { model.directPaste = true }
                option("To clipboard", "Copy selected items to the system clipboard to paste manually later.", selected: !model.directPaste) { model.directPaste = false }
                if model.directPaste && !trusted {
                    Button("Enable accessibility access") {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        trusted = AXIsProcessTrustedWithOptions(options)
                    }.buttonStyle(.link)
                }
                Toggle("Always paste as Plain Text", isOn: $model.alwaysPlainText).toggleStyle(.checkbox)
            }
            Section("Keep History") {
                VStack(spacing: 6) {
                    Slider(value: retentionIndex, in: 0...4, step: 1)
                    HStack {
                        ForEach(["Day", "Week", "Month", "Year", "Forever"], id: \.self) { label in
                            Text(label).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: label == "Day" ? .leading : label == "Forever" ? .trailing : .center)
                        }
                    }
                }
                HStack { Spacer(); Button("Erase History…") { confirmErase = true }.disabled(!model.canEdit) }
            }
        }
        .formStyle(.grouped).toggleStyle(.switch).scrollContentBackground(.hidden)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in trusted = AXIsProcessTrusted() }
        .alert("You have items older than the new history limit. Do you want to delete these older items and apply the new limit?",
               isPresented: Binding(get: { pendingRetention != nil }, set: { if !$0 { pendingRetention = nil } })) {
            Button("Delete", role: .destructive) { if let days = pendingRetention { model.retentionDays = days } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Pinned items and Pinboards won't be deleted. This action cannot be undone.") }
        .alert("Erase History?", isPresented: $confirmErase) {
            Button("Erase", role: .destructive) { model.eraseHistory() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("All unpinned items will be deleted. Pinned items and Pinboards are kept.") }
    }
    /// Radio rows with the indicator on the left, as in Paste's "Paste Items" group.
    private func option(_ title: String, _ detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selected ? "inset.filled.circle" : "circle").font(.system(size: 15))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary).padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }.contentShape(Rectangle()).padding(.vertical, 2)
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct PrivacySettings: View {
    @ObservedObject var model: AppModel
    @State private var selectedApp: String?
    var body: some View {
        Form {
            Section {
                row("Show during screen sharing", "Allow Elmers to appear to others when you share your screen.", $model.showDuringScreenSharing)
            }
            Section {
                row("Ignore confidential content", "Do not save passwords and sensitive data when detected.", $model.ignoreConfidential)
                row("Ignore transient content", "Do not save temporary data generated by other apps.", $model.ignoreTransient)
            }
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ignore Applications").font(.system(size: 13, weight: .semibold))
                    Text("Do not save content copied from the applications below.").font(.system(size: 11)).foregroundStyle(.secondary)
                }.listRowSeparator(.hidden)
                VStack(spacing: 0) {
                    List(model.excludedBundleIDs, id: \.self, selection: $selectedApp) { id in
                        HStack(spacing: 8) {
                            Image(nsImage: Self.icon(for: id)).resizable().frame(width: 22, height: 22)
                            Text(Self.name(for: id))
                        }.padding(.vertical, 2)
                    }
                    .frame(height: max(60, CGFloat(model.excludedBundleIDs.count) * 30 + 8)).scrollContentBackground(.hidden)
                    .overlay { if model.excludedBundleIDs.isEmpty { Text("No items").foregroundStyle(.secondary) } }
                    Divider()
                    HStack(spacing: 0) {
                        Button { addApplication() } label: { Image(systemName: "plus").frame(width: 24, height: 22) }
                        Divider().frame(height: 16)
                        Button { if let selectedApp { model.includeApp(bundleID: selectedApp); self.selectedApp = nil } } label: { Image(systemName: "minus").frame(width: 24, height: 22) }
                            .disabled(selectedApp == nil)
                        Spacer()
                    }.buttonStyle(.borderless).padding(.horizontal, 4)
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            }
        }.formStyle(.grouped).toggleStyle(.switch).scrollContentBackground(.hidden)
    }
    private func row(_ title: String, _ detail: String, _ binding: Binding<Bool>) -> some View {
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
        panel.prompt = "Add"; panel.message = "Choose applications whose copied content should not be saved."
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
        VStack(spacing: 0) {
            Form {
                Section {
                    recorder("Activate Elmers", binding: $model.shortcuts.activation)
                }
                Section {
                    recorder("Show next Pinboard", binding: $model.shortcuts.nextBoard)
                    recorder("Show previous Pinboard", binding: $model.shortcuts.previousBoard)
                }
                Section {
                    LabeledContent("Quick Paste") {
                        HStack(spacing: 6) {
                            Picker("", selection: $model.shortcuts.quickPasteModifier) {
                                Text("⌘ Command").tag(KeyModifiers.command)
                                Text("⌃ Control").tag(KeyModifiers.control)
                                Text("⌥ Option").tag(KeyModifiers.option)
                            }.labelsHidden().fixedSize()
                            Text("+ 1…9")
                        }
                    }
                    LabeledContent("Plain Text mode") {
                        Picker("", selection: $model.shortcuts.plainTextModifier) {
                            Text("⇧ Shift").tag(KeyModifiers.shift)
                            Text("⌃ Control").tag(KeyModifiers.control)
                            Text("⌥ Option").tag(KeyModifiers.option)
                        }.labelsHidden().fixedSize()
                    }
                }
            }
            .formStyle(.grouped).scrollContentBackground(.hidden).scrollDisabled(true).frame(height: 300)
            VStack(alignment: .trailing, spacing: 8) {
                Button("Reset shortcuts to default…") { confirmReset = true }
                if let conflict = model.shortcutValidationError ?? model.shortcutConflict {
                    Text(conflict).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
            }.padding(.horizontal, 30).frame(maxWidth: .infinity, alignment: .trailing)
            Spacer()
        }
        .alert("Reset shortcuts to default?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { model.shortcuts = ShortcutSettings() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Are you sure you want to reset all shortcuts to their default values?") }
    }
    private func recorder(_ title: String, binding: Binding<KeyStroke?>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                ShortcutRecorder(binding: binding, title: title) { model.shortcutRecordingChanged?($0) }.frame(width: 120, height: 24)
                Button { binding.wrappedValue = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).disabled(binding.wrappedValue == nil).help("Remove")
            }
        }
    }
}
