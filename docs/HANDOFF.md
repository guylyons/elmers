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

## September 16 checkpoint — reference inspection and parity pass

Paste 6.3.11 was inspected live through accessibility dumps and real clicks (see the September 16 section of `paste-parity.md`). Subscription/licensing features are out of scope by the user's decision.

What changed:

- Return pastes with a single press from the search field; Tab switches focus. Menu bar icon toggles the panel both ways. Original synthesized sound effects for capture and paste, with a Sound effects toggle.
- Settings rebuilt to Paste's structure: sidebar (General, Privacy, Shortcuts, Help Center), Open at login (SMAppService), Run in background (Dock icon policy), iCloud sync shown as not available, Paste Items radio group with "Always paste as Plain Text", Keep History slider with Paste's lower-limit confirmation, Erase History…, Show during screen sharing, Ignore Applications list with an app chooser, Reset shortcuts confirmation. Window chrome matches (640×592, hidden title).
- Card context menu, pinboard menu (8 colors, Delete… confirmation), and overflow menu reordered to match Paste. Card headers use the source app's dominant icon color; relative times use Paste's wording.
- App icon from `Resources/AppIcon.png` compiled into `AppIcon.icns` by `scripts/build-app.sh`.
- Floating rich-text editor for New Text Item (⌘N) and Edit (⌘E) with B/I/U/S, Writing Tools, live counters and Escape/⌘↩ handling.
- Link previews (Privacy › Generate link previews, default off): title and downscaled image stored on the item and shown on link cards.
- Drag and drop: cards drag out with all representations; pinboard pills reorder by drag.

Testing note: this Mac has two displays and the panel opens on the display under the pointer. Move the pointer onto the target display before scripted clicks, and send Escape with a raw CGEvent rather than cliclick.

Remaining work, in priority order:

1. ~~New Text Item / Edit floating editors~~ done (see `EditorController.swift`); image editing (rotate) in the editor remains open.
2. ~~Link previews~~ done (default off; see `LinkPreviewFetcher.swift`). Still open: image/file preview polish and comparing the Space preview against Paste's (not captured this session).
3. Paste Stack (still deferred by the user). Drag-out and pinboard drag reordering are implemented but unverified against Paste and across apps.
4. Direct paste end-to-end with Accessibility, then "Paste to <app>" verification across apps.
5. Visual polish: General section overflow by ~40 pt versus Paste, sidebar row offsets, scroll position when the selection is not the first card, panel materials.
6. Storage scalability, OCR, accessibility/localization audits.

## September 16, end of session — stopping point

Commits this session, newest first: OCR + icon build, drag and drop, link previews, floating editor, settings/menus/sounds. All checks green at the stop: `scripts/test.sh` 18/18, `--check-interaction` 30 steps (three consecutive clean runs), `--check-status-item` pass.

State of the built app (`dist/Elmers.app`, running from the menu bar):

- Done today: Return-in-search single press, arrows navigate while typing, menu bar toggle, synthesized sounds, Paste-shaped Settings, matching menus, app-colored cards, floating rich-text editor (⌘N/⌘E), link previews (Privacy toggle, default off), card drag-out and pinboard drag reorder, OCR search for images, app icon generated at build time from `Resources/AppIcon.png` (the `.icns` is no longer tracked; `scripts/build-app.sh` regenerates it when the PNG is newer).
- Later on September 16: typing a content-type word (any case) into the search turns it into a type pill, clears the field, and searches within that type; Backspace on the empty field removes the pill (`SearchQuery.swift`, `AppModel.absorbTypedFilter`). Core suite 19/19; `--check-interaction` 33 steps. Setting `ELMERS_CAPTURE_DIR` while running the interaction check writes a PNG of the demo panel, which is the safe way to eyeball the panel without exposing real history.
- Menu bar icon: the character from `Resources/Toolbar.png`, rendered in color at 20 pt by `StatusIcon.swift`; the template variant looked like a small blob because the white cloud disappears.
- User decisions: no subscription/licensing features; Paste Stack stays deferred.

Next session, in order:

1. Verify by hand what scripting could not: Paste's Space preview presentation, a real cross-app drag from a card, link previews with the toggle on, OCR search on a real screenshot, direct paste with Accessibility.
2. Visual pass on the panel against Paste at the same width: card radius/shadow/selection ring, toolbar spacing, hidden horizontal scroller, empty and paused states. General settings overflows Paste's height by roughly 40 pt.
3. Storage: move large payloads out of the single plist (payload files keyed by fingerprint, schema v2 with migration) before claiming large-history parity; raise the 2,000-item/32 MB bounds afterwards.
4. Remaining reference features: Writing Tools on cards (⇧⌘E), Share Pinboard, image rotate in the editor, Paste Stack when un-deferred, accessibility/VoiceOver audit.

Testing notes: two displays are attached; panels open on the display under the pointer, so move the pointer first (`cliclick m:x,y`). Send Escape/Space with a raw CGEvent (`scratchpad/key.swift` pattern), not `cliclick kp:`. Never send System Events `keystroke` unless the target app is frontmost. Keep captures window-bound; full-screen captures exposed private content.

## September 16, evening — copy overlay, hover states, larger card text

Done: Paste's "Copied / Enable Direct Paste ›" overlay (`CopiedHUD.swift`, shown by `PanelController.showCopied()` on clipboard-mode paste and ⌘C; measured against Paste's 200-pt HUD window), hover states (selected ring dims to gray while the pointer is on another card; faint capsule/circle highlights on pills and toolbar buttons), card geometry matched to Paste (235×236, 50-pt flat header, 46-pt icon, outside 3-pt ring, no border when unselected), link footers with host + path on up to two lines over a #F3F4F7 body, "now"/"30 seconds ago" wording. Card text is intentionally larger than Paste's measured 15/12/13/12 (see the parity table) because the user asked for bigger history text; the search type pills are untouched by request.

Checks at the stop: `scripts/test.sh` 19/19, `--check-interaction` 34 steps (new Copied HUD step; `ELMERS_CAPTURE_DIR` now also writes `panel.png` and `copied-hud.png`), `--check-status-item` pass. The user's "Show during screen sharing" setting was toggled on for captures and restored to off.

Next: **drag and drop does not work on the built app (user report, September 16)**; the drag-out and pill-reorder code only passed the in-process provider check, so verify with a real pointer drag first (suspect the mouse-down selection observer swallowing the drag). Then update the About popup to show `Resources/AboutElmers.png` (committed, unused; the build script does not copy it into the bundle yet). Then the search-open toolbar state (pills collapse to icon/dot, wider field with filter icon), Paste's direct-paste feedback (unobserved), the Space preview presentation, and the earlier storage/OCR/accessibility items.
