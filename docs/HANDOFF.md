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

## September 19 — issue triage and first fixes

Current repository: `/Users/guy/github/elmers`. This checkpoint preserves the user's September 19 additions to `issues.md`, including the open image-scrolling latency report.

- Tab/Shift-Tab now select the next/previous card and focus results; Command-F retains search access. Core routing regressions and actual AppKit dispatch pass.
- Fresh activation resets the entire viewport even if the first card was already selected. A real NSScrollView regression failed before the change and passes afterwards. Failed-paste re-show (`resetState: false`) keeps the current viewport.
- Card typography restored to recorded Paste measurements (15/12/13/12). Synthetic panel render inspected; fresh Paste comparison still needed.
- About uses AboutElmers.png as the standard panel icon; the build script includes the PNG. Bundle bytes verified; manual About appearance check pending.
- Rebuilt `dist/Elmers.app`; the existing daily-use process was not restarted. Core: 19/19. Final bundled synthetic interaction suite passed. Review found no blockers. No personal clipboard data used.

Next: reproduce physical card drag and pinboard reorder with computer-use tools (unavailable this session). Returning the original event in CardMouseObserver means the prior “swallows mouse-down” hypothesis is not established. Provider tests only prove type/data export for the first payload item. Do not call drag fixed based on those tests. Then design screenshot-folder observation plus a persisted Screenshot marker and duplicate handling; see the September 19 section of `docs/paste-parity.md`. Afterward, finish visual/direct-paste checks and scalable payload storage. Stack remains deferred; licensing/subscription stays excluded.

## September 21 — screenshot capture

Branch `feat/screenshot-capture`. New screenshots saved by macOS go into history as a Screenshot type. They are observed in the configured screenshot folder, deduplicated against clipboard copies, and have Show in Finder and Copy File actions. Details and evidence are in the September 21 section of `docs/paste-parity.md`. Checks: `scripts/test.sh` (25/0) and `dist/Elmers.app/Contents/MacOS/Elmers --demo --check-screenshots`. Next: take a real screenshot with the built app running, test a protected custom folder, and compare with Paste. Then return to the physical drag reproduction.

## September 21 — SQLite storage checkpoint

Branch `feat/sqlite-storage`. `HistoryStore` replaces whole-plist saves with incremental SQLite transactions and verified first-launch conversion. The real Application Support directory had already diverged: four SQLite items plus two items in a plist recreated by an older build. The approved recovery path now merges both stores conservatively after copying the plist and SQLite/WAL/SHM into a private recovery directory. Real recovery produced six items; live capture added a seventh, and the 7-item identity survived quit/relaunch unchanged. `history.plist.migrated`, `history.plist.pre-sqlite`, `history.plist.recovered`, the raw recovery directory and `history.plist.post-sqlite` are intentionally retained.

Current verification: `scripts/test.sh` 45/45; bundled interaction, status-item, screenshot and sound checks pass; the 40-image scroll check measured p95 9.45 ms and max 15.79 ms. Storage regressions cover another writer remaining usable across recovery, consistent reads during concurrent saves, unique legacy retirement and fresh rollback exports. Full benchmark and identity evidence are in `docs/paste-parity.md`. The fixture-only live-storage check, `dist/Elmers.app/Contents/MacOS/Elmers --check-live-storage-persistence` (DEBUG only), exercised create, pin, rename, delete, disk reload and cleanup through the real `AppModel`; real capture and full-process restart persistence are also verified. That flag writes into the real Application Support store, so it now refuses to start when `NSRunningApplication` reports another `app.elmers.clipboard` process — quit the daily-use app before running it, and never run it from two unbundled binaries at once, where the bundle identifier is not reported. September 22 review fixes: conversion canonicalises item order and verifies by id, a repeatedly failing recovery reuses its backup directory instead of adding one per launch, saves rebuild their baseline when `PRAGMA data_version` shows another writer committed, and `history.sqlite` is created at 0600 before SQLite opens it.

Rollback to a plist-writing build: quit Elmers, keep every SQLite and recovery file, run `.build/debug/ElmersCoreChecks --storage-backup-plist`, and copy (do not move) the exact fresh filename it prints to `history.plist`; then launch the older build. Each export uses a new `history.plist.post-sqlite[-N]` name and verifies its contents, preserving older exports without reusing a stale snapshot. Returning to this branch will merge any later plist changes back into SQLite. To undo only the historical real recovery merge, quit Elmers and restore the SQLite triplet plus plist from the named `history-recovery-*` directory; do this only after separately preserving the current seven-item database. Never delete retained backups until the user explicitly requests it.

