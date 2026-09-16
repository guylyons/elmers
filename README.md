# Elmers

A native macOS clipboard manager, being built against the installed Paste app. This is the first working increment, **not full Paste parity**. The feature inventory is in [docs/paste-parity.md](docs/paste-parity.md).

## Build and run

Requires macOS 14 or later and Swift 5.9+ (Xcode Command Line Tools are sufficient). No third-party packages.

Command Line Tools 27.0 ship a macOS 27 SDK whose SwiftUI `@State` macro plugin is missing, so `scripts/swift.sh` builds against the macOS 26 SDK when it is installed. Set `SDKROOT` to override.

```sh
./scripts/build-app.sh
open dist/Elmers.app
```

The app runs in the menu bar. **Shift-Command-V** shows or hides the bottom clipboard panel, matching Paste. Only one app can own it: quit Paste, then click Elmers’ menu-bar icon to retry registration.

Left-click the menu bar icon to toggle history; right-click it to open Settings.

Copy content in another app to populate history. Click a card to select it, double-click or press Return to deliver it. Clipboard mode is the default: after selecting, press Command-V in the destination. Direct paste can be enabled in Settings and requires macOS Accessibility access.

- Type to search; Command-F focuses search. Left/Right still move between cards while you type, so type, arrow, Return works without Tab. Filter by content type from the search toolbar.
- Left/Right selects; Command-1…9 delivers an item; Shift-Return delivers plain text.
- Space opens a preview; Command-C copies the selected item.
- Use + to create pinboards; a card's context menu offers Paste, Copy, Edit, Rename, Delete, Pin, Preview and Share. Right-click a pinboard to rename, delete or recolor it.
- Command-Left/Right switches pinboards; Shift-Command-N creates a pinboard.
- Command-N creates a text item and Command-E edits the selected one in a floating editor with Bold, Italic, Underline, Strikethrough and Writing Tools; Escape cancels, Command-Return saves. The overflow menu contains settings and timed capture pause.

## Data and privacy

History is saved to `~/Library/Application Support/Elmers/history.plist` using an atomic binary archive. It stays on this Mac. Links are fetched for previews only when Privacy › Generate link previews is turned on (off by default). Confidential/transient markers are excluded by default. Settings allow source-app exclusions and retention changes. Pinboards protect items from expiration. An unreadable archive is preserved and capture is suspended to avoid overwriting it.

Current bounds: 2,000 unpinned items and 32 MB per capture. History and raw formats are held in memory; a database/payload store is needed before claiming large-history performance parity. File URLs are preserved as references; Elmers does not back up the referenced files.

## Checks

```sh
./scripts/test.sh
```

Checks use a standalone Swift executable because Command Line Tools do not include XCTest on the development Mac. They exercise real history/archive behavior and uniquely named test pasteboards without changing the general clipboard. Pasteboard checks require access to the macOS pasteboard service; a restricted execution sandbox can deny it. `scripts/test.sh` currently runs 18 checks. With Elmers running, `.build/debug/ElmersCoreChecks --live-capture` optionally verifies capture using a synthetic item and restores the prior clipboard if unchanged.

## Remaining scope

Paste Stack, OCR, drag and drop, login integration, remote previews, cloud/device sync, account flows, and complete visual/accessibility parity remain open. See the inventory for observed versus implemented versus verified behavior.

Current checkpoint, verification limits, and prioritized remaining work: [docs/HANDOFF.md](docs/HANDOFF.md).

Settings mirror Paste's layout: General (Open at login, Run in background, Sound effects, Paste Items, Always paste as Plain Text, Keep History slider, Erase History…), Privacy (Show during screen sharing, confidential/transient exclusion, Ignore Applications with an app chooser) and Shortcuts (recorders for activation and pinboard navigation, Quick Paste and Plain Text modifiers, reset with confirmation). Escape cancels recording; Delete or × clears a binding. Built-in-command conflicts are rejected. Subscription/licensing features are intentionally not part of Elmers.

Sound effects are synthesized at launch (`SoundEffects.swift`); no audio assets are bundled. The app icon is built from `Resources/AppIcon.png` into `AppIcon.icns` during `scripts/build-app.sh`.
