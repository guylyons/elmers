# Automatic screenshot capture

Status: UX approved by the user on September 21; implementation in progress. The approved UX refinements below supersede conflicting initial proposals.

## Intended result

When macOS saves a new screenshot while Elmers is running and capture is enabled, Elmers adds an image-backed history item in a distinct **Screenshot** category. macOS continues saving the original file in the user's chosen folder. The Elmers copy remains usable after the original is moved or deleted. Existing image preview, OCR, selection, copy/paste, pinning, and retention behavior applies.

User requirements come from `issues.md` and the September 21 request. This is an explicit requested feature; installed Paste behavior for automatic screenshot-folder ingestion is not yet verified. Do not label this feature reference-verified on the basis of its tests.

## Evidence and existing boundaries

- Read-only inspection on September 21 found `com.apple.screencapture` configured for file output in `~/Desktop/Screenshots`, including `location-screenshot` and legacy `location` keys. No settings were changed.
- Apple documents selecting the save destination in Screenshot's Options menu: https://support.apple.com/en-us/102646. These preference key names are locally observed implementation details, not a public API guarantee.
- Apple provides directory event observation through `DispatchSourceFileSystemObject`: https://developer.apple.com/documentation/dispatch/dispatchsourcefilesystemobject.
- Current `AppModel.poll()` handles clipboard capture, pause, archive-read failures, persistence, sound, and OCR dispatch. `History.capture` deduplicates complete payload fingerprints while retaining pinboard membership.
- `ClipboardItem.kind` is derived from its payload and rebuilt after decoding. `SearchQuery` currently treats screenshot words as Image aliases. Both need explicit screenshot provenance.

## Approach

Use a dedicated screenshot-folder observer feeding the existing history ingestion path. Avoid replacing macOS screenshot shortcuts or starting a screen-capture session.

Alternatives considered:

1. Clipboard-only capture: simplest, but misses screenshots saved only to disk, so it does not meet the request.
2. System-wide Spotlight query: broader discovery, but depends on indexing and makes historical-file exclusion harder to reason about.
3. Configured-folder observation (selected): narrow scope, prompt delivery after save, explicit startup and pause boundaries. Requires recovery from folder changes and delayed writes.

## Capture lifecycle

1. Resolve the screenshot destination from the observed screenshot-specific preference, then legacy preference, then Desktop when no location is configured. Expand `~` and standardize the file URL. Unsupported/non-file destinations do not create or modify files; normal clipboard capture continues.
2. Baseline the selected folder before observing new candidates. Never import baseline files on launch, resume, folder switch, or recovery from an unavailable folder. Screenshots created while Elmers is stopped, paused, or unable to access the folder are intentionally not backfilled.
3. Watch directory changes on a background queue and debounce bursts. A low-frequency configuration/recovery check reopens observation after destination changes, directory replacement, or temporary unavailability. Reconcile once after installing the watcher to cover the baseline/watch setup race.
4. Identify actual screenshots through macOS screenshot metadata, not English filename matching or image extension alone. Validate the metadata mechanism with a newly created harmless screenshot before product code relies on it. If the local probe cannot establish a reliable marker, report the limitation and revise detection rather than importing every image in the folder.
5. New candidates remain pending while metadata or file bytes are incomplete. Read only regular, non-symlink files. Require stable identity, size and modification metadata across a short settling interval and before/after reading, then validate complete image decoding. Retry boundedly for delayed metadata and partial writes; a later file change can trigger another attempt. In-progress or failed reads never create empty history items.
6. Use existing payload-size limits. Preserve the original encoded representation when supported, and create a standard image representation when necessary for existing paste/preview support. Reject unsupported or oversized content with a clear status, leaving the original intact. PNG, JPEG, TIFF and HEIC are the initial raster formats to validate; PDF screenshots are explicitly outside this initial raster implementation and must be reported as unsupported.
7. Deliver immutable results to the main actor. Recheck the current observation generation, pause state, capture setting, exclusions, and archive readability before insertion. A stale asynchronous result cannot cross a pause, folder switch, or disable boundary.
8. After acceptance, use the existing retention, persistence, selection and sound paths; invoke OCR as for images. Never read screenshot bytes, decode images, or enumerate directories on the main thread.

## Classification and persistence

Add `.screenshot` to `ContentKind` and a backward-compatible persisted screenshot provenance field to `ClipboardItem`. Missing provenance in existing archives means an ordinary item. Classification returns Screenshot only for compatible image payloads with that marker; editing to non-image content removes stale screenshot classification.

The provenance records screenshot origin and a best-effort original file URL/bookmark for Show in Finder and Copy File. The embedded image never depends on that file remaining available. Persist embedded image bytes using the current archive system; large-payload storage redesign remains separate. Opening old archives must retain item IDs, boards, titles, timestamps, OCR and previews.

