# Screenshot Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Screenshots taken with the macOS tools appear in Elmers' history as their own `Screenshot` category, while still being written to the user's normal screenshots folder.

**Architecture:** A live `NSMetadataQuery` on `kMDItemIsScreenCapture` detects new screenshot files. Each candidate is confirmed by the EXIF `UserComment` that `screencapture` embeds, then stored as a file reference plus a bounded thumbnail. A new optional `ScreenshotInfo` field on `ClipboardItem` carries the category across reloads, because `ContentKind` is derived from the payload and never persisted.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Foundation (`NSMetadataQuery`), ImageIO (`CGImageSource`), Vision (existing OCR). No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-09-17-screenshot-capture-design.md`

## Global Constraints

- No third-party dependencies. Original code only.
- The archive stays at `version: 1`. Do not add migration code and do not change the version constant in `Sources/ElmersCore/Archive.swift`.
- Never log, commit, or print raw clipboard or screenshot content.
- Elmers observes screenshots only. Never move, delete, rewrite, or intercept the user's screenshot files, and never alter `com.apple.screencapture` preferences.
- The per-capture size cap is 32 MB (`Sources/ElmersCore/PasteboardCodec.swift:24`). Stored thumbnails target roughly 30 KB.
- Tests are a hand-rolled runner, not XCTest. `scripts/test.sh` builds and runs `ElmersCoreChecks`. The suite is currently **19 checks**; every task that adds a check updates that count in its commit message only if it states one.
- Demo mode (`--demo`) must never start the watcher, so the check executables stay hermetic.
- Control-held clipboard-only screenshots stay `Image`. Do not add heuristics to guess them.

---

### Task 1: Screenshot marker on the data model

**Files:**
- Modify: `Sources/ElmersCore/ClipboardItem.swift:5-8` (enum), `:54-99` (struct)
- Create: `Tests/ElmersCoreTests/ScreenshotTests.swift`
- Modify: `Tests/ElmersCoreTests/main.swift:24-45`

**Interfaces:**
- Consumes: nothing.
- Produces: `ContentKind.screenshot` (raw value `"Screenshot"`); `ScreenshotInfo(path:captureType:pixelWidth:pixelHeight:)`; `ClipboardItem.screenshot: ScreenshotInfo?`; `ClipboardItem.init(payload:source:sourceBundleID:at:screenshot:)`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ElmersCoreTests/ScreenshotTests.swift`:

```swift
import Foundation
import ElmersCore

final class ScreenshotTests {
    private func info(_ path: String = "/tmp/Screenshot 2026-09-17.png") -> ScreenshotInfo {
        ScreenshotInfo(path: path, captureType: "selection", pixelWidth: 1512, pixelHeight: 982)
    }
    private func payload(_ path: String = "/tmp/Screenshot 2026-09-17.png") -> ClipboardPayload {
        let url = URL(fileURLWithPath: path).absoluteString
        return ClipboardPayload(items: [["public.file-url": Data(url.utf8), "public.png": Data([0, 1, 255])]])
    }

    /// The marker, not the payload, decides the kind: the payload alone would read as a file.
    func testMarkerMakesTheItemAScreenshot() {
        let plain = ClipboardItem(payload: payload(), source: "Finder")
        XCTAssertEqual(plain.kind, .file)
        let shot = ClipboardItem(payload: payload(), source: "Screenshot", screenshot: info())
        XCTAssertEqual(shot.kind, .screenshot)
        XCTAssertEqual(shot.screenshot?.captureType, "selection")
        XCTAssertEqual(shot.screenshot?.pixelWidth, 1512)
    }

    /// Assigning or clearing the marker after the fact must refresh the cached kind.
    func testClearingTheMarkerRestoresTheDerivedKind() {
        var shot = ClipboardItem(payload: payload(), source: "Screenshot", screenshot: info())
        XCTAssertEqual(shot.kind, .screenshot)
        shot.screenshot = nil
        XCTAssertEqual(shot.kind, .file)
    }

    /// The archive stays at version 1, so the marker must survive a round trip.
    func testArchiveRoundTripPreservesTheMarker() throws {
        var history = History()
        _ = history.capture(payload(), source: "Screenshot", screenshot: info())
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("elmers-shot-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = Archive(url: url)
        try archive.save(history)
        let loaded = try archive.load()
        XCTAssertEqual(loaded.items.count, 1)
        XCTAssertEqual(loaded.items[0].kind, .screenshot)
        XCTAssertEqual(loaded.items[0].screenshot?.path, info().path)
        XCTAssertEqual(loaded.items[0].screenshot?.pixelHeight, 982)
    }

    /// An archive written before this feature has no marker and must still load.
    func testArchiveWithoutTheMarkerStillLoads() throws {
        var history = History()
        _ = history.capture(.text("older archive"), source: "Notes")
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("elmers-old-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = Archive(url: url)
        try archive.save(history)
        let loaded = try archive.load()
        XCTAssertNil(loaded.items[0].screenshot)
        XCTAssertEqual(loaded.items[0].kind, .text)
    }

    /// Detecting the same file twice promotes the existing item rather than duplicating it.
    func testSameFileCapturedTwicePromotesInsteadOfDuplicating() {
        var history = History()
        let first = history.capture(payload(), source: "Screenshot", screenshot: info())
        _ = history.capture(.text("something else"), source: "Notes")
        let second = history.capture(payload(), source: "Screenshot", screenshot: info())
        XCTAssertEqual(history.items.count, 2)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(history.items[0].id, first.id)
    }
}
```

Register it in `Tests/ElmersCoreTests/main.swift`. Add the instance next to the existing ones (after `let pasteboard = PasteboardTests()`):

```swift
let screenshot = ScreenshotTests()
```

and append these entries to the end of the `checks` array:

