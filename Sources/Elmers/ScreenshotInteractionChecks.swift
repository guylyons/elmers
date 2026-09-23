#if DEBUG
import AppKit
import ElmersCore

/// End-to-end filesystem observation and app integration using only disposable generated images.
@MainActor
enum ScreenshotInteractionChecks {
    private final class Location: @unchecked Sendable {
        private let lock = NSLock()
        private var url: URL
        init(_ url: URL) { self.url = url }
        func get() -> URL { lock.lock(); defer { lock.unlock() }; return url }
        func set(_ url: URL) { lock.lock(); defer { lock.unlock() }; self.url = url }
    }
    private static func require(_ success: Bool, _ label: String) {
        guard success else { print("FAIL: \(label)"); fflush(stdout); exit(1) }
        print("PASS: \(label)"); fflush(stdout)
    }
    private static func until(_ label: String, _ predicate: () -> Bool) async {
        let deadline = Date().addingTimeInterval(8)
        while !predicate() && Date() < deadline { try? await Task.sleep(nanoseconds: 50_000_000) }
        require(predicate(), label)
    }
    private static func png() throws -> Data {
        let image = NSImage(size: NSSize(width: 480, height: 300), flipped: false) { rect in
            NSColor(calibratedRed: 0.1, green: 0.25, blue: 0.4, alpha: 1).setFill(); rect.fill()
            ("Elmers screenshot fixture" as NSString).draw(at: NSPoint(x: 30, y: 160), withAttributes: [.font: NSFont.systemFont(ofSize: 26), .foregroundColor: NSColor.white])
            ("Search, find, and paste." as NSString).draw(at: NSPoint(x: 30, y: 110), withAttributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.white])
            return true
        }
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { throw ScreenshotImage.ReadError.invalid }
        return png
    }
    private static func write(_ data: Data, _ url: URL) throws {
        try data.write(to: url)
        let marker = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        let result = marker.withUnsafeBytes { setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW) }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
    static func run(model: AppModel, controller: PanelController) {
        Task { @MainActor in
            do {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("elmers-screenshot-check-" + UUID().uuidString)
                let second = folder.appendingPathComponent("other")
                try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: folder) }
                let bytes = try png()
                try write(bytes, folder.appendingPathComponent("old.png"))
                let location = Location(folder)
                var updates: [ScreenshotMonitor.Update] = []
                var captures: [ScreenshotCapture] = []
                let monitor = ScreenshotMonitor(folderProvider: { location.get() }) { update in
                    updates.append(update); captures.append(contentsOf: update.captures)
                }
                monitor.configure(enabled: true, generation: 1, bookmark: nil)
                await until("screenshot observer established baseline") { updates.contains { $0.generation == 1 && $0.status == nil } }
                require(captures.isEmpty, "existing screenshot files were not imported")
                let source = folder.appendingPathComponent("fresh.png")
                let started = Date()
                try write(bytes, source)
                await until("real directory event imports new marked image") { captures.count == 1 }
                print("Screenshot file-to-capture latency: \(Int(Date().timeIntervalSince(started) * 1000)) ms")
                require(captures[0].payload.items[0]["public.png"] == bytes, "capture preserves original PNG bytes")
                require(try Data(contentsOf: source) == bytes, "observer leaves source file unchanged")
                let oldCapture = captures[0]
                monitor.configure(enabled: false, generation: 2, bookmark: nil)
                await until("screenshot observer pauses") { updates.contains { $0.generation == 2 } }
                try write(bytes, folder.appendingPathComponent("paused.png"))
                monitor.configure(enabled: true, generation: 3, bookmark: nil)
                await until("screenshot observer resumes with new baseline") { updates.contains { $0.generation == 3 } }
                try write(bytes, folder.appendingPathComponent("after-resume.png"))
                await until("resume imports only newly created screenshots") { captures.count == 2 }
                require(captures.last?.origin.originalURL.lastPathComponent == "after-resume.png", "paused screenshot is not backfilled")
                try write(bytes, second.appendingPathComponent("old-in-new-folder.png"))
                location.set(second)
                await until("screenshot destination changes are followed") { updates.last?.folder == second }
                try write(bytes, second.appendingPathComponent("new-in-new-folder.png"))
                await until("new destination imports new files only") { captures.count == 3 }
                require(captures.last?.origin.originalURL.lastPathComponent == "new-in-new-folder.png", "new destination baseline excludes older files")
                monitor.configure(enabled: false, generation: 4, bookmark: nil)
                await until("observer stopped after filesystem check") { updates.last?.generation == 4 }

                model.captureScreenshots = true; model.paused = false
                model.newText("Keep browsing this item")
                let selection = model.selectedID
                model.ingestScreenshot(oldCapture)
                require(model.selectedID == selection, "screenshot capture preserves current selection")
                guard let screenshot = model.history.items.first(where: { $0.kind == .screenshot }) else { require(false, "screenshot inserted into app history"); return }
                require(imagePreview(screenshot) != nil, "screenshot uses real image preview")
                model.filters = SearchFilters([.kind(.image)])
                require(model.visibleItems.contains { $0.id == screenshot.id }, "Images includes screenshot cards")
                model.clearSearch(); model.query = "SCREENSHOT"
                await until("Screenshot query becomes dedicated type filter") { model.filters.tokens == [.kind(.screenshot)] && model.query.isEmpty }
                require(model.removeLastFilter() && model.query == "SCREENSHOT", "Backspace restores screenshot query word")
                model.clearSearch()
                let count = model.history.items.count
                model.paused = true; model.ingestScreenshot(captures[1]); model.paused = false
                require(model.history.items.count == count, "app pause rejects screenshot ingestion")
                model.captureScreenshots = false; model.ingestScreenshot(captures[1]); model.captureScreenshots = true
                require(model.history.items.count == count, "capture preference rejects screenshot ingestion")
                model.excludedApps = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
                model.ingestScreenshot(captures[1])
                require(model.history.items.count == count, "excluded foreground app rejects screenshot ingestion")
                model.excludedApps = ""
                require(oldCapture.origin.resolveOriginal() != nil, "original-file action resolves source identity")
                try FileManager.default.removeItem(at: source)
                require(oldCapture.origin.resolveOriginal() == nil && imagePreview(screenshot) != nil, "missing original leaves saved image usable")
                controller.show()
                model.filters = SearchFilters([.kind(.screenshot)])
                try? await Task.sleep(nanoseconds: 300_000_000)
                KeyboardInteractionChecks.capturePanel(controller, name: "screenshot-panel")
                controller.openSettings()
                print("PASS: screenshot filesystem and app interaction checks")
                fflush(stdout)
                // Keep the fixture panel available for visual inspection only when explicitly requested.
                if !ProcessInfo.processInfo.arguments.contains("--keep-screenshot-fixture") { exit(0) }
                withExtendedLifetime(monitor) {}
            } catch { print("FAIL: screenshot checks: \(error.localizedDescription)"); fflush(stdout); exit(1) }
        }
    }
}
#endif
