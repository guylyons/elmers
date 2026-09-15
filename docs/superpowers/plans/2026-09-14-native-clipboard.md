# Native Clipboard Implementation Plan

> Execute inline using executing-plans; check off verified deliverables.

**Goal:** Deliver the first usable native clipboard capture → history → search → paste flow.
**Architecture:** Pure history/persistence library with a macOS capture adapter and native panel shell.
**Tech Stack:** Swift Package Manager, AppKit, SwiftUI, Carbon; no external dependencies.
**Spec:** `docs/superpowers/specs/2026-09-14-native-clipboard-design.md`

## Constraints

- macOS 14 minimum, Swift 5 language mode under Swift 6 toolchain.
- Preserve all captured representations; never log clipboard content.
- Installed Paste 6.3.11 is the reference. Full parity remains unfinished until the inventory is verified.
- Initial activation uses Control-Option-V to coexist with Paste.

## Tasks

- [x] Core history and persistence: `Sources/ElmersCore/ClipboardItem.swift`, `History.swift`, `Archive.swift`; tests in `Tests/ElmersCoreTests/HistoryTests.swift`. Write failing tests for duplicate promotion, protected pinboards, filtering, retention, archive reload, and corrupt archive rejection. Run `scripts/test.sh`, implement, rerun. Command Line Tools lack XCTest, so checks run as a standalone executable.
- [x] Clipboard boundary: `Sources/ElmersCore/PasteboardCodec.swift` and `Tests/ElmersCoreTests/PasteboardTests.swift`. Use a uniquely named pasteboard to prove rich/plain/binary multi-item round trips and privacy-marker rejection without touching the system clipboard.
- [x] Application: `Sources/Elmers/AppModel.swift`, `PanelController.swift`, `GlobalShortcut.swift`, `main.swift`. Bind capture and persistence to an observable model, restore focus before paste, suppress self-capture, and surface failures. Build with `swift build`.
- [x] Interface: `Sources/Elmers/HistoryView.swift`, `CardView.swift`, `SettingsView.swift`. Match reference panel geometry and implement real search, selection, pinboards, previews, context actions, and settings. Check keyboard and pointer behavior in the running application.
- [x] Packaging: `Resources/Info.plist`, `scripts/build-app.sh`, `.gitignore`, `README.md`. Build a local `.app` bundle, launch it, inspect UI, run all tests and `git diff --check`, and update `docs/paste-parity.md` with evidence and gaps.
