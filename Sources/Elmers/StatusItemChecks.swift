#if DEBUG
import AppKit

@MainActor
enum StatusItemChecks {
    static let expectedMenu = ["About Elmers", "", "New Text Item", "Settings…", "", "Help", "", "Pause Elmers", "Quit Elmers"]
    static func run(delegate: AppDelegate) {
        var presented: NSMenu?
        delegate.presentStatusMenu = { presented = $0 }
        func fail(_ message: String) -> Never { print("FAIL: \(message)"); fflush(stdout); exit(1) }
        /// Chooses `title` from the menu the last right-click presented, as a user would.
        func choose(_ title: String) {
            guard let menu = presented else { fail("right-click did not present a menu") }
            let titles = menu.items.map { $0.isSeparatorItem ? "" : $0.title }
            guard titles == expectedMenu else { fail("status menu was \(titles)") }
            guard let pause = menu.items.first(where: { $0.title == "Pause Elmers" })?.submenu?.items.map({ $0.isSeparatorItem ? "" : $0.title }),
                  pause == ["Pause", "", "Pause for 15m", "Pause for 30m", "Pause for 1h", "Pause for 3h", "Pause for 8h"] else { fail("pause submenu differs from Paste's") }
            guard let item = menu.items.first(where: { $0.title == title }), let index = menu.items.firstIndex(of: item) else { fail("no \(title) item") }
            menu.performActionForItem(at: index)
            presented = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            click(delegate: delegate, right: true) {
                guard !delegate.panelController.isShown else { fail("right-click opened history") }
                choose("Settings…")
                guard let settings = NSApp.windows.first(where: { $0.title == "Elmers Settings" }), settings.isVisible else {
                    fail("Settings… in the right-click menu did not open Settings")
                }
                settings.close()
                click(delegate: delegate, right: false) {
                    guard delegate.panelController.isShown else { fail("left-click did not open history") }
                    click(delegate: delegate, right: true) {
                        choose("Settings…")
                        guard settings.isVisible, !delegate.panelController.isShown else { fail("Settings from the menu did not replace history") }
                        print("PASS: status-item right-click shows Paste's menu (Settings… opens Settings); left-click opens history"); fflush(stdout); exit(0)
                    }
                }
            }
        }
    }

    private static func click(delegate: AppDelegate, right: Bool, completion: @escaping @MainActor () -> Void) {
        let button = delegate.statusItem.button!
        let location = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        for type: NSEvent.EventType in right ? [.rightMouseDown, .rightMouseUp] : [.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: button.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
            NSApp.postEvent(event, atStart: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { completion() }
    }
}
#endif
