---
name: verify
description: Build Elmers, run the core checks and the relevant DEBUG UI self-checks, and relaunch the app for hands-on testing. Use after changing Elmers code and before claiming a change works or committing.
---

Verify the current working tree. `$ARGUMENTS` may name the area changed (e.g. "panel motion", "storage"); use it to pick the UI checks.

1. Lint and core: `./scripts/lint.sh` must print `lint: clean`. Then run `./scripts/test.sh`. Record the "N checks, M failures" line. If anything fails, stop and report the `FAIL` lines.
2. App build: `./scripts/build-app.sh`. This also builds `.build/debug/Elmers`.
3. UI self-checks. Always run `--demo --check-interaction`, then add the checks that cover the change:
   - panel, keyboard, search, selection or paste → `--check-interaction`
   - menu bar icon or menu → `--check-status-item`
   - screenshot capture → `--check-screenshots`
   - card rendering, thumbnails or scrolling → `--check-scroll-performance`
   - shortcuts → `--check-global-shortcut` (quit Paste first; only one app can own ⇧⌘V)
   - sounds → `--check-sounds`
   - Settings → `--show-settings` with `ELMERS_SETTINGS_SECTION=General|Privacy|Shortcuts`

   Run each as `ELMERS_CAPTURE_DIR=<scratchpad dir> .build/debug/Elmers --demo <flag>` and look at the PNGs it writes. Never point `ELMERS_CAPTURE_DIR` inside the repo.
   - If "typing into a fresh search" fails right after a build, rerun once before treating it as a real failure; it is a known flake.
   - Do not run `--check-live-storage-persistence` unless storage changed. It writes to the real store and needs every other Elmers process quit.
4. Hands-on: quit the running Elmers, then `open dist/Elmers.app`. Exercise the changed workflow against Paste using harmless test content. Follow the UI-testing rules in CLAUDE.md: move the pointer to the target display first, send raw CGEvents for Escape/Space, and keep screenshots window-bound. Leave `/Applications/Elmers.app` untouched.
5. Report in the parity-doc form: "core N/N; `--check-…` pass". List anything not compared, and any failure with its output. Do not call a feature verified from checks alone. Visual states must also be compared against Paste.
