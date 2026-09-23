import AppKit
import SwiftUI
import ElmersCore

/// First-run setup, following the steps in Paste 6.3.11's strings: a welcome ("A Better Way to Copy and Paste" · Get
/// Started), Quick Start (activation shortcut, how long to keep history, iCloud sync, running in the background), then
/// the Accessibility request ("Paste to Any App"). It ends on the panel with a Useful Links pinboard. Paste's first run
/// could not be replayed, so the wording is Paste's and the layout is Elmers' own, built from its Settings components.
@MainActor
final class OnboardingController {
    private var window: NSWindow?
    private let model: AppModel
    var finished: (() -> Void)?
    init(model: AppModel) { self.model = model }

    func show() {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 520, height: 520), styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden; window.isReleasedWhenClosed = false
        window.title = String(localized: "Welcome")
        window.contentView = NSHostingView(rootView: OnboardingView(model: model) { [weak self] in self?.close() })
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
    private func close() {
        window?.close(); window = nil
        model.onboardingCompleted = true
        finished?()
    }
}

private struct OnboardingView: View {
    enum Step { case welcome, quickStart, accessibility }
    @ObservedObject var model: AppModel
    let done: () -> Void
    @State private var step: Step = {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["ELMERS_ONBOARDING_STEP"] {
        case "quickStart": return .quickStart
        case "accessibility": return .accessibility
        default: break
        }
        #endif
        return .welcome
    }()
    @State private var trusted = AXIsProcessTrusted()
    @State private var askedForAccess = false

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .welcome: welcome
            case .quickStart: quickStart
            case .accessibility: accessibility
            }
        }
        .frame(width: 520, height: 520)
        .background(SettingsStyle.window)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in trusted = AXIsProcessTrusted() }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 128, height: 128)
            Text("A Better Way to Copy and Paste").font(.system(size: 26, weight: .bold)).multilineTextAlignment(.center)
            Text("Elmers is a time machine for your Clipboard that lets you instantly find anything you’ve ever copied and use it whenever you need it again.")
                .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
            Spacer()
            Button("Get Started") { step = .quickStart }.keyboardShortcut(.defaultAction).controlSize(.large)
        }.padding(40)
    }

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Quick Start").font(.system(size: 22, weight: .bold))
            Text("Set up and start using Elmers.").font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 4)
            SettingsGroup {
                row("Activation shortcut", "Instantly access Elmers in any app") {
                    ShortcutRecorder(binding: $model.shortcuts.activation, title: String(localized: "Activation shortcut")) { model.shortcutRecordingChanged?($0) }
                        .frame(width: 121, height: 25)
                }
                SettingsSeparator()
                row("Clipboard history", "How long to retain copied content") {
                    Picker("", selection: $model.retentionDays) {
                        Text("Day").tag(1); Text("Week").tag(7); Text("Month").tag(30); Text("Year").tag(365); Text("Unlimited").tag(0)
                    }
                    .labelsHidden().fixedSize()
                    .help(model.retentionDays == 0 ? Text("Unlimited history may increase your disk space usage") : Text(""))
                }
                SettingsSeparator()
                row("iCloud sync", "Securely sync your data across all devices") {
                    Text("Not available").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                SettingsSeparator()
                row("Run in background", "Open at login and always keep running") {
                    SettingsSwitch(isOn: Binding(get: { model.openAtLogin && model.runInBackground },
                                                 set: { model.openAtLogin = $0; model.runInBackground = $0 }))
                }
            }.padding(.top, 24)
            Spacer()
            HStack { Spacer(); Button("Continue") { if trusted { done() } else { step = .accessibility } }.keyboardShortcut(.defaultAction).controlSize(.large) }
        }.padding(32)
    }

    private var accessibility: some View {
        VStack(spacing: 16) {
            Spacer()
            PasteModeIllustration(directPaste: true).frame(width: 192, height: 128).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("Paste to Any App").font(.system(size: 22, weight: .bold))
            Text("To have the best experience and paste directly to other applications, allow Elmers to access the accessibility features of your Mac in System Settings.")
                .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
            Spacer()
            if trusted {
                Button("Continue") { done() }.keyboardShortcut(.defaultAction).controlSize(.large)
            } else if askedForAccess {
                Button("Open System Settings") { openAccessibilitySettings() }.keyboardShortcut(.defaultAction).controlSize(.large)
                Button("I’m Having an Issue") { NSWorkspace.shared.open(Onboarding.supportURL) }.buttonStyle(.link)
            } else {
                Button("Allow Access") {
                    askedForAccess = true; model.askedForAccessibility = true
                    trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
                }.keyboardShortcut(.defaultAction).controlSize(.large)
                Button("I’ll Do It Later") { done() }.buttonStyle(.link)
            }
        }.padding(40)
    }

    private func row<Control: View>(_ title: LocalizedStringKey, _ detail: LocalizedStringKey, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            control()
        }.padding(.horizontal, 12).padding(.vertical, 9)
    }
    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
}

enum Onboarding {
    static let guideURL = URL(string: "https://github.com/guylyons/elmers#readme")!
    static let supportURL = URL(string: "https://github.com/guylyons/elmers/issues")!
}
