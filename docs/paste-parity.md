# Paste parity inventory

## September 16 — reference inspection and parity pass

Reference: Paste **6.3.11** (`com.wiheads.paste`) on macOS **27.0** (26A428). Inspected with real accessibility-tree dumps (System Events), real clicks (cliclick), and window-bound screenshots. Full-screen captures were discarded because they included private desktop content; no clipboard content or screenshots are committed. Subscription and licensing surfaces are **out of scope by the user's decision** and are not tracked below.

### Observed reference behavior

| Surface | Observed in Paste 6.3.11 | Elmers status |
|---|---|---|
| Menu bar / overflow menu | About Paste · New Text Item ⌘N · Settings… ⌘, · Help › (Getting Started, Keyboard Shortcuts, Help Center, Product Updates, Feature Request, Contact Support, Start/Stop Diagnostic, Reset Search Index) · Paste on Twitter · Pause Paste › (Pause ⌘T, Pause for 15m/30m/1h/3h/8h) · Quit ⌘Q | implemented: About, New Text Item ⌘N, Settings ⌘,, Help › Keyboard Shortcuts, Pause › (⌘T + timed), Quit. Web-only help links and diagnostics intentionally absent |
| Settings window | 640×592, sidebar 200 pt: General, Privacy, Shortcuts, Subscription; "Help Center" at sidebar bottom; no title text | implemented (Subscription omitted); verified by window capture side by side |
| Settings › General | Open at login · Run in background · iCloud sync (Not available ⓘ, disabled) · Sound effects · **Paste Items** radio group with descriptions and illustration, "Always paste as Plain Text" checkbox · **Keep History** slider Day/Week/Month/Year/Forever · Erase History… | implemented: login item via SMAppService, background = Dock icon policy, sync row shown as not available, sound toggle, radio group with descriptions (no illustration), plain-text checkbox, slider with lower-limit confirmation ("You have items older than the new history limit…"), Erase History… with confirmation |
| Settings › Privacy | Show during screen sharing · Generate link previews · Ignore confidential content · Ignore transient content · Ignore Applications list (icons, names, +/−; defaults Keychain Access, Passwords) | implemented. "Generate link previews" fetches title and image with LinkPresentation and stores a small PNG on the item; **default off** in Elmers (Paste defaults on) so no URL leaves the Mac until the user opts in. Screen-sharing toggle sets window sharing type. App list uses an application chooser |
| Settings › Shortcuts | Activate Paste ⇧⌘V · Activate Paste Stack ⇧⌘C · Show next Pinboard ⌘→ · Show previous Pinboard ⌘← · Quick Paste ⌘ + 1…9 · Plain Text mode ⇧ · Reset shortcuts to default… (confirmation) | implemented except the Stack recorder (Stack deferred; no dead control) |
| Card context menu (text) | Paste to <previous app> ↩ · Copy ⌘C · — · Edit ⌘E · Writing Tools ⇧⌘E · Rename ⌘R · Delete ⌫ · — · Pin › (pinboards with color dots, Create Pinboard…) · — · Preview Space · Share › | implemented: same order; "Paste to <app>" label when direct paste is on, "Paste" in clipboard mode; Share uses the system share sheet; Writing Tools absent |
| Card context menu (link) | Open ⌘O at top, then the text menu | implemented; file items add Reveal in Finder |
| Pinboard pill context menu | Rename · Share Pinboard · Delete… · row of 8 color swatches (red, orange, yellow, green, blue, purple, pink, gray) | implemented: Rename, Delete… with confirmation, 8 colors; Share Pinboard absent (sync feature) |
| Delete pinboard alert | "Delete “name”?" / "The Pinboard and all its content will be deleted. This action cannot be undone." | implemented with Paste's title; message differs because Elmers keeps items in history and supports undo |
| New Text Item window | Floating 500×360: Cancel · B I U S · Writing Tools · Create; text area; footer "0 characters · 0 words · 0 lines" | implemented (`EditorController`): floating light panel, Bold/Italic/Underline/Strikethrough on selection or typing, Writing Tools on macOS 15.2+, Create enabled once text exists, live counters, Escape cancels, ⌘↩ confirms. RTF is stored only when formatting was applied. Verified by window capture and AppKit checks |
| Edit window | Floating 390×316 sized to content: Cancel · B I U S · Writing Tools · Save; footer counters | implemented with the same editor at 390×316; loads RTF when present; cancel leaves the item unchanged (checked) |
| Cards | 230-pt cards; header colored by the source app (Brave orange, Safari blue, terminal navy), app icon top right, kind + relative time ("3 hours ago", "yesterday"); footer "41 characters" or link host; link placeholder compass | implemented: dominant icon color header, relative wording, footer; link cards show the fetched image/title when previews are on, otherwise a compass placeholder; OCR still open |
| Sounds | Copy.aiff (0.21 s) on capture, Paste.aiff (0.08 s) on paste, toggled by Sound effects | implemented with original synthesized sounds (no assets copied) |
| Search | Field replaces pinboard pills, ≡ filter button at its right; Return with search focused pastes the selection (documented) | implemented; reference search index returned no results locally, so Return-in-search is verified against documentation and Elmers' own checks |

