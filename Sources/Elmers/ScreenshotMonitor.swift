import Foundation
import ElmersCore

/// Owns directory descriptors, security scope and scanner on one serial background queue.
final class ScreenshotMonitor {
    struct Update: Sendable {
        let generation: Int
        let folder: URL?
        let status: String?
        let needsAccess: Bool
        let captures: [ScreenshotCapture]
    }
    private let queue = DispatchQueue(label: "app.elmers.screenshots", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var events: DispatchSourceFileSystemObject?
    private var scanner: ScreenshotScanner?
    private var folder: URL?
    private var scopedURL: URL?
    private var folderIdentity: AnyHashable?
    private var generation = 0
    private var enabled = false
    private var bookmark: Data?
    private var dirty = true
    private var nextConfigurationCheck = Date.distantPast
    private var lastStatus: String?
    private var lastNeedsAccess = false
    private let receive: @MainActor (Update) -> Void
    private let folderProvider: () -> URL?

    init(folderProvider: @escaping () -> URL? = ScreenshotMonitor.configuredFolder, receive: @escaping @MainActor (Update) -> Void) {
        self.folderProvider = folderProvider; self.receive = receive
    }
    func configure(enabled: Bool, generation: Int, bookmark: Data?) {
        queue.async { [weak self] in
            guard let self else { return }
            self.enabled = enabled; self.generation = generation; self.bookmark = bookmark
            self.closeFolder(); self.folder = nil; self.nextConfigurationCheck = .distantPast
            if self.timer == nil {
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now(), repeating: .milliseconds(250), leeway: .milliseconds(50))
                timer.setEventHandler { [weak self] in self?.tick() }
                self.timer = timer; timer.resume()
            }
            self.tick()
        }
    }
    private func closeFolder() {
        events?.cancel(); events = nil; scanner = nil; folderIdentity = nil
        scopedURL?.stopAccessingSecurityScopedResource(); scopedURL = nil
        dirty = true
    }
    static func configuredFolder() -> URL? {
        // These keys are observed macOS preferences, not a public Screenshot API.
        let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.screencapture") ?? [:]
        if let target = (domain["target-screenshot"] ?? domain["target"]) as? String, target != "file" { return nil }
        let location = (domain["location-screenshot"] ?? domain["location"]) as? String
        let path = location.map { ($0 as NSString).expandingTildeInPath }
        guard path == nil || path!.hasPrefix("/") else { return nil }
        return path.map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }
    private func emit(_ status: String?, needsAccess: Bool = false, captures: [ScreenshotCapture] = [], force: Bool = false) {
        guard force || status != lastStatus || needsAccess != lastNeedsAccess || !captures.isEmpty else { return }
        lastStatus = status; lastNeedsAccess = needsAccess
        let update = Update(generation: generation, folder: folder, status: status, needsAccess: needsAccess, captures: captures)
        let receive = receive
        Task { @MainActor in receive(update) }
    }
    private func tick() {
        let now = Date()
        if now >= nextConfigurationCheck {
            nextConfigurationCheck = now.addingTimeInterval(2)
            let destination = folderProvider()
            let changed = destination != folder
            if changed { closeFolder(); folder = destination }
            guard enabled else {
                emit(nil, force: changed); return
            }
            guard let folder else {
                emit(String(localized: "macOS is not saving screenshots to a folder. Choose a folder in Screenshot’s Options to add saved screenshots here."), force: changed)
                return
            }
            let attributes = try? FileManager.default.attributesOfItem(atPath: folder.path)
            let identity = attributes?[.systemFileNumber] as? AnyHashable
            if scanner != nil && identity != folderIdentity { closeFolder() }
            if scanner == nil {
                if let bookmark {
                    var stale = false
                    if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale),
                       url.standardizedFileURL == folder, url.startAccessingSecurityScopedResource() { scopedURL = url }
                }
                do {
                    let descriptor = open(folder.path, O_EVTONLY)
                    guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                    let events = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .revoke], queue: queue)
                    events.setCancelHandler { close(descriptor) }
                    events.setEventHandler { [weak self, weak events] in
                        guard let self else { return }
                        self.dirty = true
                        if let events, !events.data.intersection([.rename, .delete, .revoke]).isEmpty {
                            self.closeFolder(); self.nextConfigurationCheck = .distantPast
                        }
                    }
                    self.events = events; events.resume()
                    scanner = try ScreenshotScanner(folder: folder)
                    folderIdentity = identity
                    dirty = true
                    emit(nil, force: true)
                } catch {
                    closeFolder()
                    let exists = FileManager.default.fileExists(atPath: folder.path)
                    let nsError = error as NSError
                    let denied = nsError.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(nsError.code)
                    let needsAccess = exists || denied || (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError)
                    emit(needsAccess ? String(localized: "Elmers cannot read the screenshot folder. Allow folder access to start capturing new screenshots.") : String(localized: "The screenshot folder is unavailable. Capture will resume when it is available."), needsAccess: needsAccess, force: changed)
                    return
                }
            }
            dirty = true // Reconcile missed/coalesced directory events without importing the baseline.
        }
        guard enabled, let scanner, dirty || scanner.hasPending else { return }
        dirty = false
        do { let captures = try scanner.scan(at: now); emit(scanner.lastIssue, captures: captures) }
        catch {
            closeFolder()
            emit(String(localized: "The screenshot folder cannot be read. Allow access or restore the folder to resume."), needsAccess: true)
        }
    }
    deinit {
        timer?.cancel(); events?.cancel(); scopedURL?.stopAccessingSecurityScopedResource()
    }
}