```swift
    ("screenshot marker sets the kind", screenshot.testMarkerMakesTheItemAScreenshot),
    ("clearing the screenshot marker", screenshot.testClearingTheMarkerRestoresTheDerivedKind),
    ("screenshot archive round trip", screenshot.testArchiveRoundTripPreservesTheMarker),
    ("archive without a screenshot marker", screenshot.testArchiveWithoutTheMarkerStillLoads),
    ("same screenshot file promotes", screenshot.testSameFileCapturedTwicePromotesInsteadOfDuplicating)
```

Note the existing array's last element has no trailing comma — add one to it when appending.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./scripts/test.sh`
Expected: compile failure — `cannot find 'ScreenshotInfo' in scope`, and `.screenshot` is not a member of `ContentKind`.

- [ ] **Step 3: Add the enum case and the marker**

In `Sources/ElmersCore/ClipboardItem.swift`, extend the enum (keep `.screenshot` directly after `.image` so the filter menu lists it there):

```swift
public enum ContentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case text = "Text", link = "Link", image = "Image", screenshot = "Screenshot", file = "File", other = "Content"
    public var id: String { rawValue }
}
```

Add the info struct above `ClipboardItem`:

```swift
/// Records that an item came from a macOS screenshot file.
/// `ContentKind` is derived from the payload, so this stored marker is what
/// keeps a screenshot a screenshot across a reload.
public struct ScreenshotInfo: Codable, Equatable, Sendable {
    /// Absolute path of the screenshot on disk. May no longer exist.
    public var path: String
    /// "selection", "window" or "display" when Spotlight reported it.
    public var captureType: String?
    public var pixelWidth: Int
    public var pixelHeight: Int
    public init(path: String, captureType: String?, pixelWidth: Int, pixelHeight: Int) {
        self.path = path; self.captureType = captureType
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
    }
}
```

In `ClipboardItem`, add the stored property immediately after `recognizedText`:

```swift
    /// Set only for items imported from a macOS screenshot file.
    public var screenshot: ScreenshotInfo? { didSet { refreshMetadata() } }
```

Change the designated initialiser to accept it (assignment inside `init` does not fire `didSet`, so the existing `refreshMetadata()` call at the end still does the work):

```swift
    public init(payload: ClipboardPayload, source: String, sourceBundleID: String? = nil, at: Date = Date(), screenshot: ScreenshotInfo? = nil) {
        id = UUID(); self.payload = payload; self.source = source; self.sourceBundleID = sourceBundleID
        copiedAt = at; boardIDs = []; fingerprint = payload.fingerprint
        self.screenshot = screenshot
        refreshMetadata()
    }
```

Make the derivation consult the marker:

```swift
    private mutating func refreshMetadata() {
        cachedText = payload.text
        cachedKind = screenshot != nil ? .screenshot : payload.kind(for: cachedText)
        cachedByteCount = payload.byteCount
    }
```

Add the key and decode it. `decodeIfPresent` is what keeps older archives loading:

```swift
    private enum CodingKeys: String, CodingKey { case id, payload, source, sourceBundleID, copiedAt, boardIDs, title, fingerprint, linkPreview, recognizedText, screenshot }
```

and in `init(from:)`, immediately before the closing `refreshMetadata()`:

```swift
        screenshot = try values.decodeIfPresent(ScreenshotInfo.self, forKey: .screenshot)
```

- [ ] **Step 4: Thread the marker through capture**

In `Sources/ElmersCore/History.swift:8-17`, extend `capture` so an item is born with its marker rather than being patched afterwards:

```swift
    @discardableResult public mutating func capture(_ payload: ClipboardPayload, source: String, sourceBundleID: String? = nil, at date: Date = Date(), screenshot: ScreenshotInfo? = nil) -> ClipboardItem {
        let fingerprint = payload.fingerprint
        var item: ClipboardItem
        if let index = items.firstIndex(where: { $0.fingerprint == fingerprint }) {
            item = items.remove(at: index)
            item.copiedAt = date; item.source = source; item.sourceBundleID = sourceBundleID
            if let screenshot { item.screenshot = screenshot }
        } else { item = ClipboardItem(payload: payload, source: source, sourceBundleID: sourceBundleID, at: date, screenshot: screenshot) }
        items.insert(item, at: 0)
        return item
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `./scripts/test.sh`
Expected: `24 checks, 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Sources/ElmersCore/ClipboardItem.swift Sources/ElmersCore/History.swift Tests/ElmersCoreTests/ScreenshotTests.swift Tests/ElmersCoreTests/main.swift
git commit -m "Add a stored screenshot marker and the Screenshot kind"
```

---

### Task 2: Search keywords and type-filter vocabulary

**Files:**
- Modify: `Sources/ElmersCore/SearchQuery.swift:33-40`
- Modify: `Sources/Elmers/CardView.swift:206-210`
- Modify: `Tests/ElmersCoreTests/ScreenshotTests.swift`
- Modify: `Tests/ElmersCoreTests/main.swift`

**Interfaces:**
- Consumes: `ContentKind.screenshot` from Task 1.
- Produces: `ContentKind.screenshot.keywords`; `ContentKind.screenshot.symbolName == "camera.viewfinder"`; `searchNoun == "screenshots"`.

- [ ] **Step 1: Write the failing test**

Append to `ScreenshotTests`:

```swift
    /// "screenshot" used to select Image. It must now select Screenshot, and
    /// Image must keep its own words.
    func testScreenshotKeywordSelectsTheScreenshotKind() {
        XCTAssertEqual(ContentKind.matching(keyword: "screenshot"), .screenshot)
        XCTAssertEqual(ContentKind.matching(keyword: "Screenshots"), .screenshot)
        XCTAssertEqual(ContentKind.matching(keyword: "screengrab"), .screenshot)
        XCTAssertEqual(ContentKind.matching(keyword: "image"), .image)
        XCTAssertEqual(ContentKind.matching(keyword: "photos"), .image)
    }

    /// Typing the word filters history down to screenshots and clears the field.
    func testTypingScreenshotFiltersToScreenshotsOnly() {
        var history = History()
        let shot = history.capture(payload(), source: "Screenshot", screenshot: info())
        _ = history.capture(ClipboardPayload(items: [["public.png": Data([9, 9, 9])]]), source: "Preview")
        _ = history.capture(.text("a screenshot of the bug"), source: "Notes")
        let parsed = SearchQuery("screenshot")
        XCTAssertEqual(parsed.kind, .screenshot)
        XCTAssertEqual(parsed.remainder, "")
        XCTAssertEqual(history.filtered(query: parsed.remainder, kind: parsed.kind).map(\.id), [shot.id])
    }
