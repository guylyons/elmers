import AppKit

@MainActor
enum AboutPanel {
    static func show() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        if let url = Bundle.main.url(forResource: "AboutElmers", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            options[.applicationIcon] = image
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }
}
