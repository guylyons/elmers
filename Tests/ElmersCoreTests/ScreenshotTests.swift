import AppKit
import ElmersCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class ScreenshotTests {
    static func image(_ type: CFString = UTType.png.identifier as CFString, red: CGFloat = 1) throws -> Data {
        let context = CGContext(data: nil, width: 16, height: 12, bitsPerComponent: 8, bytesPerRow: 64,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: red, green: 0.2, blue: 0.3, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 16, height: 12))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "Fixture", code: 1) }
        return data as Data
    }

    func testImageFilterIncludesScreenshots() throws {
        var history = History()
        let image = history.capture(.init(items: [["public.png": try Self.image()]]), source: "Fixture")
        var marked = image
        marked.screenshot = ScreenshotOrigin(originalURL: URL(fileURLWithPath: "/tmp/fixture.png"), fileIdentity: "fixture")
        history.replaceItem(marked)
        XCTAssertEqual(history.filtered(kind: .image).map(\.id), [image.id])
        XCTAssertEqual(history.filtered(kind: .screenshot).map(\.id), [image.id])
    }

    func testScreenshotDuplicatesInEitherOrderPreservePins() throws {
        let png = ClipboardPayload(items: [["public.png": try Self.image()]])
        let tiff = ClipboardPayload(items: [["public.tiff": try Self.image(UTType.tiff.identifier as CFString)]])
        let digest = try ScreenshotImage.decode(png.items[0]["public.png"]!).digest
        try XCTAssertEqual(try ScreenshotImage.decode(tiff.items[0]["public.tiff"]!).digest, digest)
        let origin = ScreenshotOrigin(originalURL: URL(fileURLWithPath: "/tmp/fixture.png"), fileIdentity: "fixture")
        for screenshotFirst in [false, true] {
            var history = History()
            let first = history.capture(screenshotFirst ? png : tiff, source: "Fixture", at: Date(timeIntervalSince1970: 100), screenshot: screenshotFirst ? origin : nil, imageDigest: digest)
            let board = history.createBoard(name: "Keep"); history.pin(first.id, to: board.id)
            history.renameItem(first.id, title: "My screenshot")
            let second = history.capture(screenshotFirst ? tiff : png, source: "Fixture", at: Date(timeIntervalSince1970: 101), screenshot: screenshotFirst ? nil : origin, imageDigest: digest)
            XCTAssertEqual(history.items.count, 1); XCTAssertEqual(second.id, first.id)
            XCTAssertEqual(second.kind, .screenshot); XCTAssertEqual(second.boardIDs, [board.id])
            XCTAssertEqual(second.title, "My screenshot")
            XCTAssertNotNil(second.payload.items[0]["public.png"])
            XCTAssertNotNil(second.payload.items[0]["public.tiff"])
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: url) }
            let archive = Archive(url: url); try archive.save(history)
            try XCTAssertEqual(archive.load().items.first?.screenshot, origin)
            _ = history.capture(tiff, source: "Later", at: Date(timeIntervalSince1970: 200), imageDigest: digest)
            XCTAssertEqual(history.items.count, 2)
        }
    }

    static func mark(_ url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        let result = data.withUnsafeBytes { bytes in
            setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", bytes.baseAddress, bytes.count, 0, XATTR_NOFOLLOW)
        }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    func testScannerIgnoresOldFilesAndWaitsForStableMarkedBytes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = folder.appendingPathComponent("old.png"), fresh = folder.appendingPathComponent("new.png")
        let bytes = try Self.image()
        try bytes.write(to: old); try Self.mark(old)
        let scanner = try ScreenshotScanner(folder: folder)
        let now = Date()
        try XCTAssertEqual(scanner.scan(at: now).count, 0)
        try Data(bytes.prefix(20)).write(to: fresh)
        try XCTAssertEqual(scanner.scan(at: now).count, 0)
        try XCTAssertEqual(scanner.scan(at: now.addingTimeInterval(1)).count, 0)
        try bytes.write(to: fresh)
        try XCTAssertEqual(scanner.scan(at: now.addingTimeInterval(2)).count, 0)
        try XCTAssertEqual(scanner.scan(at: now.addingTimeInterval(3)).count, 0)
        try Self.mark(fresh)
        let captures = try scanner.scan(at: now.addingTimeInterval(4))
        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(captures.first?.payload.items.first?["public.png"], bytes)
        try XCTAssertEqual(Data(contentsOf: fresh), bytes)
        try XCTAssertEqual(scanner.scan(at: now.addingTimeInterval(5)).count, 0)
        let renamed = folder.appendingPathComponent("renamed.png")
        try FileManager.default.moveItem(at: fresh, to: renamed)
        try XCTAssertEqual(scanner.scan(at: now.addingTimeInterval(6)).count, 0)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.png"), withDestinationURL: renamed)
        try XCTAssertEqual(scanner.scan(at: now.addingTimeInterval(7)).count, 0)
        let restarted = try ScreenshotScanner(folder: folder)
        try XCTAssertEqual(restarted.scan(at: now.addingTimeInterval(8)).count, 0)
    }

    func testRejectedFilesCanFinishLaterAndOriginalIdentityIsChecked() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let scanner = try ScreenshotScanner(folder: folder)
        let file = folder.appendingPathComponent("late.png")
        try Data([1, 2, 3]).write(to: file); try Self.mark(file)
        let start = Date()
        for tick in 0...125 { _ = try scanner.scan(at: start.addingTimeInterval(Double(tick))) }
        XCTAssertNotNil(scanner.lastIssue)
        let bytes = try Self.image()
        try bytes.write(to: file)
        _ = try scanner.scan(at: start.addingTimeInterval(130))
        let captures = try scanner.scan(at: start.addingTimeInterval(131))
        XCTAssertEqual(captures.count, 1)
        guard let captured = captures.first else { return }
        // The bookmark may resolve through /var's /private/var symlink; both name the same file.
        XCTAssertEqual(captured.origin.resolveOriginal()?.resolvingSymlinksInPath(), file.resolvingSymlinksInPath())
        try FileManager.default.removeItem(at: file)
        try Self.image(red: 0.5).write(to: file)
        XCTAssertNil(captured.origin.resolveOriginal())
        // Saved bytes remain independent of the original's lifetime.
        XCTAssertEqual(captured.payload.items[0]["public.png"], bytes)
    }

    func testOversizedUnmarkedAndNonImageFilesDoNotCapture() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let scanner = try ScreenshotScanner(folder: folder)
        try Self.image().write(to: folder.appendingPathComponent("ordinary.png"))
        let large = folder.appendingPathComponent("large.png")
        FileManager.default.createFile(atPath: large.path, contents: nil)
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(32 * 1024 * 1024 + 1)); try handle.close()
        try Self.mark(large)
        let now = Date()
        try XCTAssertEqual(scanner.scan(at: now).count, 0)
        try XCTAssertEqual(scanner.scan(at: now.addingTimeInterval(1)).count, 0)
        XCTAssertNotNil(scanner.lastIssue)
        XCTAssertThrowsError(try ScreenshotImage.decode(Data("not an image".utf8)))
    }
    func testScreenshotClassificationAndLegacyDecode() throws {
        let original = ClipboardItem(payload: .init(items: [["public.png": Data([1, 2, 3])]]), source: "Screenshot")
        let encoded = try JSONEncoder().encode(original)
        try XCTAssertEqual(try JSONDecoder().decode(ClipboardItem.self, from: encoded).kind, .image)
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        object["screenshot"] = ["originalURL": "file:///tmp/elmers-screenshot.png", "fileIdentity": "fixture"]
        let marked = try JSONDecoder().decode(ClipboardItem.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(marked.kind.rawValue, "Screenshot")
        try XCTAssertEqual(try JSONDecoder().decode(ClipboardItem.self, from: JSONEncoder().encode(marked)).kind.rawValue, "Screenshot")
        XCTAssertEqual(SearchQuery("SCREENSHOTS error").kind?.rawValue, "Screenshot")
        var edited = marked
        edited.payload = .text("changed")
        XCTAssertEqual(edited.kind, .text)
    }
}