```

Register both in `main.swift`'s `checks` array:

```swift
    ("screenshot search keywords", screenshot.testScreenshotKeywordSelectsTheScreenshotKind),
    ("typing screenshot filters to screenshots", screenshot.testTypingScreenshotFiltersToScreenshotsOnly)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./scripts/test.sh`
Expected: FAIL — `matching(keyword: "screenshot")` still returns `.image`.

- [ ] **Step 3: Move the keywords**

In `Sources/ElmersCore/SearchQuery.swift`, replace the `keywords` switch:

```swift
    var keywords: [String] {
        switch self {
        case .text: return ["text", "texts"]
        case .link: return ["link", "links", "url", "urls"]
        case .image: return ["image", "images", "photo", "photos", "picture", "pictures"]
        case .screenshot: return ["screenshot", "screenshots", "screengrab", "screengrabs", "grab", "grabs"]
        case .file: return ["file", "files"]
        case .other: return ["content"]
        }
    }
```

`ContentKind.matching` scans `allCases` in declaration order, and `.screenshot` now owns these words exclusively, so no ordering ambiguity remains.

- [ ] **Step 4: Give the kind an icon and a noun**

In `Sources/Elmers/CardView.swift`, extend both switches:

```swift
extension ContentKind {
    var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .screenshot: return "camera.viewfinder"
        case .file: return "doc"
        case .other: return "doc.on.clipboard"
        }
    }
    var searchNoun: String {
        switch self { case .text: return "text"; case .other: return "content"; default: return rawValue.lowercased() + "s" }
    }
}
```

`searchNoun` needs no new case: `.screenshot` falls into `default` and yields `"screenshots"`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `./scripts/test.sh`
Expected: `26 checks, 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Sources/ElmersCore/SearchQuery.swift Sources/Elmers/CardView.swift Tests/ElmersCoreTests/ScreenshotTests.swift Tests/ElmersCoreTests/main.swift
git commit -m "Give Screenshot its own search vocabulary and icon"
```

---

### Task 3: Reading a screenshot file into a payload

**Files:**
- Create: `Sources/ElmersCore/ScreenshotFile.swift`
- Modify: `Tests/ElmersCoreTests/ScreenshotTests.swift`
- Modify: `Tests/ElmersCoreTests/main.swift`

**Interfaces:**
- Consumes: `ScreenshotInfo`, `ClipboardPayload` from Task 1.
- Produces:
  - `ScreenshotFile.isScreenshot(at path: String) -> Bool`
  - `ScreenshotFile.read(path: String, captureType: String?) -> ScreenshotFile.Capture?`
  - `struct ScreenshotFile.Capture { let payload: ClipboardPayload; let info: ScreenshotInfo }`
  - `ScreenshotFile.fullResolutionPayload(for info: ScreenshotInfo, fallback: ClipboardPayload) -> ClipboardPayload`
  - `ScreenshotFile.thumbnailMaxPixelSize: Int` (512)

- [ ] **Step 1: Write the failing tests**

Append to `ScreenshotTests`. These build a real PNG on disk, so they need no Spotlight and no screenshots of the user's screen:

```swift
    /// Writes a PNG to a temp path. `screenshot: true` embeds the EXIF
    /// UserComment that `screencapture` puts in every screenshot it writes.
    private func writePNG(width: Int, height: Int, screenshot: Bool) throws -> String {
        let path = NSTemporaryDirectory() + "elmers-test-\(UUID().uuidString).png"
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemTeal.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        let data = rep.representation(using: .png, properties: [:])!
        guard screenshot else { try data.write(to: URL(fileURLWithPath: path)); return path }
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
        let exif = [kCGImagePropertyExifUserComment as String: "Screenshot"]
        CGImageDestinationAddImageFromSource(destination, source, 0, [kCGImagePropertyExifDictionary as String: exif] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return path
    }

    func testEXIFCommentIdentifiesAScreenshot() throws {
        let shot = try writePNG(width: 40, height: 30, screenshot: true)
        let plain = try writePNG(width: 40, height: 30, screenshot: false)
        defer { try? FileManager.default.removeItem(atPath: shot); try? FileManager.default.removeItem(atPath: plain) }
        XCTAssertTrue(ScreenshotFile.isScreenshot(at: shot))
        XCTAssertTrue(!ScreenshotFile.isScreenshot(at: plain))
        XCTAssertTrue(!ScreenshotFile.isScreenshot(at: "/tmp/does-not-exist-\(UUID().uuidString).png"))
    }

    /// The stored payload references the file and carries a small thumbnail,
    /// never the full-resolution bytes.
    func testReadProducesAFileReferenceAndABoundedThumbnail() throws {
        let path = try writePNG(width: 3000, height: 2000, screenshot: true)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let capture = ScreenshotFile.read(path: path, captureType: "selection")
        XCTAssertNotNil(capture)
        guard let capture else { return }
        XCTAssertEqual(capture.info.pixelWidth, 3000)
        XCTAssertEqual(capture.info.pixelHeight, 2000)
        XCTAssertEqual(capture.info.captureType, "selection")
        XCTAssertEqual(capture.info.path, path)
        let types = Set(capture.payload.items.flatMap { $0.keys })
        XCTAssertTrue(types.contains("public.file-url"))
        XCTAssertTrue(types.contains("public.png"))
        XCTAssertTrue(capture.payload.byteCount < 400_000)
        let thumbnail = capture.payload.items[0]["public.png"].flatMap { NSImage(data: $0) }
        XCTAssertNotNil(thumbnail)
        XCTAssertTrue((thumbnail?.size.width ?? 0) <= CGFloat(ScreenshotFile.thumbnailMaxPixelSize))
    }

    func testReadRejectsAMissingFile() {
        XCTAssertNil(ScreenshotFile.read(path: "/tmp/missing-\(UUID().uuidString).png", captureType: nil))
    }

    /// Paste reads the full file when it is still there, and falls back to the
    /// stored thumbnail when it is gone.
    func testFullResolutionPayloadFallsBackToTheThumbnail() throws {
        let path = try writePNG(width: 1200, height: 800, screenshot: true)
        let capture = ScreenshotFile.read(path: path, captureType: nil)!
        let hydrated = ScreenshotFile.fullResolutionPayload(for: capture.info, fallback: capture.payload)
        XCTAssertTrue(hydrated.byteCount > capture.payload.byteCount)
        try FileManager.default.removeItem(atPath: path)
        let stale = ScreenshotFile.fullResolutionPayload(for: capture.info, fallback: capture.payload)
        XCTAssertEqual(stale.byteCount, capture.payload.byteCount)
        XCTAssertTrue(!Set(stale.items.flatMap { $0.keys }).contains("public.file-url"))
    }
```

Register them:

```swift
    ("screenshot EXIF identification", screenshot.testEXIFCommentIdentifiesAScreenshot),
    ("screenshot file reference and thumbnail", screenshot.testReadProducesAFileReferenceAndABoundedThumbnail),
    ("screenshot read rejects a missing file", screenshot.testReadRejectsAMissingFile),
    ("screenshot paste falls back to the thumbnail", screenshot.testFullResolutionPayloadFallsBackToTheThumbnail)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./scripts/test.sh`
Expected: compile failure — `cannot find 'ScreenshotFile' in scope`.

- [ ] **Step 3: Implement `ScreenshotFile`**

Create `Sources/ElmersCore/ScreenshotFile.swift`:

```swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Reads macOS screenshot files into clipboard payloads.
///
/// Items store a reference to the file plus a small thumbnail: a 6K screenshot
/// is several megabytes and the archive is rewritten whole on every save, so the
/// full-resolution bytes are read from disk only when the item is pasted.
public enum ScreenshotFile {
    /// Longest edge of the stored thumbnail, in pixels.
    public static let thumbnailMaxPixelSize = 512

    public struct Capture: Sendable {
        public let payload: ClipboardPayload
        public let info: ScreenshotInfo
    }

    /// True when the file carries the EXIF UserComment that `screencapture`
    /// embeds in every screenshot. Verified on macOS 26; independent of
    /// Spotlight, so it also works during a backfill scan.
    public static func isScreenshot(at path: String) -> Bool {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let comment = exif[kCGImagePropertyExifUserComment] as? String
        else { return false }
        return comment.caseInsensitiveCompare("Screenshot") == .orderedSame
    }

    /// Builds the stored payload for a screenshot file, or nil when the file is
    /// unreadable or is not an image.
    public static func read(path: String, captureType: String?) -> Capture? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let thumbnail = thumbnailData(from: source)
        else { return nil }
        let url = URL(fileURLWithPath: path).absoluteString
        let payload = ClipboardPayload(items: [["public.file-url": Data(url.utf8), "public.png": thumbnail]])
        let info = ScreenshotInfo(path: path, captureType: captureType, pixelWidth: width, pixelHeight: height)
        return Capture(payload: payload, info: info)
    }

    /// The payload to put on the pasteboard. Reads the file when it still
    /// exists; otherwise drops the dead file reference and pastes the thumbnail.
    public static func fullResolutionPayload(for info: ScreenshotInfo, fallback: ClipboardPayload) -> ClipboardPayload {
        guard FileManager.default.fileExists(atPath: info.path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: info.path)),
              data.count <= 32 * 1024 * 1024
        else {
            let items = fallback.items.map { $0.filter { $0.key != "public.file-url" } }.filter { !$0.isEmpty }
            return ClipboardPayload(items: items)
        }
        let url = URL(fileURLWithPath: info.path).absoluteString
        return ClipboardPayload(items: [["public.file-url": Data(url.utf8), "public.png": data]])
    }

    private static func thumbnailData(from source: CGImageSource) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./scripts/test.sh`
Expected: `30 checks, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ElmersCore/ScreenshotFile.swift Tests/ElmersCoreTests/ScreenshotTests.swift Tests/ElmersCoreTests/main.swift
git commit -m "Read screenshot files into a file reference plus a thumbnail"
```

---

### Task 4: Deciding which screenshots to import

**Files:**
- Create: `Sources/ElmersCore/ScreenshotImport.swift`
- Modify: `Tests/ElmersCoreTests/ScreenshotTests.swift`
- Modify: `Tests/ElmersCoreTests/main.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `ScreenshotImport.shouldImport(path:created:watermark:) -> Bool`; `ScreenshotImport.advance(watermark:with:) -> Date`.

