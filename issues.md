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
