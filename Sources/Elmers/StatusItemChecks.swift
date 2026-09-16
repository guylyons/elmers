#if DEBUG
import AppKit

@MainActor
enum StatusItemChecks {
    static func run(delegate: AppDelegate) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            click(delegate: delegate, right: true) {
                guard let settings = NSApp.windows.first(where: { $0.title == "Elmers Settings" }), settings.isVisible else {
                    print("FAIL: right-click on status item did not open Settings"); fflush(stdout); exit(1)
                }
                guard !delegate.panelController.panel.isVisible else {
                    print("FAIL: right-click opened history"); fflush(stdout); exit(1)
                }
                settings.close()
                click(delegate: delegate, right: false) {
                    guard delegate.panelController.panel.isVisible else {
                        print("FAIL: left-click did not open history"); fflush(stdout); exit(1)
                    }
                    click(delegate: delegate, right: true) {
                        guard settings.isVisible, !delegate.panelController.panel.isVisible else {
                            print("FAIL: right-click did not replace history with Settings"); fflush(stdout); exit(1)
                        }
                        print("PASS: status-item right-click opens/reopens Settings; left-click opens history"); fflush(stdout); exit(0)
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
