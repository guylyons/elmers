- [fixed 2026-09-16] sometimes takes two presses of return to select a pasteitem, should only be one
  (Return while the search field had focus only moved focus; it now pastes)
- [done 2026-09-16] we need sound effects. good ones!
  (synthesized copy "pop" and paste "tick"; toggle in Settings › General. Tune in SoundEffects.swift if they need work)
- [fixed 2026-09-16] clicking the toolbar icon to show it works, clicking it again should hide it,
  and it just makes it pop again
- [done 2026-09-16] settings must match what Paste has
  (General/Privacy/Shortcuts rebuilt from a live inspection; Subscription intentionally omitted; link-preview toggle waits on the feature)

- [done 2026-09-16] I should be able to start typing by category and have it work. For instance, "Image" caps or not caps.
  (a type word — image/photo/screenshot, link/url, file, text, singular or plural, any case — turns into a pill in the search field, the field clears, and further typing searches within that type; Backspace on the empty field removes the pill and gives the word back)

- [fixed 2026-09-22; real-pointer drags verified on the demo build] drag and drop does not work
  (Reproduced with physical cliclick drags against a `--demo --demo-fixtures` panel. Pinboard pills never
  started a drag: each pill was a SwiftUI Button, whose click tracking takes the drag events, so `.draggable`
  never fired. Pills are now tappable views with button accessibility, and Beta dragged onto Alpha reorders
  them; clicking a pill still switches pinboards. Card drags did start, but files arrived as SwiftUI copies
  in ~/Library/Caches and multi-file cards dragged only their first file. Cards now drag through an AppKit
  drag session carrying every stored item with every representation: text, RTF (bold 14 pt kept in
  TextEdit), one file and two files all arrive intact in a logging drop target, and Finder copies both files
  while the originals stay in place. Not yet compared with the same drags in Paste, and not re-tried on the
  daily-use /Applications build.)

- [implemented 2026-09-19; visual check pending] update the About popup to use the About png
  (AboutPanel.swift supplies Resources/AboutElmers.png as the standard About panel's application icon.
  scripts/build-app.sh now bundles the artwork; bundled bytes verified against the source.
  Manual About-window appearance check remains pending.)

- [open 2026-09-17] capture OS screenshots into the history as their own "Screenshot" category
  (requested by the user: when macOS takes a screenshot it should land in Elmers' history like a copied
  image, but categorized as Screenshot rather than Image, and it must still be written to the user's
  normal screenshots folder — Elmers observes, it does not replace `screencapture`. Design open: how to
  detect them (folder watch vs. pasteboard-only), whether the payload embeds the PNG or references the
  file, and how the new category persists — `ContentKind` is derived from the payload today and not
  encoded, so a screenshot needs a stored marker on `ClipboardItem`. Note `SearchQuery` already maps the
  word "screenshot" to the Image filter; that mapping moves to the new category.)

- [implemented 2026-09-19; reference comparison pending] match Paste's card font sizes
  (Restored the recorded Paste 6.3.11 measurements: title 15 semibold, time 12, body/link/file
  text 13, footer 12. Kept the 235×236 card and 50-pt header; inspected the synthetic panel render.
  Fresh same-state comparison with Paste remains pending because computer-use tools were unavailable.)

- [decision 2026-09-17] exclude everything subscription/license related
  (standing scope exclusion, recorded in AGENTS.md › Scope exclusions: no Subscription settings pane,
  upgrade prompts, paywalls, feature gating, license checks, trial timers, purchase/restore flows, or
  entitlement-only account sign-in. All features stay unlocked locally. Where Paste shows one of these
  surfaces, record it as observed-and-excluded rather than a parity gap. iCloud sync itself is NOT
  excluded — it is still in scope and blocked only on signing, entitlements and a second device.)

- [fixed 2026-09-19; automated checks passed] Tab should move through the items in the history
  (Tab advances one card; Shift-Tab moves back. Both focus results when used from search;
  Command-F still opens search. Routing and AppKit dispatch checks pass.)

- [duplicate; implementation above] card fonts still do not match Paste
  (reported by the user: the September 16 increase looks bad. Already tracked by the 2026-09-17
  "match Paste's card font sizes" entry above; see its current verification status)

- [fixed 2026-09-19; automated checks passed] ⌘⇧V should always open the history scrolled to the far left
  (Fresh activation recreates the scroll viewport even when the selected first item is unchanged.
  Regression reproduced with a 150-pt offset before the fix and passed afterwards. Failed-paste
  re-show still preserves state. Physical global-shortcut verification remains pending.)

- [fixed 2026-09-21; measured in a synthetic check, feel on real history pending] there is a bit of latency when scrolling images, we need to get this down
  (reported by the user: scrolling the history feels sluggish once image cards are on screen. Likely
  full-size image decoding on the main thread during scroll rather than cached, downsampled thumbnails.
  Measure first — instrument scroll-frame time with image-heavy history — then cache decoded
  thumbnails at card size and decode off the main thread.)
  Measured with `Elmers --demo --check-scroll-performance` (40 generated 3840×2160 PNGs, ~5 MB each;
  each step scrolls the real NSScrollView and forces layout, display and a CA commit). Before: median
  0.8 ms but p95 ~71 ms and max ~99 ms, 30 of 161 steps over 16.7 ms — one hitch per image card
  scrolling in, from decoding the full PNG on the main thread. Fix: `ThumbnailCache` downsamples to
  512 px with ImageIO on a background queue, caches by fingerprint (128 MB limit), and prewarms the
  first 40 items on activation. After: p95 ~9 ms, max ~13 ms, none over 16.7 ms; with 80 images (half
  not prewarmed) p95 7.4 ms, max 11.8 ms. Cards not yet decoded show an empty image area for a moment
  before the thumbnail appears. The Space preview, sharing and drags still use the full image.

- [implemented 2026-09-21; listening check pending] Sound effects. Add a small set of UI sounds tied to clipboard actions:
  a short double-click ("click-click") when an image is grabbed from the
  clipboard, and a distinct confirmation tone on copy. Needs a decision on the
  audio backend, where the asset files live, and a preference to mute them.
  (Kept the existing backend: sounds are synthesized at launch with AVAudioEngine, so there are no
  asset files; Settings › General › Sound effects mutes all of them. Images grabbed from the clipboard
  now play two dry clicks 75 ms apart; text, link and file captures, and copies out of Elmers
  (⌘C, clipboard-mode paste, Copy File) play a rising two-note chime; direct paste keeps the tick.
  Screenshots picked up from the screenshot folder stay silent. `Elmers --demo --check-sounds`
  checks routing and waveform shape; with ELMERS_CAPTURE_DIR set it writes sound-*.wav to audition.
  Note: Paste itself plays one Copy sound for every capture; the image click is a deliberate departure.)

- [fixed 2026-09-22; automated checks passed] user should not be able to copy nothing.
  (A clipboard change whose every representation is empty or whitespace-only text no longer creates a
  card, plays a sound or changes the selection; the same rule blocks New Text / Edit from saving a
  whitespace-only item. Anything else non-empty — images, files, private types with data, HTML with
  an image — still counts as content. Note: Paste 6.3.11 itself records empty and whitespace-only
  copies as cards (observed with marker content on 2026-09-22); dropping them is a deliberate
  departure at the user's request.)
