# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

Parity inventory: `docs/paste-parity.md`. Latest checkpoint and next steps: `docs/HANDOFF.md`. Open bugs: `issues.md`.

## Build, run, test

SwiftPM only (Swift 5.9, macOS 14+, no Xcode project, no third-party deps).

- Never call bare `swift`; use `./scripts/swift.sh <args>`. It keeps caches in `.build/`, disables the SwiftPM sandbox, and pins `SDKROOT` to the macOS 26 SDK because the CLT macOS 27 SDK lacks SwiftUI's `@State` macro plugin.
- Build the app bundle: `./scripts/build-app.sh` (or `release`) → ad-hoc signed `dist/Elmers.app`.
- Relaunch after a rebuild: quit the running Elmers, then `open dist/Elmers.app`. Leave `/Applications/Elmers.app` (the daily-use copy) alone.
- Lint: `./scripts/lint.sh [paths]` (swift-format rules in `.swift-format`; layout diagnostics are filtered out). Never run `swift-format format`; it would rewrite the deliberately dense style (4-space indent, `;`-joined statements, long lines).
- Core tests: `./scripts/test.sh`. This is a hand-rolled runner (`ElmersCoreChecks`), not XCTest: there is no single-test filter, and a new check must be registered in the `checks` array in `Tests/ElmersCoreTests/main.swift`.
- UI self-checks are DEBUG flags in `Sources/Elmers/main.swift`, for example `.build/debug/Elmers --demo --check-interaction`. Others: `--check-status-item`, `--check-screenshots`, `--check-scroll-performance`, `--check-global-shortcut`, `--check-sounds`, `--show-settings`. `--demo` uses a separate defaults suite and in-memory content. Set `ELMERS_CAPTURE_DIR=<scratch dir>` to get window-bound PNGs; that is the safe way to look at the UI without exposing real history.
- `--demo --check-editor` runs only the editor checks. They need no keyboard focus, so they are reliable while someone is using the Mac; `--check-interaction` is not, because real input steals the demo panel's focus.
- `--check-live-storage-persistence` writes to the **real** store (run without `--demo`, never with another Elmers process running).
- Known flake: the "typing into a fresh search" step of `--check-interaction` can fail right after a build; rerun before debugging.

## Architecture notes

- Keep pure logic in `ElmersCore` (testable by the runner). AppKit/SwiftUI and OS integration live in `Elmers`, `@MainActor`, with check code behind `#if DEBUG`.
- Store: `~/Library/Application Support/Elmers/history.sqlite` (0600, `secure_delete`, excluded from Time Machine). The README's `history.plist` is stale. Migrations are explicit: bump `HistoryStore.schemaVersion` and add to `migrations`. Newer or damaged databases are rejected untouched. Multiple writers are expected (`PRAGMA data_version`).
- Never delete retained backups (`history.plist.migrated`, `.pre-sqlite`, `.recovered`, `history-recovery-*`) unless the user asks.
- Direct paste needs Accessibility and otherwise falls back to "Copied. Press ⌘V". Only one app can own ⇧⌘V, so quit Paste before testing the shortcut.

## Hands-on UI testing

- Two displays are attached, and the panel opens on the display under the pointer; move it first (`cliclick m:x,y`).
- Send Escape/Space as raw CGEvents, not `cliclick kp:`. Use System Events `keystroke` only when the target app is frontmost.
- Screenshots must be window-bound; full-screen captures have exposed private content. Don't commit reference recordings.

## Git

- Commit directly on `main`, then push to both remotes: `origin` (sourcehut) and `github`.
- Subject: imperative, sentence case, no prefix, no trailing period, describing behavior (e.g. "Never capture a blank copy"). Doc-only commits use `docs:`. The body is prose explaining cause and fix, citing Paste 6.3.11 measurements where relevant.
