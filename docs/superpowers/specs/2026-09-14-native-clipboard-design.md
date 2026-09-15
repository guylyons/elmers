# Native clipboard foundation

The full product goal is parity with the user's installed Paste 6.3.11 on macOS 26.5. This first increment establishes a real native clipboard manager; the broader inventory remains the completion authority.

## Reference observations

Paste has a bottom-aligned, full-screen-width 332-point panel. At 2560×1440 its top-left is (0,1108). A rounded translucent surface contains a centered toolbar, horizontal 230-point cards, approximately 20-point card gaps, colored 48-point headers, source-app icons, relative timestamps, white content previews, and character counts. Selection uses a bright blue outline. Clipboard History and pinboards appear as compact toolbar pills; search, add pinboard, and overflow sit nearby.

Settings use a 648×600 sidebar window: General, Privacy, Shortcuts, Subscription. General includes background/login, sync, sounds, paste destination, and retention. Privacy includes screen sharing, remote previews, confidential/transient exclusions, and ignored applications. Shortcuts include activation, stack, pinboard navigation, Quick Paste, and plain text modifiers.

## Approach

Use Swift Package Manager, Swift 6 compiler in Swift 5 language mode, macOS 14 minimum, AppKit window/system integration, and SwiftUI views. No external dependencies. AppKit offers direct pasteboard representation access and precise panel positioning. An Electron shell would add a bridge and runtime without simplifying these OS behaviors; a browser app cannot implement the required global clipboard workflow.

`ElmersCore` owns Codable clipboard items, ordered history, pinboards, filtering, and atomic versioned persistence. `Elmers` owns polling, source metadata, a global Carbon hotkey, NSPanel, settings, and paste delivery. The capture adapter snapshots every representation of every pasteboard item. Self-writes are suppressed by change count. On app transitions, ambiguous generations involving excluded or unknown apps are skipped; transitions between allowed apps preserve content with unknown attribution if necessary. Confidential/transient markers and excluded source applications prevent capture. Persistence failures surface in the panel; an unreadable archive is never replaced with an empty one.

Use a binary property-list archive stored locally in Application Support/Elmers, with file permissions 0600. The first increment uses a bounded history and in-memory search. Large-payload performance and a paged database are separate measured follow-ups. Pinboards protect items from history expiration.

## First-increment behavior

Capture text, links, images, rich text, and file URLs; preserve raw formats when copying back. Search text and source-app names, filter by type, organize into named pinboards, inspect previews, copy or request direct paste, and remove items from Elmers. Arrow keys select cards; Return pastes; Shift-Return pastes plain text; Command-C copies; Escape clears search then dismisses; Command-1…9 invokes visible items. Use Control-Option-V initially so the running reference retains Shift-Command-V. Explain the temporary shortcut in settings and README.

The panel opens on the pointer's screen and restores the previous application when pasting. Request accessibility only through an explicit product action; when permission is absent, copy to clipboard and explain manual Command-V. Never synthesize a paste if the intended destination cannot be activated.

Settings expose only working preferences: retention, paste destination, privacy exclusions, capture pause, and shortcut instructions. Cloud/account/stack/OCR and broader settings remain visible in the parity inventory, not as fake product controls.

## Validation

Automated checks exercise duplicate promotion without losing pinboards, filtering, pruning, archive round trips and corrupt archives, binary representations, and a real isolated NSPasteboard. Manually launch the bundled app, inspect the panel and settings, copy harmless fixtures, search, restart, and verify history persistence. Compare the panel to the reference at the same screen size. Record gaps honestly.
