# Paste parity inventory

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
| Multi-selection / drag and drop | Discovery required | unexplored | Inspect reference |
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
