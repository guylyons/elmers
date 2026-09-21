import Darwin
import Foundation

extension ScreenshotOrigin {
    /// A replacement at the same path is not the original; bookmarks may follow a moved file.
    public func resolveOriginal() -> URL? {
        var candidates = [URL]()
        if let bookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) { candidates.append(resolved) }
        }
        candidates.append(originalURL)
        return candidates.first { (try? ScreenshotFile.inspect($0).identity) == fileIdentity }
    }
}

public struct ScreenshotCapture: Sendable {
    public let payload: ClipboardPayload
    public let origin: ScreenshotOrigin
    public let imageDigest: String
    public let date: Date
}

/// Identity includes birth time to avoid inode reuse; no content or filenames are logged.
public struct ScreenshotFile: Equatable {
    public let identity: String
    public let size: Int64
    public let modified: Date
    public let created: Date
    public static func inspect(_ url: URL) throws -> Self {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard info.st_mode & S_IFMT == S_IFREG else { throw ScreenshotImage.ReadError.invalid }
        return snapshot(info)
    }
    private static func snapshot(_ info: stat) -> Self {
        Self(identity: "\(info.st_dev):\(info.st_ino):\(info.st_birthtimespec.tv_sec):\(info.st_birthtimespec.tv_nsec)", size: info.st_size,
             modified: Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9),
             created: Date(timeIntervalSince1970: Double(info.st_birthtimespec.tv_sec) + Double(info.st_birthtimespec.tv_nsec) / 1e9))
    }
    public static func isScreenshot(_ url: URL) -> Bool {
        var bytes = [UInt8](repeating: 0, count: 1024)
        let size = getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", &bytes, bytes.count, 0, XATTR_NOFOLLOW)
        guard size > 0, size <= bytes.count,
              let value = try? PropertyListSerialization.propertyList(from: Data(bytes.prefix(size)), format: nil) as? Bool else { return false }
        return value
    }
    /// Open without following symlinks and check the descriptor before and after reading.
    public func read(_ url: URL) throws -> Data {
        guard size > 0, size <= ScreenshotImage.maximumBytes else { throw ScreenshotImage.ReadError.tooLarge }
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, Self.snapshot(info) == self else { throw ScreenshotImage.ReadError.invalid }
        let data = try handle.read(upToCount: Int(size) + 1) ?? Data()
        guard data.count == size, fstat(descriptor, &info) == 0, Self.snapshot(info) == self,
              try Self.inspect(url) == self else { throw ScreenshotImage.ReadError.invalid }
        return data
    }
}

/// Single-queue state machine. Startup baselines never read image bytes.
public final class ScreenshotScanner {
    public let folder: URL
    public var lastIssue: String? { issues.values.sorted().first }
    public var hasPending: Bool { !pending.isEmpty }
    private let started: Date
    private var consumed: Set<String> = []
    private var rejected: [String: (file: ScreenshotFile, marked: Bool)] = [:]
    private var issues: [String: String] = [:]
    private struct Pending { var file: ScreenshotFile; var stableSince: Date; var attempts = 0 }
    private var pending: [String: Pending] = [:]
    public init(folder: URL) throws {
        self.folder = folder; started = Date()
        for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            if let file = try? ScreenshotFile.inspect(url) { consumed.insert(file.identity) }
        }
    }
    public func scan(at now: Date = Date()) throws -> [ScreenshotCapture] {
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        var present = Set<String>()
        var captures: [ScreenshotCapture] = []
        for url in urls {
            guard let file = try? ScreenshotFile.inspect(url) else { continue }
            present.insert(file.identity)
            guard !consumed.contains(file.identity) else { continue }
            // A pre-existing screenshot moved into the folder is not a new capture.
            guard file.created >= started else { consumed.insert(file.identity); continue }
            if let previous = rejected[file.identity] {
                guard previous.file != file || previous.marked != ScreenshotFile.isScreenshot(url) else { continue }
                rejected.removeValue(forKey: file.identity); issues.removeValue(forKey: file.identity)
            }
            var candidate = pending[file.identity] ?? Pending(file: file, stableSince: now)
            if candidate.file != file { candidate = Pending(file: file, stableSince: now) }
            pending[file.identity] = candidate
            guard now.timeIntervalSince(candidate.stableSince) >= 0.35 else { continue }
            candidate.attempts += 1; pending[file.identity] = candidate
            guard ScreenshotFile.isScreenshot(url) else {
                if candidate.attempts >= 120 { pending.removeValue(forKey: file.identity); rejected[file.identity] = (file, false) }
                continue
            }
            do {
                let data = try file.read(url)
                let image = try ScreenshotImage.decode(data)
                guard try ScreenshotFile.inspect(url) == file else { continue }
                let bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                captures.append(ScreenshotCapture(payload: image.payload,
                    origin: ScreenshotOrigin(originalURL: url, fileIdentity: file.identity, bookmark: bookmark), imageDigest: image.digest, date: file.created))
                consumed.insert(file.identity); pending.removeValue(forKey: file.identity)
                issues.removeValue(forKey: file.identity)
            } catch {
                if candidate.attempts >= 120 || file.size > ScreenshotImage.maximumBytes {
                    issues[file.identity] = error.localizedDescription
                    pending.removeValue(forKey: file.identity); rejected[file.identity] = (file, true)
                }
            }
        }
        pending = pending.filter { present.contains($0.key) }
        rejected = rejected.filter { present.contains($0.key) }
        issues = issues.filter { present.contains($0.key) }
        return captures.sorted { $0.date < $1.date }
    }
}