This is the watermark logic kept separate from `NSMetadataQuery` so it can be tested without Spotlight. Task 5 is then a thin, hand-verified shell around it.

- [ ] **Step 1: Write the failing tests**

Append to `ScreenshotTests`:

```swift
    /// First run must adopt a watermark without importing the existing corpus:
    /// this machine already has 201 screenshots under the home folder.
    func testFirstRunImportsNothing() {
        let now = Date()
        XCTAssertTrue(!ScreenshotImport.shouldImport(path: "/tmp/a.png", created: now.addingTimeInterval(-60), watermark: nil))
        XCTAssertTrue(!ScreenshotImport.shouldImport(path: "/tmp/a.png", created: now, watermark: nil))
    }

    func testOnlyScreenshotsNewerThanTheWatermarkImport() {
        let mark = Date()
        XCTAssertTrue(ScreenshotImport.shouldImport(path: "/tmp/a.png", created: mark.addingTimeInterval(1), watermark: mark))
        XCTAssertTrue(!ScreenshotImport.shouldImport(path: "/tmp/a.png", created: mark, watermark: mark))
        XCTAssertTrue(!ScreenshotImport.shouldImport(path: "/tmp/a.png", created: mark.addingTimeInterval(-1), watermark: mark))
    }

    /// `screencapture` renames through `..name-XXXX` then `.name` within a few
    /// milliseconds; reacting to either would open a file that is about to move.
    func testHiddenIntermediateFilesAreIgnored() {
        let mark = Date()
        let later = mark.addingTimeInterval(5)
        XCTAssertTrue(!ScreenshotImport.shouldImport(path: "/tmp/.Screenshot.png", created: later, watermark: mark))
        XCTAssertTrue(!ScreenshotImport.shouldImport(path: "/tmp/..Screenshot.png-MCMTqN", created: later, watermark: mark))
        XCTAssertTrue(ScreenshotImport.shouldImport(path: "/tmp/Screenshot.png", created: later, watermark: mark))
    }

    func testWatermarkOnlyMovesForward() {
        let mark = Date()
        XCTAssertEqual(ScreenshotImport.advance(watermark: mark, with: mark.addingTimeInterval(10)), mark.addingTimeInterval(10))
        XCTAssertEqual(ScreenshotImport.advance(watermark: mark, with: mark.addingTimeInterval(-10)), mark)
        XCTAssertEqual(ScreenshotImport.advance(watermark: nil, with: mark), mark)
    }
```

