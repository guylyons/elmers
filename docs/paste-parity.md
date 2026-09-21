# Paste parity inventory

## September 17 — default state when the history opens

User request, not a reference observation: pressing ⇧⌘V (or clicking the menu bar item, or launching) must open the history in a known state — search cleared, no type/source/date filter, the All pinboard, and the most recent item selected so Return pastes it immediately.

| Surface | Behavior | Elmers status |
|---|---|---|
| Activation state | Every fresh activation clears `query`, `kind` (and its typed-filter word), `sourceFilter`, `afterDate` and `boardID`, then selects the newest item with focus on the results, not the search field. | implemented: `AppModel.resetForActivation()`, called from `PanelController.show()` |
| Re-show after a failed paste | The three direct-paste failure paths bring the panel back with the user's search and selection intact. | implemented: those calls pass `show(resetState: false)` |

Verification: `scripts/test.sh` 19/19; `--check-interaction` 35 steps, including the new "opening the history clears search and filters and selects the most recent item" step, which seeds a query, a type filter, a source filter, a date filter and a pinboard, calls the real `show()`, and asserts the cleared state and newest-item focus. The physical ⇧⌘V key press itself is unchanged (`GlobalShortcut` → `toggle()` → `show()`) and remains user-verified only.

## September 16, evening — copy overlay, hover states, card typography

Reference: Paste 6.3.11, main display 1512×982 pt at 2×. Evidence came from window-bound captures of Paste's panel (`screencapture -R` on the frame reported by System Events) and of the 200-pt HUD window, seeded with harmless test text; glyph extents were measured in the captures. Nothing from the user's history is committed.