Typing `screenshot` or `screenshots` selects the new filter, case-insensitively. Images includes screenshots; Screenshot narrows to screenshots only. The filter menu gains Screenshot automatically alongside the other types. Screenshot cards and Space previews use the image presentation; OCR searches include screenshots. Existing keyboard behavior for type pills and Backspace remains unchanged.

## Duplicate policy

- Repeated directory events for the same file generation insert once. Moving, renaming or touching an already observed file does not create another item.
- Exact screenshot payload recapture promotes the existing history item and preserves its provenance, pins and user title.
- File observation and clipboard delivery may encode the same screenshot differently. Compare a deterministic decoded image identity for recent screenshot candidates off the main thread, using dimensions and normalized full pixel data rather than a perceptual hash. Match only a short capture-time window across the two capture paths; do not globally collapse unrelated historical images.
- Either arrival order merges into one Screenshot item. Preserve existing item ID and pinboard membership, and retain useful clipboard representations. Conflicting encodings need a deterministic preferred representation and byte-preservation tests. Clearing/deleting an item must not cause unchanged files to be automatically imported again.
- A clipboard-only image without reliable screenshot provenance remains Image. This design does not guess provenance merely because an image resembles a screen.

## User controls, privacy and failures

Add a persisted **Add saved screenshots to history** switch in Privacy, enabled by default for this requested behavior. Explain: “Screenshots stay in your macOS save location. Elmers keeps a copy for searching and pasting.” Show the resolved folder and actionable unavailable/access-denied status there. Demo/test mode never observes the user's screenshot folder.

Pause applies to both clipboard and screenshot capture. Resume establishes a fresh folder baseline. Existing excluded-app policy should conservatively suppress candidates observed while an excluded app is active; record the app at observation time and recheck before ingestion. File observation cannot prove which apps contributed pixels to a saved screenshot; do not claim pixel-level filtering or confidential-pasteboard-marker protection for disk files.

If macOS denies folder access, keep clipboard capture working and show a clear explanation. A user-invoked folder chooser may grant access to the configured folder; it must not silently change the macOS screenshot destination. Do not request Screen Recording access merely to read saved files. No history content, screenshot bytes, or file names are logged or committed.

## Verification and acceptance

Automated tests use temporary directories and generated images with synthetic metadata, with an injectable clock, configuration and event source where needed:

- Existing files are ignored; a new completed marked image is captured once with unchanged source bytes.
- Ordinary images, symlinks, incomplete files, invalid data and oversized inputs do not become screenshots.
- Delayed metadata, partial writes, event bursts, rename/replacement, folder removal/reappearance and destination changes are handled without duplicate imports or stale callbacks.
- Pause/disable/read-failure gates prevent insertion and do not backfill on recovery.
- Screenshot provenance, image data, pins and item IDs survive save/reload; old archives remain readable.
- Both clipboard/file arrival orders merge compatible duplicate screenshots; distinct images and older matches are not accidentally merged.
- Screenshot keyword/menu filtering, ordinary Image separation, OCR eligibility and image presentation work.
- Existing core and AppKit interaction checks continue to pass.

Manual verification uses a harmless synthetic document and a window-only macOS screenshot. Confirm that the original is saved normally, one Screenshot card appears after the file completes, copy/paste delivers the image, and the card survives restart and source-file relocation. Compare filter/card/preview behavior with the running Paste app where available, recording differences and unobserved behavior. Do not capture personal desktop/history content. Measure save-to-history latency; target under one second after stable bytes on local storage, and record actual results rather than claiming the target was met.

## Remaining implementation prerequisites

The detection metadata probe and reference inspection are required before implementation. These are verification dependencies, not claims that the macOS internals are stable or that Paste already implements the requested workflow. The next artifact after design approval is the implementation plan.

## Approved UX refinements

- Quiet capture: no additional popup, notification or sound when a saved screenshot is imported. Keep the macOS thumbnail and markup flow intact; ingest the finalized file.
- Opening Elmers selects the newest screenshot through the existing activation behavior. Capture while browsing preserves the current selection and focus.
- Use an uncropped image preview and a Screenshot label. Space opens the existing large preview; Return keeps existing paste behavior.
- Images includes Screenshot; the dedicated Screenshot filter is a narrower query. No automatic pinboard.
- Show in Finder and Copy File act on the original when available. Missing originals produce an explanation, while the embedded image remains usable. Deleting history never deletes the source.
- No old-file import on startup, resume or destination changes.
- Local metadata inspection found 14 files marked by a binary-plist boolean true at `com.apple.metadata:kMDItemIsScreenCapture`, without reading image contents or recording names. Fresh reference filter inspection did not expose useful labels through computer-use; screenshot-folder behavior in Paste remains unverified.
