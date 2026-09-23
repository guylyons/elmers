import AppKit

/// Paste 6.3.11 shows one menu from both the panel's … button and a right-click on its menu bar icon:
/// About · New Text Item ⌘N · Settings… ⌘, · Help › · Pause › (Pause ⌘T, then timed pauses) · Quit ⌘Q.
/// Paste's web-only entries (Getting Started, Help Center, Product Updates, Feature Request, Contact Support,
/// diagnostics, Paste on Twitter) have no Elmers counterpart and are left out rather than shown dead.
@MainActor
enum AppMenu {
    static func make(model: AppModel, showKeyboardShortcuts: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item(String(localized: "About Elmers")) { AboutPanel.show() })
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "New Text Item"), key: "n", enabled: model.canEdit) { model.openEditor?(nil) })
        menu.addItem(item(String(localized: "Settings…"), key: ",") { model.showSettings?() })
        menu.addItem(.separator())
        menu.addItem(submenu(String(localized: "Help"), [item(String(localized: "Keyboard Shortcuts"), action: showKeyboardShortcuts)]))
        menu.addItem(.separator())
        if model.paused { menu.addItem(item(String(localized: "Resume Elmers")) { model.resume() }) }
        else {
            var pauses = [item(String(localized: "Pause"), key: "t") { model.pause(minutes: nil) }, NSMenuItem.separator()]
            for minutes in [15, 30, 60, 180, 480] {
                // "Pause for 15m", "Pause for 1h", as Paste shows them; the system abbreviates the duration in the user's language.
                let duration = DateComponentsFormatter.localizedString(from: DateComponents(hour: minutes < 60 ? nil : minutes / 60, minute: minutes < 60 ? minutes : nil), unitsStyle: .abbreviated) ?? "\(minutes)"
                pauses.append(item(String(localized: "Pause for \(duration)")) { model.pause(minutes: minutes) })
            }
            menu.addItem(submenu(String(localized: "Pause Elmers"), pauses))
        }
        menu.addItem(item(String(localized: "Quit Elmers"), key: "q") { NSApp.terminate(nil) })
        return menu
    }
    private static func item(_ title: String, key: String = "", enabled: Bool = true, action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, keyEquivalent: key, action: action)
        item.isEnabled = enabled
        return item
    }
    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title); menu.autoenablesItems = false
        items.forEach(menu.addItem)
        item.submenu = menu
        return item
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, keyEquivalent: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }
    required init(coder: NSCoder) { fatalError("not used") }
    @objc private func run() { handler() }
}
