# Checkpoint — September 15, 2026

Repository: `/Users/guy/github/glue`. The built app is still named Elmers. Full Paste parity is unfinished. Reference inspected: Paste 6.3.11 on macOS 26.5.

## What changed

- Card selection happens on mouse-down, eliminating the single/double-click recognition delay. Rich-text metadata and filtered history are cached to reduce redraw work.
- Paste's default history shortcut is Shift-Command-V. Local routing covers navigation, extended selection, quick paste, plain text, search/results focus, editing, rename, new text, undo, pinboards, pause, settings, and quit.
- Search spans pinboards and supports type, app, and date filters. Multi-selection supports copy, paste, pin, unpin, and deletion.
- Undo of duplicate New Text restores the original item, including metadata and pins. Deletion takes current snapshots so redo preserves pinboard membership.
- Right-clicking an already selected item preserves multi-selection.

## Verification and commands

```sh
./scripts/test.sh
./scripts/build-app.sh
.build/debug/Elmers --demo --check-interaction
open dist/Elmers.app
```

The core suite passes 17 checks, including keyboard routing, selection, metadata caching, persistence, capture policy, and isolated pasteboard round trips. The interaction check uses synthetic in-memory content and a mocked delivery callback; it tests undo/redo, context selection, and actual AppKit single/double-click dispatch. It does not verify cross-app delivery or global hotkeys.

Paste and Elmers cannot both own Shift-Command-V. Quit Paste and click Elmers' menu-bar icon to retry registration. Shortcut conflicts appear in Settings. Accessibility-dependent direct paste remains unverified: the reference still showed its permission prompt at the last inspection, despite the user's acknowledgment.

## Remaining work, in priority order

1. Verify actual global/local shortcuts and focus transitions against the running reference, including search, sheets, previews, and multiple keyboard layouts. Implement configurable shortcut recording.
2. Implement Paste Stack (Shift-Command-C, FIFO capture, Command-V consumption, reverse/remove controls). Its shortcut is defined but not registered; Stack is not implemented.
3. Verify direct paste across destination apps after Accessibility is working for both apps. Exercise rich multi-item delivery and plain-text conversion end to end.
4. Add drag and drop, item/pinboard reordering UI, richer editing, and native Share workflows. Compare multi-selection menu behavior in Paste.
5. Implement OCR, richer previews, image caching, and scalable history/payload storage. Current bounds are 2,000 unpinned items and 32 MB per capture; whole archives are rewritten on changes.
6. Complete login/background/sound preferences, screen-sharing privacy, and optional remote previews.
7. Implement cloud/device synchronization and account/companion workflows with the necessary accounts, entitlements, and devices.
8. Complete visual, timing, accessibility, localization, onboarding, and error-state comparisons. The existing panel is an approximation, not a pixel-perfect match.

The repository has no initial commit; project files remain untracked on `feat/native-clipboard`. No personal clipboard captures belong in source control. `AGENTS.md` preserves the full-parity mission and CodeGraph workflow. Earlier September 14 inventory entries describe the initial increment; this checkpoint supersedes their shortcut and test-count notes.

Stack is deferred at the user’s request (September 15). Return to the saved Stack design and implementation plan later; no Stack implementation is included. Continue other parity work now.

## Latest stopping point — shortcut customization

Implemented native shortcut recorders for history activation and next/previous pinboards, Quick Paste and Plain Text modifier selectors, and Restore Defaults. Changes persist through ShortcutSettings. Recording supports Escape cancellation, Delete clearing, and cancellation when its window closes or loses key status. Global activation is suspended during recording and restored afterwards. Duplicate bindings, built-in command collisions, and identical Quick Paste/Plain Text modifiers are rejected. Validation messages are separate from OS registration conflicts so re-registration cannot erase the explanation.

The core suite now contains 18 checks. New coverage includes custom-binding serialization, routing, and conflicts. The AppKit interaction executable additionally dispatches Command-A, Left, Shift-Right, Command-F, Return from search, Return paste, Shift-Return, Command-1, and Shift-Command-1. It exercises the recorder through actual NSApplication event dispatch, plus a window-deactivation notification. Delivery is mocked in these checks; they do not prove cross-app paste or every keyboard layout.

Next session: manually compare the completed shortcut settings UI with Paste, verify recording cancellation via actual window close/app switching, and test the physical global activation shortcut. Then proceed to pinboard drag/reordering and richer item workflows. Stack remains explicitly deferred. Full 1:1 parity is still unfinished; earlier remaining-work categories continue to apply, with basic configurable shortcuts now implemented.

A reference-settings screenshot export was rejected by automatic approval review because it could expose private UI data. The session continued using accessibility labels already inspected; screenshot comparison remains outstanding.

## Keyboard navigation follow-up

Fixed results-focus handoff for first/last item commands, pinboard changes, reopening, and Escape clearing filters. The expanded AppKit interaction check reproduces the previous Command-Down/search-focus bug and passes with the fix. Core checks: 18/18 pass. Official keyboard documentation was consulted; computer-use tools were unavailable for fresh reference UI comparison. This task creates the repository's initial commit, including the previously untracked app baseline. Full parity and physical cross-app/global-shortcut verification remain outstanding.