| Surface | Observed in Paste 6.3.11 | Elmers status |
|---|---|---|
| Copied overlay | After Return in clipboard mode, a 200×200 pt borderless window (`AXUnknown`) appears centered horizontally on the panel's screen with its bottom edge 140 pt above the screen bottom. Gray (about #868686 at 87 % over a soft blur), 18-pt corners. Light "checkmark" 72 pt wide centered 68 pt from the top, "Copied" (about 22 pt) at 142 pt, "Enable Direct Paste ›" (13 pt) at 166 pt. Visible at 0.25 s and 0.85 s, gone by 1.35 s. | implemented in `CopiedHUD.swift`: same size, position, layout and timing (1.0 s then a 0.25 s fade); the button opens Settings. Shown on clipboard-mode paste and on ⌘C; replaces the old "Copied to clipboard." banner. Measured on the built app: checkmark 75 pt, "Copied" and button within 1 px of Paste. Direct-paste mode shows nothing (Paste's direct-paste feedback not observed). |
| Card hover | Hovering an unselected card adds nothing to it, but turns the selected card's ring gray; hovering the selected card, the gaps, or the toolbar keeps the ring blue. | implemented (`ringDimmed` on `CardView`, `hoveredID` in `HistoryView`) |
| Toolbar hover | Unselected pinboard pills get a faint capsule; search, +, and … buttons get a faint 34-pt circle. | implemented (`hoverHighlight` modifier) |
| Card geometry | 235×236 pt, 256-pt pitch (21-pt gap), 50-pt header, flat header color (#1C3EC3 top to bottom for the terminal source, #E65227 for Brave), ~46-pt app icon tucked into the top-right corner, no border on unselected cards, 3-pt accent ring just outside the selected card. | implemented; header tint now clamps brightness to 0.72–0.9 so a navy terminal icon gives Paste's vivid blue (#1A2FB0 measured) |
| Card typography | Measured: title 15 pt semibold, time 12 pt, body 13 pt, footer 12 pt gray. | **Implemented September 19:** restored 15/12/13/12, including 13-pt link/file text. Synthetic panel render inspected with the 235×236 card and 50-pt header retained. Fresh equivalent-state comparison with Paste is pending; not marked verified. |
| Card footer | Counts are centered on one line; link addresses show host + path without scheme, left-aligned, wrapping to two lines that grow upward from the bottom edge; link placeholder bodies are #F3F4F7 rather than white. | implemented |
| Relative time | "now" right after a copy, then "30 seconds ago", "1 minute ago", "4 minutes ago". | implemented ("now" under 30 s, then the system relative formatter) |
| Drag and drop | Paste cards drag into other apps and pinboard pills reorder by drag. | **broken on the built app** (user report, September 16); implemented code passed only the in-process provider check. Needs a real pointer-drag repro. |
| Search open state | With the search field open, pinboard pills collapse to their icon or color dot only and the field grows to about 400 pt with a focus ring and a filter icon inside. | not implemented; noted for a later pass (the type pills inside the field stay as they are by the user's request) |

Verification: `scripts/test.sh` 19/19; `--check-interaction` 34 steps including "Copied HUD shows for about a second, then fades" (also writes `panel.png` and `copied-hud.png` under `ELMERS_CAPTURE_DIR`); `--check-status-item` passes. Physical: overlay captured on the built app over the same screen region as Paste's and compared by pixel extents; card hover, pill hover and … hover captured on the built app. Note for captures: Elmers windows are excluded from `screencapture` while "Show during screen sharing" is off; enable it temporarily in Settings › Privacy (or `defaults write app.elmers.clipboard showDuringScreenSharing -bool true`) and restore it afterwards.

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

### Menu bar icon (September 16, evening)

- The status item now shows the user's character artwork (`Resources/Toolbar.png`, copied into the bundle by `scripts/build-app.sh`). `StatusIcon.swift` fits the visible bounds of the artwork into a 20 pt square at 1x/2x/3x. It is drawn in its own colors: as a template image only the dark parts would survive and the white cloud became a hole, leaving a 10 pt body. A darkness-to-opacity template variant is kept in `StatusIcon.template(from:pointSize:)` if a tinted look is wanted later. Verified with a menu bar capture on the built app; running from `.build` (checks) falls back to the SF Symbol because the resource is not present there.

### Fixes from `issues.md`

- Return sometimes needed two presses: the first press only moved focus from the search field. Return now pastes from either context; Tab still switches focus. Covered by the core routing check and the AppKit dispatch check "Return from search delivers with a single press".
- First typed letter lost ("paige" became "aige"): focusing the search field selected all of its text, so the second letter replaced the first. The insertion point is now moved to the end once the field editor takes focus. Reproduced and fixed by the AppKit check "typing into a fresh search keeps the first letter"; confirmed on the built app.
- Menu bar icon could not hide the panel: the outside-click monitor hid the panel on mouse-down, then the button action re-showed it. The monitor now ignores clicks inside the status item. Verified with real clicks: show, hide, show.
- Sound effects: synthesized copy "pop" and paste "tick", toggle in General.
- Settings now mirror Paste's sections, rows, wording and dialogs (see table).

- Typing a category: Paste's help says relevant filters appear inside the search field as you type and stay visible there. Elmers turns a content-type word (image/images/photo/picture, screenshot/screenshots, link/links/url, file/files, text/texts, content; any case) into the type filter as soon as it is typed: the word leaves the field, a pill shows the type, the placeholder reads "Search images", and further typing searches within that type. Backspace on the empty field removes the pill and puts the word back as text (so "link" can still become "linkedin"). A type chosen from the filter menu shows the same pill. The absorb runs one run-loop turn after the edit because the SwiftUI text field ignores a binding change made inside its own update. Covered by the core check "category keywords in search" and the AppKit steps "typing a type word becomes the type filter and clears the field" and "Backspace on the empty field removes the type filter and restores the word" (real key events, captures via `ELMERS_CAPTURE_DIR`). Not matched: Paste's suggested-filter menu for app and date words; app names already match through the source text search.
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

### OCR (later on September 16)

- `ImageTextRecognizer` runs on-device recognition for image items without stored text, on capture and at launch for older items. An empty string records a run that found nothing. `History.filtered` also matches recognized text and link-preview titles (core check "binary archive round trip" now covers both fields).
- Accurate recognition took about 35 s on first use on this Mac (model warm-up); the fast level took 0.25 s. The app uses accurate in the background; the check uses fast.
- Space preview: a raw Space key event on a selected Paste card produced no separate window and nothing above the panel, so Paste's preview presentation is still unobserved.

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
| Subscription / licensing | Sidebar category exists in Paste | **out of scope** (user decision) | Not a parity gap: no subscription, licensing, payment, trial or feature-gating surfaces are built or tracked. See the Scope exclusions section of `AGENTS.md` |
| Rich content and files | Full format preservation required by project | unexplored | Round-trip tests plus cross-app verification |
| Multi-selection / drag and drop | Multi-selection observed via ⇧/⌘ clicks and ⌘A; drag-out from cards not exercised on the reference this session | in progress | Elmers: cards drag out with every stored representation (checked in-process); pinboard pills reorder by drag (not automated). Cross-app drop and reference comparison remain unverified |
| Edit / new text / previews | New Text Item observed in menu | unexplored | Inspect reference workflows |
| Paste Stack | Shortcut entry observed | unexplored | Inspect queue ordering and delivery |
| OCR | Official search documentation describes image text search | implemented | Vision `VNRecognizeTextRequest` (accurate level, background, two images at a time) fills `recognizedText`; search matches it and the preview window shows it. Checked with a rendered fixture (fast level). Reference behavior not observed locally |
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


## September 19 — issue fixes and next verification

- **Tab navigation — implemented, automated checks passed.** User's September 19 request supersedes the earlier Tab search/results switching behavior documented above. Tab selects the next card; Shift-Tab selects the previous card without extending selection; both focus results. Command-F opens search. Routing checks failed before the change and pass afterwards; actual AppKit dispatch covers both directions and search handoff. Fresh Paste comparison/physical keyboard check remains pending.
- **Activation scroll — implemented, automated checks passed.** The viewport previously reset only if selectedID changed; unchanged selection could retain a clipped first card. A fresh activation now gives the ScrollViewReader a new identity. A regression moves the real NSScrollView 150 points while keeping the first card selected, hides/reopens, and asserts zero offset and unchanged selection. It failed before and passed after the fix. `show(resetState: false)` retains the existing viewport for failed-paste recovery. Physical global activation remains pending.
- **Card typography — implemented.** Restored recorded Paste 6.3.11 sizes in every card text branch. The synthetic panel render was inspected; no new card geometry or title/footer line-limit changes were needed for that fixture. Computer-use tools were unavailable for fresh reference comparison. Full geometry parity is unverified.
- **About artwork — implemented.** Standard About panel now receives the bundled AboutElmers.png as its application icon. Build copies the PNG and its bytes match the source. Manual window appearance check remains pending.
- **Drag/drop — still open.** CardMouseObserver returns the original mouse event and its hitTest returns nil; the old hypothesis that it simply swallows mouse-down is not established. DragSupport still exports only the first payload item. Provider round-trip checks pass, but do not test pointer initiation, multi-item export, external drop acceptance, or pill reordering. Obtain a real pointer reproduction before choosing a fix.
- **Validation:** core suite 19 checks / zero failures with macOS pasteboard access; bundled debug app interaction suite passed including the new viewport regression. Build succeeded with an existing non-Sendable closure warning in the interaction harness. Fixture render: `/tmp/elmers-20260919-checks/panel.png` (temporary, not committed). No personal clipboard captures used.

Recommended next sequence:
1. Physical drag-out (text, rich text, image, multiple files), pinboard reordering, and direct paste in TextEdit/Finder; compare the same workflows in Paste. Fix the demonstrated drag failure before adding another capture path.
2. Screenshot capture design: observe newly created screenshots in the user's configured destination, preserve the original file, ingest stable bytes, and persist an explicit screenshot marker. Handle custom destinations, duplicate clipboard delivery, partial writes, restarts, and missing folder access. Give Screenshot its own filter rather than the current Image alias. Do not scan/import old screenshots by default. This is proposed work, not implemented.
3. Recheck About, card typography, Space preview, search-expanded toolbar, settings overflow, and the horizontal indicator visible in the synthetic capture despite `.scrollIndicators(.hidden)`.
4. Move large payloads out of the monolithic archive with an explicit migration, then benchmark large histories. Continue accessibility and remaining image-editing/Sharing gaps. Paste Stack remains deferred; subscription/licensing stays excluded; iCloud remains blocked on signing, entitlements, and second-device verification.

## September 21 — drag verification attempt

- Resumed the drag investigation using the available computer-use connection. Paste search's accessibility tree showed the existing harmless “Elmers hover test” fixture, but subsequent screenshots showed an unfiltered panel or a filter popover instead. One screenshot request timed out. No reliable pointer-drag reproduction was obtained; no cross-app drop or pinboard reorder is claimed as verified. Do not retain these reference captures in the repository.
- Opened a blank TextEdit destination and closed it after the attempt; no test content was dropped or saved. Dismissed the reference panel. No reference history, pinboards, or settings were changed.
- Code inspection confirms `CardMouseObserver` returns the original event and has a nil hit-test result. Event swallowing remains an unproven hypothesis. `DragSupport.itemProvider` exports all representations of only the first payload item; multi-item drag delivery remains a separate known limitation.
- Fresh verification: `scripts/test.sh` passed **19 checks, zero failures** with macOS pasteboard service access. The restricted sandbox run had eight failed assertions in the three isolated pasteboard checks; the same suite passed with service access. These tests do not establish pointer-drag behavior.
- No application code changed. Next step remains a stable, synthetic-content pointer reproduction against Paste and Elmers before selecting a drag fix.

## September 21 — screenshot capture

- **Screenshot capture — implemented, automated checks passed.** Elmers watches the folder macOS Screenshot saves to (`com.apple.screencapture` `location-screenshot`, then `location`, then Desktop; nothing is watched when the target is clipboard/preview). It adds only files created after observation starts that carry `kMDItemIsScreenCapture`, after two stable observations and a complete ImageIO decode, within the 32 MB bound. Original files are never modified, moved or deleted, and the macOS destination is never changed. Existing screenshots, files moved in, symlinks, renames and files saved while paused or excluded are not imported. PNG/JPEG/TIFF/HEIC are supported; other formats and oversized files surface a status in Settings › Privacy.
- **Screenshot type:** items persist optional `screenshot` provenance and `imageDigest` fields (older archives decode unchanged). Cards say “Screenshot” with a viewfinder icon and render uncropped. The Images filter includes screenshots; typing “screenshot(s)” selects a dedicated Screenshot filter. Preview, Share and OCR treat screenshots as images.
- **Duplicates:** clipboard and file arrivals of the same pixels (SHA-256 over decoded sRGB RGBA) within 10 seconds merge into one item in either order, keeping ID, pins, title and OCR text and combining representations within the capture bound. Clipboard image digests are computed off the main thread (at most four pending).
- **Actions:** Screenshot cards add Show in Finder and Copy File to the context menu. Both check the original's file identity (device, inode, birth time). A missing or replaced original reports this, and the saved image still copies and pastes.
- **Settings › Privacy › Screenshots:** “Add saved screenshots to history” (on by default), the resolved folder with Show in Finder, and a status line. When the folder can't be read, “Allow Folder Access…” stores a read-only security-scoped bookmark for that exact folder.
- **Verification:** `scripts/test.sh` passed 25 checks, zero failures (6 screenshot checks: legacy decode, inclusive filter, both duplicate arrival orders with persistence, stable/partial/renamed/symlinked/restart scanning, delayed completion with original identity, oversized/unmarked/non-image). `Elmers --demo --check-screenshots` passed 25 steps using real directory events on temporary files and generated images. Observed file-to-history latency was 785 ms. Pause, resume, folder switching, preference and exclusion gating, preserved selection and a missing original are covered. `--check-interaction` and `--check-status-item` still pass. The synthetic Screenshot-filter panel render was inspected.
- **Not verified:** a real Command-Shift-3/4/5 capture while the app runs, a TCC-protected custom folder that needs the access chooser, and comparison with Paste's own screenshot handling. Paste 6.3.11 was not re-inspected this session, so the Screenshot type and its placement follow the approved design rather than observed reference behavior.
