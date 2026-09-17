# Screenshot capture

User request, September 17, not a reference observation: screenshots taken with the macOS tools must land in Elmers' history like a copied image, categorised as `Screenshot` rather than `Image`, while still being written to the user's normal screenshots folder. Elmers observes; it never replaces `screencapture`.

## Decisions

| Question | Decision |
|---|---|
| Scope | File screenshots only. Control-held clipboard-only screenshots stay `Image` (see Limits). |
| Storage | File reference plus a bounded thumbnail; full-resolution PNG read from disk on paste. |
| Missing file | Keep the card, paste the thumbnail, disable Reveal in Finder, mark the card. |
| Setting | Settings › Privacy, "Capture screenshots", default on. |
| Filtering | `Screenshot` is its own `ContentKind`, not a subset of `Image`. |

## Evidence

Verified on this machine, macOS 26.0 (26A428), with throwaway scripts outside the repository. Test screenshots were 8×8 px captures of a blank region, deleted afterwards.

- `kMDItemIsScreenCapture == 1` is set on every screenshot in any save location, confirmed against the user's non-default `~/Desktop/Screenshots`.
- `kMDItemScreenCaptureType` is one of `selection`, `window`, `display`. No captured-app or window-title attribute exists.
- A live `NSMetadataQuery` fired `NSMetadataQueryDidUpdate` ~0.5 s after a new screenshot was written. Initial gathering of 201 existing screenshots took 0.24 s.
- `screencapture` writes atomically as `..name-XXXXXX` → `.name` → `name` within ~3 ms. A watcher must ignore dotfiles.
- Screenshot PNGs embed EXIF `UserComment = "Screenshot"`, readable through `CGImageSourceCopyPropertiesAtIndex`. This is independent of Spotlight and survives copying the file.
- There is **no** pasteboard marker distinguishing `screencapture -c` output from any other application's image copy: both produce exactly `public.png`, `public.tiff` and AppKit's legacy aliases, with `propertyList(forType:)` nil throughout.
- `PropertyListDecoder` ignores unknown keys and `decodeIfPresent` yields nil for absent ones, verified in both directions. Adding an optional field needs no archive version change.

## Data model

`ContentKind` gains `case screenshot = "Screenshot"`. Because the kind is derived from the payload and never persisted, a screenshot needs a stored marker on `ClipboardItem`:

```swift
public struct ScreenshotInfo: Codable, Equatable, Sendable {
    public var path: String
    public var captureType: String?
    public var pixelWidth: Int
    public var pixelHeight: Int
}
public var screenshot: ScreenshotInfo? { didSet { refreshMetadata() } }
```

`refreshMetadata()` resolves `cachedKind = screenshot != nil ? .screenshot : payload.kind(for: cachedText)`. The new key joins `CodingKeys` and is decoded with `decodeIfPresent`. The archive stays at `version: 1`; no migration code is added, and an older build reading a newer archive ignores the key rather than failing.

The payload carries two representations: `public.file-url` for the screenshot file, and `public.png` for a thumbnail bounded to roughly 30 KB. The thumbnail renders cards without touching the disk and is the fallback when the file is gone. Fingerprinting over this payload gives duplicate promotion for free: re-detecting the same file promotes the existing item instead of inserting a second one, which also makes relaunch backfill idempotent.

## Detection

`ScreenshotWatcher` owns a live `NSMetadataQuery` with predicate `kMDItemIsScreenCapture == 1` scoped to `NSMetadataQueryUserHomeScope`. It sets the watermark and calls `enableUpdates()` on `NSMetadataQueryDidFinishGathering`, then reports items from `NSMetadataQueryUpdateAddedItemsKey` on `NSMetadataQueryDidUpdate`. Each candidate is confirmed by its EXIF `UserComment` before import, and dotfile names are ignored.

A persisted watermark (`screenshotWatermark`, the newest imported screenshot's creation date) prevents importing the existing corpus on first run and backfills screenshots taken while Elmers was not running. First run records the watermark without importing anything.

Home scope is deliberate: it catches Cmd-Shift-5's "Other Location" and survives the user changing the save location, neither of which a folder watcher on the configured directory handles. A folder watcher is not built; if Spotlight indexing proves unreliable, one drops in behind the same interface.

## Application integration

`AppModel` gains `captureScreenshots`, persisted, default true, surfaced in Settings › Privacy. Its `didSet` starts or stops the watcher; `start()` runs the watcher only when the setting is on and the model is not in demo mode, so checks stay hermetic.

Screenshot items are attributed to source `Screenshot` with bundle identifier `com.apple.screencaptureui`, which lets the existing Ignore Applications list suppress them exactly like any other source.

`poll()`'s capture tail — the paused/readable guard, `history.capture`, the copy sound, prune, persist, and the link-preview/OCR triggers — is extracted so the screenshot path shares it rather than duplicating capture policy.

Paste hydrates the item: when the file exists, write the file URL and the full-resolution PNG read from disk; when it does not, write the stored thumbnail alone.

## Search, filtering and OCR

`screenshot` and `screenshots` move off `.image`'s keyword list onto `.screenshot`, so the existing typed-filter pill works unchanged. The filter menu picks the case up from `allCases`. `recognizeImageText()` extends its filter to `.screenshot`, which is the most valuable OCR target in the app.

## Presentation

The card image branch and `Reveal in Finder` extend to screenshots. The footer shows pixel dimensions rather than a byte count. A missing file disables Reveal and marks the card; existence is checked at paste and menu time, not on every render.

## Testing

Core checks: kind derived from the marker; archive round trip preserving `ScreenshotInfo` in both directions, including an archive written without the key; keyword remapping from `Image` to `Screenshot`; duplicate promotion when the same file is detected twice; thumbnail fallback for a missing path. One interaction step asserts a screenshot card renders with its Reveal action.

Detection itself is verified by hand against a real screenshot on the built app, because `NSMetadataQuery` and TCC cannot be exercised from the check executables.

## Limits

- Control-held screenshots that never touch disk remain `Image`. No pasteboard marker exists to identify them, and the only alternative — guessing from a PNG arriving with no matching file — misfires on ordinary image copies. Recorded rather than approximated.
- Detection requires Spotlight indexing on the volume holding the screenshots folder.
- The user's screenshots folder is under `~/Desktop`, which is TCC-gated, so the first read prompts for consent. Declining leaves detection working but import failing; this must degrade without an error loop.
- Ad-hoc signing produces a different CDHash on every build, and TCC matches ad-hoc code by CDHash, so every rebuild re-triggers that prompt until the app uses a stable signing identity. Verified by signing two identical builds.