Register them:

```swift
    ("screenshot first run imports nothing", screenshot.testFirstRunImportsNothing),
    ("screenshot watermark gating", screenshot.testOnlyScreenshotsNewerThanTheWatermarkImport),
    ("screenshot hidden files ignored", screenshot.testHiddenIntermediateFilesAreIgnored),
    ("screenshot watermark moves forward", screenshot.testWatermarkOnlyMovesForward)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./scripts/test.sh`
Expected: compile failure — `cannot find 'ScreenshotImport' in scope`.

- [ ] **Step 3: Implement `ScreenshotImport`**

Create `Sources/ElmersCore/ScreenshotImport.swift`:

```swift
import Foundation

/// Decides which detected screenshots belong in the history.
///
/// Kept free of Spotlight and AppKit so the rules are testable; the watcher in
/// the app target is a thin shell around this.
public enum ScreenshotImport {
    /// A screenshot is imported when it is newer than the last one imported and
    /// is not one of `screencapture`'s transient hidden files.
    ///
    /// A nil watermark means Elmers has never recorded one: adopt the current
    /// state without importing anything, so enabling the feature does not pour
    /// the user's entire screenshot folder into the history.
    public static func shouldImport(path: String, created: Date, watermark: Date?) -> Bool {
        guard let watermark else { return false }
        guard !(path as NSString).lastPathComponent.hasPrefix(".") else { return false }
        return created > watermark
    }

    public static func advance(watermark: Date?, with created: Date) -> Date {
        guard let watermark else { return created }
        return max(watermark, created)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./scripts/test.sh`
Expected: `34 checks, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ElmersCore/ScreenshotImport.swift Tests/ElmersCoreTests/ScreenshotTests.swift Tests/ElmersCoreTests/main.swift
git commit -m "Gate screenshot import on a watermark and skip transient files"
```

---

### Task 5: The Spotlight watcher

**Files:**
- Create: `Sources/Elmers/ScreenshotWatcher.swift`

**Interfaces:**
- Consumes: `ScreenshotImport`, `ScreenshotFile` from Tasks 3-4.
- Produces:
  - `final class ScreenshotWatcher`
  - `ScreenshotWatcher.Candidate { let path: String; let captureType: String?; let created: Date }`
  - `init(watermark: Date?, onImport: @escaping @MainActor (Candidate) -> Void, onWatermark: @escaping @MainActor (Date) -> Void)`
  - `func start()`, `func stop()`

There is no automated check for this task: `NSMetadataQuery` needs a live Spotlight index and the app's own TCC identity, neither of which the check executables have. It is verified by hand in Task 9.

- [ ] **Step 1: Implement the watcher**

Create `Sources/Elmers/ScreenshotWatcher.swift`:

```swift
import Foundation
import ElmersCore

/// Watches for new macOS screenshot files via Spotlight.
///
/// Spotlight sets `kMDItemIsScreenCapture` on every screenshot regardless of
/// where it is saved, which a folder watcher on the configured directory would
/// miss when the user picks "Other Location" in the Cmd-Shift-5 UI or changes
/// the save location. Measured latency on macOS 26 is about half a second.
@MainActor
final class ScreenshotWatcher {
    struct Candidate {
        let path: String
        let captureType: String?
        let created: Date
    }

    private let query = NSMetadataQuery()
    private var watermark: Date?
    private let onImport: @MainActor (Candidate) -> Void
    private let onWatermark: @MainActor (Date) -> Void
    private var observers: [NSObjectProtocol] = []
    private var running = false

    init(watermark: Date?, onImport: @escaping @MainActor (Candidate) -> Void, onWatermark: @escaping @MainActor (Date) -> Void) {
        self.watermark = watermark
        self.onImport = onImport
        self.onWatermark = onWatermark
    }

    func start() {
        guard !running else { return }
        running = true
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.notificationBatchingInterval = 0.2
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Adopt the current state on first run, then go live. Without
                // enableUpdates() no further notifications ever arrive.
                self.adoptInitialWatermark()
                self.query.enableUpdates()
            }
        })
        observers.append(center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self else { return }
                let added = note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? []
                self.handle(added)
            }
        })
        query.start()
    }

    func stop() {
        guard running else { return }
        running = false
        query.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private func adoptInitialWatermark() {
        guard watermark == nil else { return }
        let newest = (0..<query.resultCount)
            .compactMap { query.result(at: $0) as? NSMetadataItem }
            .compactMap { $0.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date }
            .max() ?? Date()
        watermark = newest
        onWatermark(newest)
    }

    private func handle(_ items: [NSMetadataItem]) {
        for item in items {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  let created = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date,
                  ScreenshotImport.shouldImport(path: path, created: created, watermark: watermark)
            else { continue }
            // Spotlight can report the file a moment before its bytes settle;
            // the EXIF check also rejects anything that is not really a
            // screenshot, and doubles as the guard for a denied TCC read.
            guard ScreenshotFile.isScreenshot(at: path) else { continue }
            watermark = ScreenshotImport.advance(watermark: watermark, with: created)
            onWatermark(watermark ?? created)
            let type = item.value(forAttribute: "kMDItemScreenCaptureType") as? String
            onImport(Candidate(path: path, captureType: type, created: created))
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `scripts/swift.sh build`
Expected: builds with no errors. Nothing calls the watcher yet; that is Task 6.

- [ ] **Step 3: Commit**

```bash
git add Sources/Elmers/ScreenshotWatcher.swift
git commit -m "Detect new screenshots with a live Spotlight query"
```

---

### Task 6: Wire the watcher into the app

**Files:**
- Modify: `Sources/Elmers/AppModel.swift:56-75` (published properties), `:117-146` (defaults and init), `:153-166` (`start()`), `:167-194` (`poll()`), `:260-272` (`recognizeImageText`)

**Interfaces:**
- Consumes: `ScreenshotWatcher`, `ScreenshotFile`, `ScreenshotInfo`.
- Produces: `AppModel.captureScreenshots: Bool`; `AppModel.importScreenshot(_:)`; `AppModel.accept(payload:source:sourceBundleID:screenshot:)`.

- [ ] **Step 1: Add the setting**

In `Sources/Elmers/AppModel.swift`, next to the other published privacy settings (near `ignoreConfidential` at line 60):

```swift
    @Published var captureScreenshots: Bool {
        didSet { defaults.set(captureScreenshots, forKey: "captureScreenshots"); refreshScreenshotWatcher() }
    }
```

Add the stored watcher alongside the other private state (near `capturePolicy`):

```swift
    private var screenshotWatcher: ScreenshotWatcher?
```

Register the default `true` in the `defaults.register` call at line 121 by adding `"captureScreenshots": true` to the dictionary, and read it in `init` next to `ignoreConfidential = defaults.bool(forKey: "ignoreConfidential")`:

```swift
        captureScreenshots = defaults.bool(forKey: "captureScreenshots")
```

- [ ] **Step 2: Extract the shared capture tail**

`poll()` currently inlines the policy that a screenshot import needs too. Replace the body of the `do` block in `poll()` (lines 181-190) so both paths share one method:

```swift
        do {
            if let payload = try PasteboardCodec.read(from: board, ignoreConfidential: ignoreConfidential, ignoreTransient: ignoreTransient) {
                accept(payload: payload, source: sourceName, sourceBundleID: sourceID)
            }
            lastChange = currentChange
        } catch PasteboardCodec.CaptureError.changedDuringRead {
            // Retry the current clipboard generation on the next poll.
        } catch { lastChange = currentChange; message = error.localizedDescription }
```

and add the extracted method next to `poll()`:

```swift
    /// The shared tail of every capture: store, announce, trim, persist, and
    /// kick off the per-kind enrichment.
    private func accept(payload: ClipboardPayload, source: String, sourceBundleID: String?, screenshot: ScreenshotInfo? = nil) {
        let item = history.capture(payload, source: source, sourceBundleID: sourceBundleID, screenshot: screenshot)
        SoundEffects.shared.play(.copy)
        if selectedID == nil { selectedID = item.id }
        prune(); persist()
        if item.kind == .link { fetchLinkPreviews() }
        if item.kind == .image || item.kind == .screenshot { recognizeImageText() }
    }
```

- [ ] **Step 3: Start and stop the watcher**

Add to `start()`, after the timer is scheduled:

```swift
        refreshScreenshotWatcher()
