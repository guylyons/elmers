import SwiftUI
import ApplicationServices
import ElmersCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var section = "General"
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Elmers").font(.title2.bold()).padding(.horizontal, 12).padding(.vertical, 20)
                ForEach([("General", "gearshape"), ("Privacy", "hand.raised"), ("Shortcuts", "keyboard")], id: \.0) { title, symbol in
                    Button { section = title } label: {
                        Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .background(section == title ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Text("Elmers 0.1\nClipboard foundation").font(.caption).foregroundStyle(.secondary).padding(12)
            }.padding(12).frame(width: 170).background(.ultraThinMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 20) {
                Text(section).font(.title2.bold())
                if section == "General" { general }
                else if section == "Privacy" { privacy }
                else { shortcuts }
                Spacer()
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(width: 648, height: 560)
    }
    private var general: some View {
        VStack(alignment: .leading, spacing: 22) {
            Picker("Paste items", selection: $model.directPaste) {
                Text("To clipboard").tag(false)
                Text("To active app").tag(true)
            }.pickerStyle(.radioGroup)
            Text("Direct paste needs Accessibility access. Clipboard mode lets you paste with ⌘V.").font(.caption).foregroundStyle(.secondary)
            if model.directPaste {
                Button("Allow Accessibility Access…") {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                }
            }
            Divider()
            Picker("Keep history", selection: $model.retentionDays) {
                Text("Day").tag(1); Text("Week").tag(7); Text("Month").tag(30); Text("Year").tag(365); Text("Forever").tag(0)
            }
            Text("Pinned items are kept. This build keeps up to 2,000 unpinned items and captures items up to 32 MB.").font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack { Label(model.paused ? "Capture paused" : "Capture is running", systemImage: model.paused ? "pause.circle" : "checkmark.circle"); Spacer(); Button(model.paused ? "Resume" : "Pause") { model.paused ? model.resume() : model.pause(minutes: nil) } }
        }
    }
    private var privacy: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("Ignore confidential content", isOn: $model.ignoreConfidential)
            Text("Skip content marked as concealed by its source app.").font(.caption).foregroundStyle(.secondary)
            Toggle("Ignore transient content", isOn: $model.ignoreTransient)
            Text("Skip temporary and automatically generated clipboard entries.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Ignored applications").font(.headline)
            Text("One application bundle identifier per line.").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $model.excludedApps).font(.system(.body, design: .monospaced)).frame(height: 130).padding(5).background(.background, in: RoundedRectangle(cornerRadius: 7))
            Text("History stays on this Mac. Elmers does not fetch links or upload clipboard content.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 18) {
            recorder("Activate Elmers", binding: $model.shortcuts.activation)
            recorder("Show next Pinboard", binding: $model.shortcuts.nextBoard)
            recorder("Show previous Pinboard", binding: $model.shortcuts.previousBoard)
            Picker("Quick Paste", selection: $model.shortcuts.quickPasteModifier) {
                Text("⌘ Command").tag(KeyModifiers.command)
                Text("⌃ Control").tag(KeyModifiers.control)
                Text("⌥ Option").tag(KeyModifiers.option)
            }
            Text("+ 1…9").font(.caption).foregroundStyle(.secondary)
            Picker("Plain Text mode", selection: $model.shortcuts.plainTextModifier) {
                Text("⇧ Shift").tag(KeyModifiers.shift)
                Text("⌃ Control").tag(KeyModifiers.control)
                Text("⌥ Option").tag(KeyModifiers.option)
            }
            Divider()
            shortcut("Search / filters", "⌘F")
            shortcut("Paste / preview", "↩ / Space")
            shortcut("Edit / rename / open", "⌘E / ⌘R / ⌘O")
            shortcut("New item / pinboard", "⌘N / ⇧⌘N")
            shortcut("Delete / undo", "⌫ / ⌘Z")
            Button("Restore Defaults") { model.shortcuts = ShortcutSettings() }
            if let conflict = model.shortcutValidationError ?? model.shortcutConflict { Text(conflict).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func recorder(_ title: String, binding: Binding<KeyStroke?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            ShortcutRecorder(binding: binding, title: title) { model.shortcutRecordingChanged?($0) }
                .frame(width: 150, height: 26)
        }.font(.system(size: 13))
    }
    private func shortcut(_ title: String, _ keys: String) -> some View {
        HStack { Text(title); Spacer(); Text(keys).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary) }.font(.system(size: 13))
    }
}
