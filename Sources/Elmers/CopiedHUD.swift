import AppKit
import SwiftUI

/// Paste's confirmation overlay: a 200-pt translucent square centered near the bottom of the panel's
/// screen, shown for about a second after an item is copied in clipboard mode. Its "Enable Direct Paste ›"
/// button opens Settings, where direct paste can be turned on.
@MainActor
final class CopiedHUD {
    let panel: NSPanel
    private var hideWork: DispatchWorkItem?
    var openSettings: (() -> Void)?
    static let size: CGFloat = 200
    static let bottomInset: CGFloat = 140
    static let duration: TimeInterval = 1.0

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.title = String(localized: "Copied")
    }
    var isVisible: Bool { panel.isVisible }

    func show(on screen: NSScreen?, offerDirectPaste: Bool) {
        hideWork?.cancel()
        let material = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        // Paste's HUD is a light, mostly opaque gray (about #868686 at 87%) over a soft blur, in either appearance.
        material.material = .hudWindow; material.blendingMode = .behindWindow; material.state = .active
        material.appearance = NSAppearance(named: .aqua)
        material.wantsLayer = true; material.layer?.cornerRadius = 18; material.layer?.cornerCurve = .continuous; material.layer?.masksToBounds = true
        let hosting = NSHostingView(rootView: CopiedHUDView(offerDirectPaste: offerDirectPaste) { [weak self] in self?.hide(); self?.openSettings?() })
        hosting.frame = material.bounds; hosting.autoresizingMask = [.width, .height]
        material.addSubview(hosting)
        panel.contentView = material
        if let frame = (screen ?? NSScreen.main)?.frame {
            panel.setFrameOrigin(NSPoint(x: (frame.midX - Self.size / 2).rounded(), y: frame.minY + Self.bottomInset))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration, execute: work)
    }
    private func fadeOut() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.hideWork?.isCancelled == false || self.hideWork == nil else { return }
                self.panel.orderOut(nil); self.panel.alphaValue = 1
            }
        })
    }
    func hide() {
        hideWork?.cancel(); hideWork = nil
        panel.orderOut(nil); panel.alphaValue = 1
    }
}

struct CopiedHUDView: View {
    let offerDirectPaste: Bool
    let enableDirectPaste: () -> Void
    /// Measured from Paste: a 72-pt checkmark centered 68 pt from the top, "Copied" at 142 pt, the button at 166 pt.
    var body: some View {
        ZStack {
            Color(white: 0.5).opacity(0.72)
            Image(systemName: "checkmark").font(.system(size: 89, weight: .light)).position(x: CopiedHUD.size / 2, y: 68)
            Text("Copied").font(.system(size: 22)).position(x: CopiedHUD.size / 2, y: 142)
            if offerDirectPaste {
                Button(action: enableDirectPaste) {
                    HStack(spacing: 3) { Text("Enable Direct Paste"); Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)) }
                }.buttonStyle(.plain).font(.system(size: 13)).position(x: CopiedHUD.size / 2, y: 166)
                    .accessibilityLabel("Enable Direct Paste")
            }
        }
        .foregroundStyle(Color(white: 0.12))
        .frame(width: CopiedHUD.size, height: CopiedHUD.size)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Copied")
    }
}