### Fixes from `issues.md`

- Return sometimes needed two presses: the first press only moved focus from the search field. Return now pastes from either context; Tab still switches focus. Covered by the core routing check and the AppKit dispatch check "Return from search delivers with a single press".
- Menu bar icon could not hide the panel: the outside-click monitor hid the panel on mouse-down, then the button action re-showed it. The monitor now ignores clicks inside the status item. Verified with real clicks: show, hide, show.
- Sound effects: synthesized copy "pop" and paste "tick", toggle in General.
- Settings now mirror Paste's sections, rows, wording and dialogs (see table).

- Arrow keys while typing: Left/Right (and Shift variants) now move the card selection while the search field keeps focus, so type → arrow → Return needs no Tab. Option-arrows, Home/End and Delete stay with the text field. Reference behavior not observable locally (Paste's search index returned no results); implemented from the user's request.

### Editor (later on September 16)

- `EditorController` replaces the SwiftUI sheet for ⌘N, ⌘E and the menu entries. The history panel closes while the editor is open and focus returns to the previous app afterwards, as observed in Paste.
- Checks: "editor counters, bold range, and formatted create", "unformatted create stays plain text", "editor cancel preserves and save updates the item" (Escape sent as a real key event). Physical: ⌘N, typing, ⌘B on a selection, Escape via a raw CGEvent (the cliclick key-press path does not deliver Escape to nonactivating panels, which misled two earlier test runs).
- Not matched: Paste's image rotate tools in the editor (images are not editable in Elmers yet).

### Link previews (later on September 16)

- `LinkPreviewFetcher` uses `LPMetadataProvider`; fetches run for link items without a stored preview, at most eight per pass, tracked in memory so a quit mid-fetch retries next time. A fetch that yields nothing is stored as attempted and never retried.
- Verified: archive round trip of `LinkPreview` (core check), and a standalone LinkPresentation probe on this Mac returned a title and a 1024×537 image for a public Apple page. The in-app card rendering with a real fetch was not captured: the scripted UI run kept landing on the second display. Verify by enabling Privacy › Generate link previews and copying a public URL.

### Drag and drop (later on September 16)

- Cards use `onDrag` with an `NSItemProvider` that registers each pasteboard representation under its own type (`DragSupport.swift`); check "drag provider offers every representation" loads RTF back from the provider.
- Pinboard pills are draggable and accept drops to reorder; dropping on the Clipboard History pill moves a board to the front. Not automated and not compared with Paste's reorder gesture.

### Verification on September 16

- `scripts/test.sh`: 18 checks, 0 failures (Return-in-search expectation updated).
- `.build/debug/Elmers --demo --check-interaction`: all steps pass, including the new single-press Return step.
- `.build/debug/Elmers --demo --check-status-item`: passes.
- Physical: status item click cycle on the built app; Settings sections captured and compared with Paste's captures; panel captured showing app-colored headers and relative times.
- Not verified: Open at login on an ad-hoc signed bundle (SMAppService may refuse), Run in background beyond Dock-icon behavior, screen-sharing exclusion with a real share, sound levels by ear.

## Menu bar right-click fix — September 15

- User-reported behavior: right-clicking the Elmers menu bar icon should open Settings. Fresh Paste UI inspection is unavailable in this session because no computer-use tools are exposed; reference parity remains unverified.
- Root cause: the status button only dispatched left-click actions, and Settings was available only through other menus.
- Implemented: dispatch left/right mouse-up events; right-click opens the existing Settings window and dismisses history, while left-click retains history toggle behavior. Tooltip describes the Settings gesture.
- Verification: `Elmers --demo --check-status-item` failed before the fix and passed afterward using real AppKit event dispatch. Covers opening Settings, left-click history, and reopening Settings from visible history. Existing `--check-interaction` checks and all 18 core checks pass with macOS service access. App bundle rebuilt and signed. Physical pointer and reference screenshot comparison remain unverified.

Reference: Paste **6.3.11**, `com.wiheads.paste`, macOS **26.5**, observed 2026-09-14. Local UI inspected through macOS accessibility and a temporary screenshot. Personal clipboard content/screenshots are not committed.

Statuses distinguish observation from implementation. No feature is verified solely by compiling.

| Area | Reference evidence / expected behavior | Status | Validation / gaps |
|---|---|---|---|
| Bottom panel | Observed 2560×332 at screen bottom; translucent rounded background | observed | Compare same-size captures |
| Cards | Horizontal, colored header, source icon, relative time, content, count, blue selection | observed | Text observed; inspect image/file/link examples |
| Search and filters | Toolbar controls; Command-F hints | observed | Inspect filter menu and query behavior |
| Clipboard history | Visible text cards | observed | Check all formats, deduplication and retention |
| Pinboards | Clipboard History / Useful Links pills, Add button, Shift-Command-N hint | observed | Inspect creation, reorder, context menus |
| Overflow | New Text Item, Settings, Help, Pause, Quit | observed | Implement actual commands in increments |
| Pause | Indefinite and 15m/30m/1h/3h/8h menu options | observed | Timed resume needs validation |
| General settings | Login, background, iCloud, sounds, paste destination, retention Day…Forever | observed | Inspect radio labels and nested options |
| Privacy | Screen sharing, link previews, confidential/transient exclusion, ignored apps | observed | Validate each policy independently |
| Shortcuts | Activation, Stack, next/previous pinboard, Quick Paste, Plain Text | observed | Inspect actual key values and behavior |
| Subscription | Sidebar category exists | observed | Account/payment requirements unexplored |
| Rich content and files | Full format preservation required by project | unexplored | Round-trip tests plus cross-app verification |
| Multi-selection / drag and drop | Multi-selection observed via ⇧/⌘ clicks and ⌘A; drag-out from cards not exercised on the reference this session | in progress | Elmers: cards drag out with every stored representation (checked in-process); pinboard pills reorder by drag (not automated). Cross-app drop and reference comparison remain unverified |
| Edit / new text / previews | New Text Item observed in menu | unexplored | Inspect reference workflows |
| Paste Stack | Shortcut entry observed | unexplored | Inspect queue ordering and delivery |
| OCR | Official search documentation describes image text search | unexplored | Installed-version verification required |
| iCloud and companion devices | iCloud toggle observed | blocked | Requires signing, entitlements, and device testing |
| Accessibility / localization | Discovery required | unexplored | VoiceOver, keyboard, contrast, language tests |
| Import/export / recovery | Discovery required | unexplored | Inspect reference |

Official documentation used as supplementary discovery, potentially newer than installed version:
- https://pasteapp.io/help/paste-on-mac
- https://pasteapp.io/help/keyboard-shortcuts
- https://pasteapp.io/help/search-and-filters
- https://pasteapp.io/help/paste-directly-to-other-applications

## Increment 1 — implementation and evidence

Implemented in Swift/AppKit/SwiftUI, with no third-party dependencies:

- Real background capture with raw representation preservation, duplicate promotion, source metadata, privacy markers and application exclusions.
- Versioned atomic local archive; pinboard membership survives recapture and reload; unreadable archives disable capture and edits.
- Bottom translucent panel, horizontal cards, source icons, relative time, selection, text/image/file previews, search and type filters.
- Pinboard creation/rename/removal, pin/unpin, new text items, context copy/paste/delete, previews.
- Menu bar activation, Control-Option-V, arrows, Return/Shift-Return, quick paste, search, pinboard navigation, Escape.
- Working local settings for retention, clipboard/direct-paste destination, exclusions, and timed capture pause.

Verified on 2026-09-14:

- `scripts/build-app.sh` creates and ad-hoc signs `dist/Elmers.app` successfully.
- `scripts/test.sh`: **11 checks, 0 failures**. Covers allowed/excluded source transitions, deduplication with pins, search/type filtering, retention, board deletion, binary archive round trip, corrupt archives, multiple pasteboard items/formats, plain text, and concealed markers. Pasteboards are unique isolated test boards.
- `.build/debug/ElmersCoreChecks --live-capture`: running application captured and persisted synthetic text; previous general clipboard restored if unchanged.
- Manually created a synthetic text item, searched for it, created a Verification pinboard, restarted the app, and observed both the saved text and pinboard in the final panel.
- Compared a cropped panel screenshot with the running reference. Corrected window level so the Dock no longer appears above Elmers.
- Code review identified and corrected exclusion races on app transitions, plain-text paste during search, and silently unsaved edits after archive-load failure.

Remaining verification and differences:

- Direct paste is implemented but not end-to-end verified with Accessibility access in a destination app. Clipboard mode remains the default.
- Full VoiceOver coverage, complete keyboard focus behavior, source-specific card colors, precise relative-time wording, and all reference animations remain unverified or different.
- UI for pinboard item reordering, multi-selection, drag/drop, Paste Stack, OCR, edit transformations, login/background settings, screen-sharing exclusion, sync/accounts/devices and configurable shortcuts remains open.
- Search currently scopes to the selected pinboard; official newer documentation describes global search. Installed-version behavior needs further inspection.
- Capture crossing an app transition involving an excluded/unknown source is conservatively skipped unless an allowed source is declared. Transitions between allowed apps retain content with unknown source attribution when ambiguous.
- Limits: 32 MB per capture, 2,000 unpinned items, in-memory history and whole-archive saves. Large-history performance is not claimed.
- The fixture items and Verification pinboard remain in the local Elmers history for inspection. No personal clipboard data is checked into the repository.

## September 15 checkpoint

See [HANDOFF.md](HANDOFF.md) for the current implementation and remaining work. This supersedes initial-increment shortcut/test notes: history activation now uses Shift-Command-V; 17 core checks pass. Local keyboard routing, range/toggle selection, global search, basic editing/undo, and immediate mouse-down selection are implemented. Full shortcut behavior, direct paste, Stack, and complete visual parity remain unverified or unfinished as detailed in the handoff.

Stack is deferred at the user’s request (September 15). Return to the saved Stack design and implementation plan later; no Stack implementation is included. Continue other parity work now.

Shortcut customization checkpoint: native recorders, modifier selectors, defaults restoration, persistence, and conflict validation are implemented. Core suite expanded to 18 checks; AppKit keyboard/recorder checks added. See the latest HANDOFF section for verification limits and the next task.

## Keyboard navigation fix — September 15

- Reference: [Paste keyboard shortcuts](https://pasteapp.io/help/keyboard-shortcuts), read September 15: Left/Right, Shift-Left/Right, Command-Up/Down, Command-A, and Tab search/results switching. This is documentation evidence; fresh installed-app UI inspection was unavailable because this session exposed no computer-use tools.
- Root cause: first/last-item commands changed selection without releasing the search field; subsequent arrows remained text-editing commands. Reopening and pinboard changes could also retain search focus.
- Implemented: one synchronous results-focus handoff used by first/last navigation, pinboard switching, reopening, Tab/Return, and clearing filters with Escape. Query text is preserved when reopening.
- Acceptance: Command-Up/Down selects an endpoint and returns keyboard control to cards; arrows stay within results; Tab/Shift-Tab moves between query and results; reopening restores results focus. Text editing remains native while search is focused.
- Verification: AppKit regression failed on Command-Down focus before the fix, then passed after it. Expanded real event-dispatch checks cover Tab, endpoints, next item, last-item boundary, reopen focus, existing range selection and delivery routing. `scripts/test.sh`: 18 checks, zero failures. Delivery callbacks are intercepted; physical global shortcuts, cross-app paste, scrolling screenshots and fresh reference visual comparison remain unverified. Status: implemented, automated interaction checks passed; full reference parity remains unverified.
