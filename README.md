<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="Elmers app icon">
</p>

<h1 align="center">Elmers</h1>

<p align="center">
  <strong>Everything you copy, one keystroke away.</strong><br>
  A free, clean-room clone of <a href="https://pasteapp.io">Paste</a> for macOS.
</p>

<p align="center">
  <a href="https://github.com/guylyons/elmers/releases/latest"><img alt="Download" src="https://img.shields.io/github/v/release/guylyons/elmers?label=download&color=0a84ff"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000?logo=apple">
  <img alt="Price: free" src="https://img.shields.io/badge/price-free-brightgreen">
  <img alt="No dependencies" src="https://img.shields.io/badge/dependencies-none-lightgrey">
</p>

<p align="center">
  <img src="docs/screenshots/panel.png" alt="The Elmers history panel: a row of cards for text, an image, code and a link, each colored by the app it came from">
</p>

Press **⇧⌘V** anywhere. Your clipboard history slides up as a row of cards. Pick one and it's pasted.

That's it. No account, no subscription, no trial, no upsell. Your history never leaves your Mac.

## Why Elmers

[Paste](https://pasteapp.io) is a lovely app, and it's a subscription. Elmers rebuilds it from scratch, **clean-room**: no Paste code or assets, only what anyone can see by using the app and reading its public help pages. The result looks, moves and behaves like Paste, down to the animation curves, and every feature is unlocked for everyone.

## What it does

- **Remembers everything.** Text, rich text, links, images, files and colors, with every format kept, so a paste arrives exactly as you copied it.
- **Finds anything.** Start typing to search. Type `image`, `link` or `file` to filter. Text inside screenshots is searchable too, recognized on your Mac.
- **Pinboards.** Keep snippets you reuse on colored boards. Pinned items never expire. Drag a card onto a board to pin it.
- **Paste Stack.** Press **⇧⌘C**, copy several things, then press ⌘V to paste them back in order.
- **Pastes your way.** Straight into the app you're using, or onto the clipboard. **⇧Return** pastes plain text; **⌘1–9** pastes one of the first nine items.
- **Edit before you paste.** **⌘N** writes a new item; **⌘E** edits one, with rich text and Writing Tools.
- **Drag and drop** cards into any app.
- **Speaks your language.** English plus the 16 languages Paste ships.

<p align="center">
  <img src="docs/screenshots/pinboard.png" alt="A Snippets pinboard with saved code snippets">
</p>

## Private by default

- History is stored **only on this Mac**, in a private database that is excluded from Time Machine. Deleted items are wiped from disk.
- Passwords and other items that apps mark as **confidential** are skipped. Keychain Access and Passwords are ignored, and you can add any app to that list.
- **Pause** capture for 15 minutes to 8 hours, or hide Elmers from screen sharing.
- **Link previews are off** until you turn them on, so Elmers makes no network requests of its own.

## Install

1. Download **Elmers.zip** from the [latest release](https://github.com/guylyons/elmers/releases/latest) and drag **Elmers** into Applications.
2. Open it. Elmers isn't notarized, so macOS will refuse the first time. Go to **System Settings › Privacy & Security** and click **Open Anyway**.
3. Copy something, then press **⇧⌘V**.

Needs macOS 14 or later on Apple silicon.

> [!NOTE]
> Only one app can own ⇧⌘V at a time. If Paste is running, quit it first. To paste straight into other apps, grant Elmers **Accessibility** access when it asks.

## Keyboard shortcuts

| Keys | Action |
|---|---|
| **⇧⌘V** | Show or hide history, from any app |
| **⇧⌘C** | Open the Paste Stack |
| **← →** | Move between cards |
| **Return** | Paste |
| **⇧Return** | Paste as plain text |
| **⌘1 – ⌘9** | Paste one of the first nine items |
| **Space** | Preview |
| **Type**, or **⌘F** | Search |
| **⌘← ⌘→** | Previous or next pinboard |
| **⌘N** / **⌘E** | New item / edit item |
| **⌘T** | Pause capture |
| **Esc** | Close |

Every shortcut can be changed in Settings.

## Build from source

Needs the Xcode Command Line Tools. There are no third-party packages.

```sh
git clone https://github.com/guylyons/elmers.git && cd elmers
./scripts/build-app.sh release
open dist/Elmers.app
```

`./scripts/test.sh` runs the core checks. [CLAUDE.md](CLAUDE.md) covers the UI self-checks, localization rules and the SDK workaround.

## Status

Elmers is used every day and is close to Paste, though it doesn't match it everywhere yet. Every feature is tracked against Paste in [docs/paste-parity.md](docs/paste-parity.md). The main gaps:

- iCloud sync and the iPhone and iPad apps
- A final visual pass on the Paste Stack window, Compact Mode and panel resizing
- VoiceOver and right-to-left layout audits

Found a bug? [Open an issue](https://github.com/guylyons/elmers/issues).

---

<sub>Elmers is an independent project. It is not affiliated with, endorsed by or connected to Paste or its developers. "Paste" is a trademark of its owners.</sub>