```

and add these methods next to it:

```swift
    private func refreshScreenshotWatcher() {
        guard !isDemo else { return }
        guard captureScreenshots else { screenshotWatcher?.stop(); screenshotWatcher = nil; return }
        guard screenshotWatcher == nil else { return }
        let stored = defaults.object(forKey: "screenshotWatermark") as? Date
        let watcher = ScreenshotWatcher(watermark: stored) { [weak self] candidate in
            self?.importScreenshot(candidate)
        } onWatermark: { [weak self] date in
            self?.defaults.set(date, forKey: "screenshotWatermark")
        }
        screenshotWatcher = watcher
        watcher.start()
    }

    /// Screenshots are attributed to the system screenshot UI, so the existing
    /// Ignore Applications list suppresses them like any other source.
    func importScreenshot(_ candidate: ScreenshotWatcher.Candidate) {
        guard !paused, archiveReadable else { return }
        let excluded = Set(excludedApps.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
        guard !excluded.contains("com.apple.screencaptureui") else { return }
        guard let capture = ScreenshotFile.read(path: candidate.path, captureType: candidate.captureType) else { return }
        accept(payload: capture.payload, source: "Screenshot", sourceBundleID: "com.apple.screencaptureui", screenshot: capture.info)
    }
```

- [ ] **Step 4: Include screenshots in OCR**

In `recognizeImageText()` (line 262), widen the filter:

```swift
        let pending = history.items.filter { ($0.kind == .image || $0.kind == .screenshot) && $0.recognizedText == nil && !recognitionInFlight.contains($0.id) }.prefix(2)
```

- [ ] **Step 5: Verify the build and the suite**

Run: `scripts/swift.sh build && ./scripts/test.sh`
Expected: builds cleanly; `34 checks, 0 failures` (unchanged — this task adds no core checks).

- [ ] **Step 6: Commit**

```bash
git add Sources/Elmers/AppModel.swift
git commit -m "Import detected screenshots through the shared capture path"
```

---

### Task 7: The Privacy setting

**Files:**
- Modify: `Sources/Elmers/SettingsView.swift:139-144`

**Interfaces:**
- Consumes: `AppModel.captureScreenshots` from Task 6.
- Produces: nothing for later tasks.

- [ ] **Step 1: Add the row**

In the Privacy section, directly after the screen-sharing row so capture policy reads top to bottom:

```swift
                row("Capture screenshots", "Add screenshots to the history when you take them. They are still saved to your screenshots folder.", $model.captureScreenshots)
```

- [ ] **Step 2: Verify**

Run: `scripts/swift.sh build`
Expected: builds cleanly.

Then run `scripts/build-app.sh && open dist/Elmers.app`, open Settings › Privacy, and confirm the row appears, toggles, and survives a relaunch.

- [ ] **Step 3: Commit**

```bash
git add Sources/Elmers/SettingsView.swift
git commit -m "Add the Capture screenshots setting to Privacy"
```

---

### Task 8: Cards, paste and Reveal in Finder

**Files:**
- Modify: `Sources/Elmers/CardView.swift:18-23` (accent), `:89-100` (footer), `:101-129` (preview)
- Modify: `Sources/Elmers/HistoryView.swift:196-229` (context menu)
- Modify: `Sources/Elmers/AppModel.swift` (the paste payload path)

**Interfaces:**
- Consumes: `ScreenshotFile.fullResolutionPayload(for:fallback:)`, `ClipboardItem.screenshot`.
- Produces: nothing for later tasks.

- [ ] **Step 1: Render screenshots like images**

In `CardView.swift`, add the accent case:

```swift
        case .image, .screenshot: return Color(red: 0.57, green: 0.32, blue: 0.65)
```

Give the footer the pixel dimensions, which say more about a screenshot than a byte count:

```swift
        case .screenshot:
            guard let shot = item.screenshot else { return "Screenshot" }
            let size = "\(shot.pixelWidth) × \(shot.pixelHeight)"
            return FileManager.default.fileExists(atPath: shot.path) ? size : size + " · file missing"
```

and extend the preview's first branch so screenshots draw their thumbnail:

```swift
            if item.kind == .image || item.kind == .screenshot, let image = imagePreview(item) {
```

`imagePreview` already reads `public.png` from the payload, which is the stored thumbnail, so it needs no change.

- [ ] **Step 2: Reveal the file in Finder**

In `HistoryView.swift`'s `itemMenu`, replace the `.file` branch so screenshots get the same action, disabled when the file is gone:

```swift
        if item.kind == .file {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls); model.dismiss?() }
            Divider()
        }
        if let shot = item.screenshot {
            let present = FileManager.default.fileExists(atPath: shot.path)
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: shot.path)]); model.dismiss?()
            }.disabled(!present)
            Divider()
        }
```

- [ ] **Step 3: Paste the full-resolution file**

`AppModel.selectedAggregate()` (`Sources/Elmers/AppModel.swift:222-227`) is the single chokepoint: both `copy(_:plainText:)` and `activate(_:plainText:)` deliver whatever it returns, and its result is transient — never written back into `history` — so rebuilding a payload there is safe and cannot corrupt a stored item.

Replace it with:

```swift
    /// Screenshots store a thumbnail; delivery swaps in the real file when it is
    /// still on disk, and falls back to the thumbnail when it is not.
    private func deliverablePayload(for item: ClipboardItem) -> ClipboardPayload {
        guard let shot = item.screenshot else { return item.payload }
        return ScreenshotFile.fullResolutionPayload(for: shot, fallback: item.payload)
    }
    func selectedAggregate() -> ClipboardItem? {
        let items = selectedItems
        guard let first = items.first else { return nil }
        if items.count == 1 {
            guard first.screenshot != nil else { return first }
            var hydrated = first
            hydrated.payload = deliverablePayload(for: first)
            return hydrated
        }
        return ClipboardItem(payload: .init(items: items.flatMap { deliverablePayload(for: $0).items }), source: first.source, sourceBundleID: first.sourceBundleID)
    }
