---
name: parity-log
description: Record Paste observations, implementation status, and verification evidence in docs/paste-parity.md, issues.md and docs/HANDOFF.md using their existing formats. Use after inspecting Paste, finishing a feature, or fixing a reported issue.
---

Keep the repo's tracking docs current. Read the top of each file before editing and match what is already there.

## docs/paste-parity.md

- Add a new dated section at the **top** (newest first): `## <Month D> — <surface>`. Never reorder or rewrite older sections. Update an older row only to correct its status, and say that it was corrected.
- Open with a reference line: the Paste version (currently 6.3.11), macOS build, display and scale, appearance, and how the evidence was gathered (accessibility tree, window-bound 2× captures, `screencapture -v -R` recordings reduced to numbers).
- Use the table `| Surface | Observed in Paste 6.3.11 | Elmers status |`. Each status cell starts with a status word: `unexplored`, `observed`, `in progress`, `implemented`, `**matched**`, `verified` or `blocked`. Follow it with measurements and the Swift type or function names involved.
- Evidence is numeric: points, hex colors, timings and offsets. Describe what was seen instead of committing reference recordings or screenshots. `docs/screenshots/` holds only the README images.
- End the section with `Not compared: …` and a checks line, for example "Checks: core 51/51; `--check-interaction`, `--check-status-item` pass".
- Subscription, licensing, account and trial surfaces are recorded as "observed and excluded", never as gaps.
- Only call something `verified` when behavior matches, checks pass, and the visual states were compared side by side.

## issues.md

- Change the tag on a bullet rather than deleting it. The tags are `[open YYYY-MM-DD]`, `[fixed YYYY-MM-DD]`, `[done YYYY-MM-DD]` and `[implemented YYYY-MM-DD; visual check pending]`. Add a short explanation of the fix or remaining gap in parentheses.

## docs/HANDOFF.md

- At a checkpoint, add or refresh the dated checkpoint with three parts: what changed, verification (commands and test counts), and remaining work in priority order.

## Privacy

Never paste raw clipboard content from real history into any doc. Use the test fixtures' wording or describe the content type.

Commit doc-only changes with a `docs:` subject (see CLAUDE.md).
