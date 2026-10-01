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
  (replaced 2026-09-25 at the user's request with Paste's behavior: typing the start of any chip title offers it in a list under the field, and Down + Return or a click turns it into a token; the word itself stays search text)

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
  [fixed 2026-09-23] Reopened by the user: a card dropped on a pinboard pill was not pinned. A real pointer
  drag onto the Alpha pill showed SwiftUI's drop provider offering only `public.utf8-plain-text`; the private
  `app.elmers.item-ids` type is undeclared, so it never reached the drop handler, which accepted the drop and
  did nothing. The panel now records the card being dragged from the start to the end of the session, and pill
  drops (pin) and card drops inside a pinboard (reorder) read that. Re-dragged onto Alpha: the card was pinned.

- [implemented 2026-09-19; visual check pending] update the About popup to use the About png
  (AboutPanel.swift supplies Resources/AboutElmers.png as the standard About panel's application icon.
  scripts/build-app.sh now bundles the artwork; bundled bytes verified against the source.
  Manual About-window appearance check remains pending.)

- [implemented 2026-09-21; automated checks passed, not yet tried with a real screenshot] capture OS screenshots into the history as their own "Screenshot" category
  (Status corrected 2026-09-28; built in 7ecddb5. Elmers watches the folder macOS saves screenshots to and adds
  only new files marked as screen captures, stored with a `ScreenshotOrigin` marker as the Screenshot type; the
  original file stays where macOS put it. Details in docs/paste-parity.md › September 21. `--check-screenshots`
  passes. Not yet checked by taking a real screenshot with the running app.)
  (requested by the user: when macOS takes a screenshot it should land in Elmers' history like a copied
  image, but categorized as Screenshot rather than Image, and it must still be written to the user's
  normal screenshots folder — Elmers observes, it does not replace `screencapture`. Design open: how to
  detect them (folder watch vs. pasteboard-only), whether the payload embeds the PNG or references the
  file, and how the new category persists — `ContentKind` is derived from the payload today and not
  encoded, so a screenshot needs a stored marker on `ClipboardItem`. Note `SearchQuery` already maps the
  word "screenshot" to the Image filter; that mapping moves to the new category.)

- [done 2026-09-24; approved by the user] match Paste's card font sizes
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

- [fixed 2026-09-21; confirmed fast on real history by the user 2026-09-24] there is a bit of latency when scrolling images, we need to get this down
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

- [done 2026-09-24; approved by the user after listening] Sound effects. Add a small set of UI sounds tied to clipboard actions:
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

- [fixed 2026-09-23] the animation blinks/flickers when clicking search
  (A 60 fps recording of the toolbar showed the focus ring vanishing for one frame as the field finished
  growing, then closing in again from its soft halo over 0.2 s. The ring was held on until focus arrived, but
  that hold was released two run-loop turns after focus was requested, before SwiftUI reported the field
  focused. The hold now ends when focus is reported, with a 0.5 s fallback. Re-recorded after a real click on
  the magnifier and after ⌘F: the ring stays on from mid-open into focus.)

- [fixed 2026-09-28; automated check passed, not yet heard by ear] after a while of using the app it seems like sound stops working
  (Reproduced outside the app with the same AVAudioEngine setup: switching the default output device
  (MacBook Pro Speakers → BlackHole 2ch → back) posts two configuration-change notifications and leaves the
  engine stopped, while the player still reports playing. `SoundEffects` started the engine once behind a
  `started` flag and never again, so every later effect was scheduled into a stopped engine and never reached
  the output. Headphones, AirPods, sleep, or a call app taking over the device all do the same. `play` now
  checks `engine.isRunning` and, when it has stopped, stops the player, restarts the engine and plays again;
  restarting the engine alone was not enough, the player had to be reset too. `--check-sounds` now stops the
  engine and requires the next effect to reach playback: it failed before the fix and passes after.)

- [fixed 2026-09-28] copying an image file in Finder shows a generic file icon on its card instead of a thumbnail
  (File cards always drew an orange `doc.fill` symbol and the name. Paste 6.3.11 draws the file's Quick Look
  thumbnail in icon mode over its full path. Cards now ask `QLThumbnailGenerator` for that thumbnail at Paste's
  measured size and show the path in the footer. Finder also puts the file's name on the clipboard as plain text,
  so file URLs parsed from the item's text were names: real Finder copies had no path, and Reveal in Finder
  selected nothing. Both now read the file-URL representations. Checked with an image file copied in Finder
  into the built app. Details in docs/paste-parity.md › September 28, file cards.)

