# Paste parity punchlist

Open items for 1:1 parity with Paste 6.3.11, compiled on 2026-09-25 from `docs/paste-parity.md`, `issues.md` and `docs/HANDOFF.md`. Subscription and licensing are out of scope and not listed. Check an item off when it is done and verified, and record the evidence in `docs/paste-parity.md`.

## Not built

- [ ] iCloud sync and shared pinboards (blocked: code signing, entitlements, a second device)
- [ ] "Delete selected items?" confirmation (observe when Paste asks and which buttons it shows)
- [ ] In-app tips: Enable Direct Paste, Open at Login, Run in Background, Enable iCloud Sync (observe placement)
- [ ] Pause: "Paused until …" label and "Paste Paused" / "Paste Resumed" notices
- [ ] Menu bar icon animation (17 frames; observe its trigger)
- [ ] Resizable panel (drag the top edge) and Compact Mode at small heights
- [x] "≡ 1" card marker: Quick Paste numbers while ⌘ is held (September 25)
- [ ] Highlighted matches in search results
- [ ] "Show in" item on search results
- [x] "Paste as Plain Text" in the context menu: the ⇧ alternate of Paste, following the Plain Text modifier (September 25; Paste's own presentation not yet observed)
- [ ] Show in Menu Bar setting (probably conditional; find out when it appears)
- [ ] Right-to-left mirroring for Hebrew (check whether Paste mirrors)
- [ ] Search result ranking

## Known differences

- [ ] Filter popover sits 56 pt left of Paste's
- [ ] Selected pinboard pill is flat; Paste's has a faint gradient
- [ ] Search open: Paste's first-frame field jump and briefly hidden dots

Deliberate departures, kept by your decision: blank copies are ignored, Return in search pastes, Tab moves between cards, one Backspace removes a search token, the image-capture click sound, and undo after deleting a pinboard.

## Built, not yet compared with Paste

- [ ] Paste Stack: window layout, empty state, where it opens, whether entries survive closing
- [ ] Paste Stack: a real ⌘V into another app
- [ ] Space preview window, including the built-in link browser
- [ ] Rename-in-place field
- [ ] Image editor (rotate)
- [ ] Shortcut recorder error position and styling
- [ ] Direct paste Accessibility prompt (Paste probably uses a custom window with an illustration)
- [ ] Onboarding layout
- [ ] "Preview unavailable" and empty-state layouts
- [ ] Drag and drop: the same drags in Paste, a drop onto a pill, multi-select drag, re-check on the daily-use build
- [ ] Direct paste into browsers, Electron apps and terminals
- [ ] Direct paste with Accessibility denied, and focus after the destination quits
- [ ] Paste's direct-paste feedback
- [ ] Light appearance, across the panel and Settings
- [ ] Dark swatches on Color cards
- [ ] Selection ring with a non-blue accent
- [ ] The seven pinboard colors other than red
- [ ] Hover and pressed states in Settings and the filter popover
- [ ] Motion: card selection, scroll-to-selection, switching pinboards
- [ ] Filters: exact date ranges, clicking a token, a query plus a card click
- [ ] Whether Paste lists type chips for kinds absent from history
- [ ] Screenshots: a real ⌘⇧3/4/5 capture, a protected custom folder, Paste's own screenshot handling
- [ ] Link previews with real content
- [ ] OCR search on a real screenshot
- [ ] Card typography in the same state as Paste
- [ ] Open at login on the ad-hoc signed build
- [ ] Screen-sharing exclusion during a real share
- [ ] About window appearance
- [ ] Scrolling and filtering with 20,000 items
- [ ] Global shortcut on other keyboard layouts

## Quality and cleanup

- [ ] VoiceOver audit
- [ ] Native-speaker review of Elmers-only translations
- [x] Storage: leftover `-wal`/`-shm` next to a missing database (moved into a retained `history-orphaned-*` folder, September 25)
- [x] Storage: a 0-byte database treated as fresh (now rejected untouched as damaged, September 25)
- [x] Storage: history folder permissions enforced only on creation (reset to 0700 on every read-write open, September 25)
- [ ] Listening check of the deletion sound
- [ ] Fix the "typing into a fresh search" flake in `--check-interaction`
- [ ] Remove test items (`#123456`, `FF8800`, …) from Paste's history (needs your OK)