Next storage stage: lazy representation loading, FTS5 and a higher history limit. That requires a separate design because it touches capture, duplicate merging, thumbnails, OCR, preview, drag and paste paths. Outside storage, physical drag/drop and direct-paste verification remain the highest-priority parity gaps.

## September 22 — checkpoint

Branch `feat/sqlite-storage`, worktree `.claude/worktrees/sqlite-storage`, not merged into `main`. `main` still has the user's uncommitted one-line addition to `issues.md` ("user should not be able to copy nothing"); the branch records that issue as fixed, so drop the main-checkout edit when merging.

Done this session:

- **Blank copies are never captured** (`ClipboardPayload.isBlank`, `PasteboardCodec.read`, `AppModel.newItem`, the editor's confirm rule). Paste 6.3.11 records empty and whitespace-only copies; Elmers drops them by the user's decision. Check "blank text is never captured".
- **Pointer drag regression check** committed ("pointer drag starts a card drag session" in `--check-interaction`). It passes, so the September 16 drag report is still not reproduced; see the September 22 parity notes for the cliclick attempt and what a real repro needs.
- **Whole-branch review of the SQLite storage work** (0 Critical, 4 Important, 7 Minor) and a fix wave for the Important findings plus two minors: out-of-order plists convert, tied timestamps recover, repeated failing recoveries reuse their backup, a rename after another writer deleted the row rewrites the payload, a failed save is repeated by the next one, the database file is created 0600, and `--check-live-storage-persistence` refuses to run beside another Elmers. Review and fix reports are in the git-ignored `.superpowers/sdd/2026-09-21-sqlite-storage/` directory. Review minors left open: stale `-wal`/`-shm` beside a missing database, a 0-byte database treated as fresh, `notLoaded` reused for a missing database, the unrouted confirmation sound and the delete sound on New Text undo, and directory mode enforced only on creation. The scoped re-review confirmed every fix and added one open item: when another writer changed the database, `HistoryStore.save` rebuilds the item baseline but not the pinboard baseline (`HistoryStore.swift`, the `data_version` branch), so a pinboard edit committed by a second process can still be replaced by this process's next board save. Pinboards were last-writer-wins before this branch as well; fix by rebuilding `baselineBoards` from the database in the same branch and adding a two-writer board test.

Verification at the stop: `scripts/test.sh` 45/45; rebuilt `dist/Elmers.app` passes `--check-interaction`, `--check-status-item`, `--check-sounds` and `--check-screenshots`. The interaction suite's "typing into a fresh search" step failed once right after a build (fixed 150 ms keystroke delays) and passed on three reruns; it is a timing flake, not fixed. The daily-use app was not running during this session; two idle `--demo` processes left by the previous session were stopped.

Next: merge `feat/sqlite-storage` into `main` (user's call), then a physical drag repro with a card on screen, direct paste with Accessibility, and the storage stage 2 design (lazy payloads, FTS5, higher limits). Paste Stack stays deferred; subscription/licensing stays excluded.


## September 22, later — pinboard merge across writers

Closed the re-review's open item. The suggested fix (rebuild the pinboard baseline from the database) was not used, because a process that had not touched its pinboards would then see them differ from the database and overwrite the other writer. Instead `HistoryStore.save` reads the stored pinboards only when this process changed its own, and `HistoryStore.mergeBoards` does a three-way merge (local, last saved, stored): boards added, edited or deleted here follow this process; all others follow the database, so another writer's additions, edits and deletions survive; an edit here brings back a board deleted elsewhere, as for items; order follows this process only when it reordered. New check "board save keeps another writer's pinboard edits". `scripts/test.sh` 46/46; `--check-interaction` passes.

Next is unchanged: merging `feat/sqlite-storage` into `main` is the user's call, then physical drag repro, direct paste with Accessibility, and the storage stage 2 design.

## September 23 — storage security

Deleted clips were still readable on disk. The live `history.sqlite` held 2–3 items but was 32 MB: 7,841 free pages, all non-zero. The cause was SQLite's default fast secure-delete, which never wipes whole freed pages. The WAL also kept pre-deletion row images. Fixes in `HistoryStore`:

- Every read-write open sets `secure_delete = ON` and `temp_store = MEMORY`. A database without incremental auto-vacuum is switched and rewritten once with `VACUUM`, which also drops pages left by earlier builds. The VACUUM is best-effort: if another process holds a write lock, history still loads and the rewrite runs on a later open.
- A save that deletes or replaces content (item deletion, edits, renames, OCR/link updates, pinboard changes) runs `incremental_vacuum` and `wal_checkpoint(TRUNCATE)`. Opening does the same.
- The history folder is marked excluded from Time Machine, and the flag persists on the folder.

Verified by `scripts/test.sh` (51/51). Four new storage-security checks:
- markers from deleted, edited, renamed and OCR text are absent from the database, WAL and SHM bytes;
- a database built as an earlier build left it loses its deleted row on open;
- the folder is excluded from backups;
- a concurrent writer does not block load. This check fails without the best-effort VACUUM.

On a private copy of the live store, `ElmersCoreChecks --storage-report <dir>` shrank it from 32 MB (7,859 pages) to 86 KB (21 pages) with an empty WAL and an unchanged history identity (`f3948c892d3d`). The copy was deleted afterwards; the live store scrubs itself the first time the new build opens it.

Link previews no longer send or keep cookies. `LinkPreviewFetcher` passes a `URLRequest` with `httpShouldHandleCookies = false` to LinkPresentation, and afterwards clears Elmers' own cookie storage and URL cache (`purgeWebState`, also run at launch). Verification: `Elmers --check-link-preview-privacy http://localtest.me:8765/page`, run against a local server that sets `tracker=…` and logs each request's Cookie header. Without the change, the second fetch sent the cookie back. With it, no request sent a cookie and none was kept. A bare IP address is not a valid test, because cookies from IP hosts are dropped anyway.

Not done by decision: encryption beyond FileVault.

## September 23 — checkpoint

All work is on `main`, pushed to `github`. The `origin` (sourcehut) push failed with "Permission denied (publickey)", so `origin` is behind until the SSH key works there.

Done today (details in `docs/paste-parity.md`, newest sections first):

- **Search mode** as Paste: a quarter-width field with tokens, collapsed pinboards, a chip popover (Type/App/Date/Device, OR within a section, AND across), and Escape one layer at a time. Down arrow leaves the field.
- **Color type** (six hex digits), card and filter chip.
- **Paste's strings table as an inventory**: wording fixes, Writing Tools ⇧⌘E, the Preview unavailable state, the first-use Accessibility prompt, recorder labels and errors (system-wide, menu item, Option-only), and in-place renaming.
- **Image rotate** in the editor; the editor's text area layout fixed.
- **Long histories**: no 2,000-item cap; representations over 64 KB load from SQLite on use; 20,000 items load in about 280 ms and 25 MB; search takes about 3 ms.
- **Pinboards as Paste documents them**: one pinboard per item, deleting a pinboard removes its items, pinned items outlive history, hand ordering and pin by drag. Schema version 2, migrated on the live store with its identity unchanged.
- **17 languages** (`Resources/Localization`). Paste-worded strings use Paste's translation, with the brand swapped; see CLAUDE.md › Localization.
- **Paused menu bar icon**, **link previews in a private web view**, **first-run setup** with a Useful Links pinboard, **Paste Stack** (working; look provisional).

Verification: core 69/69; `--check-interaction` passes in full on an idle Mac; `--check-editor`, `--check-stack`, `--check-link-browser`, `--check-screenshots` and `--check-status-item` pass.

Next, needing Paste on screen (run only while the Mac is idle, with `obs.sh`-style guards; see the memory note on guarding clicks):
1. Paste Stack window: layout, empty state, position, whether entries survive closing.
2. Resizable panel and Compact Mode (Paste saves `NSWindow Frame PasteAppMainWindow` with a 332-pt height).
3. The context menu with Shift held (Paste as Plain Text), search highlighting, the "≡ 1" card marker, the Nothing found layout, image card footers, the Space preview, and the "Delete selected items?" confirmation. Deleting the test items left in Paste's history on September 23 (`#123456`, `FF8800`, `rgb(…)` and similar) cleans them up at the same time.
4. Popover horizontal offset; dark appearance; Hebrew right-to-left.