- [fixed 2026-09-29; not a regression] `--check-scroll-performance` fails: p95 about 19 ms over the 16.7 ms budget (21 of 183 steps)
  (Fails the same way with the file-card change stashed: three runs with it, two without, median about 4.5 ms. Not yet investigated:
  it may be a regression or this machine's state.)
  (Machine state, not code. On 2026-09-29, `main` at 3d0d24a passed 10 of 10 runs, 4 of them at a load average of about 13:
  median 1.1–2.3 ms, p95 6.5–12 ms. 249a316, the commit that recorded the failure, built in a worktree and alternated with
  `main`, measured the same: p95 7–15 ms against 6.6–12 ms. The Sep 28 median of 4.5 ms was 2–4× both builds' median today, so
  that machine was busy. One run of the older build printed no result and could not be reproduced. The check is unchanged; rerun
  it before investigating a p95 failure whose median is also high.)

- [fixed 2026-09-28] a link card with a fetched preview sits its header, and so the source app's icon, a few points
  higher than the cards beside it
  (The preview's image has a fixed 108-pt height, so image, title and a two-line address came to more than the
  182-pt body. The preview's `maxHeight: .infinity` frame had no `minHeight`, so it took its content's height
  instead of clipping; the overflowing column was centered in the 232-pt card and the top 7 pt of the 50-pt
  header were clipped off (9 pt for an image-only preview). The frame now has `minHeight: 0`, so the preview
  takes what the footer leaves and clips. New `--check-card-layout` renders link cards offscreen and measures
  the header tint down the left margin: 43 and 41 pt before, 50 pt for every case after.)
- [fixed 2026-09-29] active paste to direct app not working
  (Not a code bug: the Accessibility grant was pinned to the cdhash of a Sept 17 ad-hoc build. Neither the running
  `dist` build nor `/Applications/Elmers.app` matched it, so `AXIsProcessTrusted()` was false and every pick fell back
  to copy + the Copied overlay, while System Settings still showed Elmers switched on. `build-app.sh` now signs with a
  local self-signed "Elmers Development" identity, whose designated requirement is the bundle ID plus certificate leaf,
  and the grant was reset and re-granted against it. `/Applications/Elmers.app` is still ad-hoc and stays without
  direct paste until it is replaced with a build signed this way.)

- [fixed 2026-09-30; measured, not compared frame by frame with Paste] resizing the panel works but looks awful next to Paste's fluid motion
  (Each drag step cost 17 ms and a third of screen updates came 33 ms apart. Four causes, each measured: the height was
  published through AppModel and re-evaluated the whole history view; a card-wide animation ran after the Compact Mode
  switch; every mouse event laid the panel out synchronously; and the full-width window was resized every frame. Now
  the height lives in PanelGeometry, cards are Equatable, only the icon animates, heights apply once per display refresh,
  and the window holds still while the glass resizes. Recorded: 163–164 of 170 updates on time. Details in
  docs/paste-parity.md › September 30.)

- [fixed 2026-09-30; checked with real clicks] most card menu options do not work
  (Tested every item with real clicks while Elmers was inactive. Show in Finder, Open, Reveal in Finder and ⌘O handed
  focus back to the previous app over Finder or the browser; Share… presented nothing; Paste as Plain Text was offered on
  images and did nothing. Fixed with AppModel.handOff, a Share submenu of sharing services as in Paste, and disabling
  Paste as Plain Text without text. The rest worked. `--check-card-menu` covers Share and Paste as Plain Text.)

- [fixed 2026-09-30] text over hex codes is white in Paste (#668184), dark in Elmers
  (Paste goes by perceived brightness: dark type on #FF8800, white on #668184. `HexColor.prefersDarkText`.)

- [fixed 2026-09-30] the shading behind a card's footer: Paste fades the last lines of text out above "229 characters", and
  lays a dark gradient over an image behind its footer ("817 × 620", "≡ 1"); Elmers has neither. Image footers in Paste
  show the pixel size, Elmers shows the file size.
  (Paste's binary has FooterView with a GradientEffectView (gradientLayer, gradientAlpha) and a ShadowOverlayView. The
  gradient's height and colors still need measuring on harmless fixture cards in Paste.)
  (Measured on test cards: text fades linearly over 35 pt, gone 16 pt above the bottom, now matched. Image cards have no
  gradient; their size and number sit in dark pills, now matched, and the size replaces the file size.)

- [fixed 2026-09-30; measured, not yet tried by the user] scrolling is very very slow (mouse wheel and trackpad sideways)
  (A vertical mouse wheel did not scroll the row at all, and sideways swipes moved it 1:1. Paste scrolls about 10 pt
  per wheel line and moves 1.7–2× a sideways swipe. Scroll events over the panel are now rewritten to match
  (`ScrollMapping`). Also removed a full image read and decode per image card from the card menu, which made image
  cards hitch as they scrolled in. Details in docs/paste-parity.md › September 30, scroll input.)

- [fixed 2026-09-30; compared side by side with Paste] rounding is better on corners in Paste, images show dimensions, and its
  header background colors are better; Screenshot headers should be a system gray
  (Corners already match Paste's profile best at the current continuous 16 pt; the difference was the app icon, which Paste
  draws large and cut by the corner, now matched. Image cards fill with the picture and show "W × H" in a pill. Headers use
  Paste's fixed colors chosen by the icon's dominant hue: 10 of 12 apps match exactly. Screenshot headers are system gray.
  Details in docs/paste-parity.md › September 30, card headers.)
