# Screenshot Capture Implementation Plan

> Execute inline using the executing-plans and test-driven-development workflows. User approved the UX and instructed implementation with “ok go”.

**Goal:** Quietly capture newly saved macOS screenshots into searchable image-backed history, preserving original files.

**Architecture:** A background folder monitor feeds a deterministic candidate tracker and screenshot reader, then passes immutable captures to AppModel. History owns provenance and duplicate reconciliation. Existing views use image behavior with a Screenshot subtype.

**Tech stack:** Swift, AppKit/SwiftUI, Foundation, Dispatch, ImageIO, CryptoKit; no dependencies.

**Spec:** `docs/superpowers/specs/2026-09-21-screenshot-capture-design.md` including approved UX refinements.

## Global constraints

- Preserve macOS screenshot shortcuts, destination, original file bytes and thumbnail/markup flow.
- No old-file imports, source-file deletion, personal fixtures or raw clipboard logging.
- Embedded images remain usable without source files. Images includes screenshots.
- Never steal focus/selection on capture. No new capture popup or sound.
- Pause, disabling, excluded-app periods and unreadable archives prevent ingestion.
- Keep the current 32 MB capture bound; raster screenshots initially, unsupported types reported honestly.

## Review focus

1. Delayed metadata and partial writes: tracker retries while validating stable full image bytes.
2. Folder switches and pause races: generation checks and fresh baselines suppress stale results.
3. Clipboard/file duplicate arrival order: normalized pixel identities merge only recent cross-source matches, preserving pins and IDs.
4. Source removed/replaced: original-file actions validate identity; embedded copy still works.
5. Old archive decoding and image consumers: optional provenance defaults, inclusive Images, OCR and preview remain functional.

## Task 1 — Screenshot identity, persistence and filtering

Files: `Sources/ElmersCore/ClipboardItem.swift`, `History.swift`, `SearchQuery.swift`; new `Screenshot.swift`; `Tests/ElmersCoreTests/ScreenshotTests.swift`, `main.swift`.

- [x] Write tests for persisted provenance, legacy decode, inclusive Image filtering, screenshot keyword and both duplicate arrival orders with pins preserved.
- [x] Run `scripts/test.sh` and observe missing screenshot behavior before implementation.
- [x] Add `ScreenshotOrigin`, `ContentKind.screenshot`, `ContentKind.isImage`, optional screenshot provenance and image digest fields. Extend `History.capture` with optional screenshot/digest arguments and a bounded cross-source merge.
- [x] Derive image identity with ImageIO decoded RGBA pixels, dimension framing and SHA256 off the main thread. Keep exact representation fingerprints unchanged.
- [x] Rerun core tests with pasteboard service access.

## Task 2 — Stable file capture and folder observation

Files: new `Sources/ElmersCore/ScreenshotCapture.swift`; new `Sources/Elmers/ScreenshotMonitor.swift`; extend `ScreenshotTests.swift`.

- [x] Write temporary-folder tests: baseline skip, stable marked image import, burst dedupe, delayed xattr, partial/invalid file, symlink, rename, oversized payload, destination and restart baseline.
- [x] Run failing tests before adding the tracker/reader.
- [x] Add synchronous `ScreenshotScanner` owned exclusively by a background queue. `scan(at:)` returns captures only after two stable observations, valid marker and complete image decode. Baseline identities on creation; retain consumed identities across renames; retry changed/incomplete generations with bounded unchanged attempts.
- [x] Add `ScreenshotMonitor` with directory DispatchSource, settling timer, periodic preference/folder recovery and generation-tagged callbacks. Resolve screenshot-specific location then legacy location then Desktop. No demo observation.
- [x] Test production scanner against real temporary files and xattrs; test decoded image equivalence across encodings.

## Task 3 — App integration and screenshot UX

Files: `AppModel.swift`, new `ScreenshotActions.swift`, `SettingsView.swift`, `HistoryView.swift`, `CardView.swift`, existing image/OCR consumers and interaction checks.

- [x] Add AppKit regression checks for Screenshot type absorption, Images inclusion, preserving selection and screenshots in image preview/OCR eligibility.
- [x] Wire capture preference, pause/exclusion generation invalidation, archive readability and main-actor ingestion. Generate clipboard image digests asynchronously and reconcile both arrival orders without delaying ordinary capture.
- [x] Add Privacy copy, resolved folder/status, reveal and explicit folder-access chooser. Persist authorization bookmark; never change macOS destination.
- [x] Add original-file Show in Finder and Copy File actions; verify file identity and report missing originals. Avoid self-capture by using existing copy tracking.
- [x] Render screenshot cards uncropped and share/preview/OCR as images. Use Screenshot label and existing keyboard behavior. Capture remains silent.
- [x] Run core suite, build app, AppKit interaction checks. Inspect synthetic screenshots only; record manual limitations if computer-use remains unreliable.

## Completion

- [x] Review the full diff, fix substantive findings, rerun affected checks.
- [x] Update parity inventory and handoff with verified behavior, limits and evidence. Leave existing user edits in `issues.md` intact.

## Execution ledger

- Baseline: 19 checks passed in prior service-enabled run; current restricted run repeats the eight pasteboard assertion failures. Re-run with macOS service access for meaningful verification.
- Ruling: work on `feat/screenshot-capture` in the current checkout, preserving existing edits; branch creation required sandbox escalation and succeeded. No worktree created.
- Ruling: user’s explicit “ok go” after UX approval authorizes implementation; keep planning inline and do not introduce another approval round.
- Completion: core suite 25/0 after correcting a test that compared `/var` and `/private/var` paths to the same file. `--check-screenshots` 25 steps passed, and `--check-interaction` and `--check-status-item` still pass. A real OS screenshot and a protected folder remain manual checks.