```

Two details that matter. Assigning `hydrated.payload` fires the `didSet` that recomputes the fingerprint and the cached kind — harmless here because the value is discarded after delivery, but it is the reason this must not be done to an item inside `history`. And the early `guard first.screenshot != nil` keeps the common non-screenshot path free of any copying.

- [ ] **Step 4: Verify**

Run: `scripts/swift.sh build && ./scripts/test.sh`
Expected: builds cleanly; `34 checks, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Elmers/CardView.swift Sources/Elmers/HistoryView.swift Sources/Elmers/AppModel.swift
git commit -m "Show screenshots on cards and paste the file behind them"
```

---

### Task 9: Interaction check, hand verification and documentation

**Files:**
- Modify: `Sources/Elmers/KeyboardInteractionChecks.swift` (the `checkRecognition` → `checkCopiedHUD` chain)
- Modify: `docs/paste-parity.md`, `issues.md`, `README.md`

**Interfaces:**
- Consumes: everything above.
- Produces: nothing.

- [ ] **Step 1: Add the interaction step**

Insert a step into the existing chain that asserts a screenshot item renders as a screenshot and keeps its marker through a save and reload. Follow the file's established shape — `guard … else { print("FAIL: …"); fflush(stdout); exit(1) }`, then `print("PASS: …")`, then call the next check in the chain:

```swift
    static func checkScreenshotCard(model: AppModel, controller: PanelController) {
        let path = NSTemporaryDirectory() + "elmers-check-\(UUID().uuidString).png"
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 80,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemPink.setFill(); NSRect(x: 0, y: 0, width: 120, height: 80).fill()
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        guard let capture = ScreenshotFile.read(path: path, captureType: "selection") else {
            print("FAIL: screenshot file could not be read"); fflush(stdout); exit(1)
        }
        model.history.capture(capture.payload, source: "Screenshot", sourceBundleID: "com.apple.screencaptureui", screenshot: capture.info)
        model.refreshVisibleItems()
        guard let item = model.visibleItems.first, item.kind == .screenshot, item.screenshot?.pixelWidth == 120 else {
            print("FAIL: captured screenshot did not become a Screenshot item"); fflush(stdout); exit(1)
        }
        guard SearchQuery("screenshot").kind == .screenshot else {
            print("FAIL: the word screenshot no longer selects the Screenshot filter"); fflush(stdout); exit(1)
        }
        print("PASS: a screenshot file becomes a Screenshot card")
        checkCopiedHUD(model: model, controller: controller)
    }
```

Change `checkRecognition`'s final call from `checkCopiedHUD(model:controller:)` to `checkScreenshotCard(model:controller:)` so the new step joins the chain.

Note this check reads a file it wrote itself in the temp directory — it never touches the user's screenshots folder and never starts the watcher, so `--demo` stays hermetic.

- [ ] **Step 2: Run the checks**

Run: `scripts/swift.sh build && ./scripts/test.sh && .build/debug/Elmers --demo --check-interaction`
Expected: `34 checks, 0 failures`, and the interaction run reports one more step than before, including `PASS: a screenshot file becomes a Screenshot card`.

- [ ] **Step 3: Verify by hand on the built app**

The watcher cannot be exercised by the checks. Run:

```bash
scripts/build-app.sh && open dist/Elmers.app
```

Then, in order, confirming each:

1. Take a screenshot with Cmd-Shift-4 of a small, non-private region. Grant the Desktop access prompt if it appears.
2. Within a couple of seconds, open the history with Shift-Cmd-V. The screenshot is the newest card, titled `Screenshot`, showing its thumbnail and `<width> × <height>`.
3. The file is still in the screenshots folder, untouched.
4. Type `screenshot` into the search field: it becomes a type pill and lists only screenshots.
5. Right-click the card: `Reveal in Finder` selects the real file.
6. Press Return to paste into a document: the full-resolution image arrives, not the thumbnail.
7. Move the file to the Trash, reopen the history: the card is still there, the footer says `file missing`, `Reveal in Finder` is disabled, and Return still pastes the thumbnail.
8. Turn Settings › Privacy › Capture screenshots off, take another screenshot: nothing is added. Turn it back on.
9. Quit and relaunch: the screenshot items are still there and still categorised as screenshots.

- [ ] **Step 4: Record the result**

Add a September 17 section to `docs/paste-parity.md` recording what was implemented, what was verified by hand, and the limits from the spec: Control-held screenshots stay `Image`, Spotlight must be enabled, the Desktop TCC prompt, and the ad-hoc signing CDHash problem that re-triggers that prompt on every rebuild.

Mark the screenshot entry in `issues.md` done, dated 2026-09-17, with a one-line note of where the code lives.

Add the `Capture screenshots` setting to the README's feature list.

- [ ] **Step 5: Commit**

```bash
git add docs/paste-parity.md issues.md README.md Sources/Elmers/KeyboardInteractionChecks.swift
git commit -m "Verify screenshot capture and record its limits"
```

---

## Self-review notes

- **Spec coverage.** Data model → Task 1. Payload shape and paste hydration → Tasks 3 and 8. Detection and watermark → Tasks 4 and 5. AppModel integration and the extracted capture tail → Task 6. Setting → Task 7. Search, filter and OCR → Tasks 2 and 6. Presentation and stale files → Task 8. Testing → every task, plus Task 9. Limits → recorded in Task 9.
- **Check count** rises 19 → 24 → 26 → 30 → 34; Tasks 6-8 add no core checks, which is why their expected output stays at 34.
- **Names** used consistently throughout: `ScreenshotInfo`, `ScreenshotFile.Capture`, `ScreenshotFile.read(path:captureType:)`, `ScreenshotFile.fullResolutionPayload(for:fallback:)`, `ScreenshotImport.shouldImport(path:created:watermark:)`, `ScreenshotWatcher.Candidate`, `AppModel.importScreenshot(_:)`, `AppModel.accept(payload:source:sourceBundleID:screenshot:)`.
- **Delivery chokepoint confirmed.** `AppModel.selectedAggregate()` (`Sources/Elmers/AppModel.swift:222-227`) is the only path to both `copy(_:plainText:)` and `activate(_:plainText:)`, so Task 8 hydrates there and nowhere else. Its result never re-enters `history`, so the payload `didSet` that recomputes the fingerprint is harmless.
- **No automated coverage for detection.** Task 5 ships with a compile check only; `NSMetadataQuery`, Spotlight and TCC cannot be driven from the check executables. Task 9 Step 3 is the real verification and must not be skipped or reported as passing without being run.
