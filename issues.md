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

- [open 2026-09-16] drag and drop does not work
  (reported by the user on the built app; card drag-out and pinboard pill reordering are implemented in DragSupport.swift / HistoryView.swift but were only verified through the in-process interaction check, never with a real pointer drag across apps. Reproduce with a real drag from a card into another app, and a pill drag in the toolbar; the mouse-down card selection in CardMouseObserver may be swallowing the drag start)

- [open 2026-09-16] update the About popup to use the About png
  (Resources/AboutElmers.png is committed but unused; the overflow menu's "About Elmers" still calls NSApp.orderFrontStandardAboutPanel. Show the artwork in the About panel — either pass it as the credits/icon of the standard panel or build a custom About window — and copy the PNG into the bundle in scripts/build-app.sh)

- [open 2026-09-17] capture OS screenshots into the history as their own "Screenshot" category
  (requested by the user: when macOS takes a screenshot it should land in Elmers' history like a copied
  image, but categorized as Screenshot rather than Image, and it must still be written to the user's
  normal screenshots folder — Elmers observes, it does not replace `screencapture`. Design open: how to
  detect them (folder watch vs. pasteboard-only), whether the payload embeds the PNG or references the
  file, and how the new category persists — `ContentKind` is derived from the payload today and not
  encoded, so a screenshot needs a stored marker on `ClipboardItem`. Note `SearchQuery` already maps the
  word "screenshot" to the Image filter; that mapping moves to the new category.)

- [open 2026-09-17] match Paste's card font sizes
  (reverses the September 16 request for bigger history text: parity wins. Paste 6.3.11 measured
  title 15 semibold, time 12, body 13, footer 12 gray; `CardView.swift` currently uses 17/13/15/13
  — see lines 33, 35, 58 and the body/title styles at 112/122/126. Dial each back to the measured
  value, then re-check the card geometry that was tuned around the larger text: 235×236 card,
  50-pt header, line limits on link/file titles, and the two-line link footer. Also confirm nothing
  else was sized to compensate, and update the "Card typography" row in docs/paste-parity.md.)

- [decision 2026-09-17] exclude everything subscription/license related
  (standing scope exclusion, recorded in AGENTS.md › Scope exclusions: no Subscription settings pane,
  upgrade prompts, paywalls, feature gating, license checks, trial timers, purchase/restore flows, or
  entitlement-only account sign-in. All features stay unlocked locally. Where Paste shows one of these
  surfaces, record it as observed-and-excluded rather than a parity gap. iCloud sync itself is NOT
  excluded — it is still in scope and blocked only on signing, entitlements and a second device.)
