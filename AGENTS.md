# Elmers — Paste parity

## Mission

Build a phenomenal clipboard manager that faithfully replicates **all features of Paste**, the app running on the user's Mac. Paste is the product specification. Match its appearance, interactions, workflows, and system behavior with meticulous attention to detail.

The target is a complete, polished application suitable for daily use. A static mockup, partial feature set, or generic clipboard manager does not meet the goal. Work may ship in increments, but an increment must never be described as full parity.

## Scope exclusions

Standing decision by the user: **everything subscription, licensing, account, payment or trial related is out of scope.** Do not build, stub, or track it — no Subscription settings pane, no upgrade prompts, paywalls, feature gating, license checks, trial timers, purchase or restore flows, or account sign-in that exists only to carry entitlements. Every Elmers feature is unlocked for the local user. When the reference shows one of these surfaces, note that it was observed and excluded rather than treating it as a parity gap. This exclusion does not extend to iCloud sync itself, which stays in scope and is blocked only on signing, entitlements and a second device.

## Reference app and discovery

- Inspect the running Paste app before implementing the corresponding behavior. Use the computer-use skill and tools for local UI inspection.
- Record the installed version, platform, and relevant settings so observations are reproducible.
- Explore every reachable surface: main window, menu bar, menus, context menus, settings, onboarding, dialogs, keyboard shortcuts, and empty, loading, error, and permission states.
- Observe actual interactions using harmless test clipboard content. Capture reference screenshots and notes without exposing the user's private clipboard history.
- Do not clear history, delete pinboards, change account state, purchase anything, or alter sync settings in the reference app without explicit authorization. Restore temporary settings after inspection.
- Treat observed behavior as authoritative. Use official documentation to investigate features that cannot be exercised locally; distinguish documented behavior from verified behavior.
- Do not invent details or silently omit features that are difficult to inspect. Record unknowns and blockers explicitly, then continue independent work.

## Feature inventory

Maintain `docs/paste-parity.md` as the durable checklist. For each feature, record its reference evidence, expected behavior, implementation status, verification steps, and remaining gaps. Use statuses such as `unexplored`, `observed`, `in progress`, `implemented`, `verified`, and `blocked`.

Investigate at least the areas below. These are discovery prompts, not claims about the installed app's capabilities. Expand the inventory whenever another feature is found.

- Clipboard capture, supported content types and formats, metadata, previews, duplicate handling, history limits, and persistence.
- Browsing, search, filtering, sorting, selection, navigation, and detailed previews.
- Pinboards or collections, organization, renaming, reordering, and item management.
- Copying, pasting, plain-text transformations, multi-item operations, drag and drop, and behavior across destination apps.
- Global shortcuts, local shortcuts, menu bar controls, activation, dismissal, window placement, and focus restoration.
- Preferences, excluded apps, sensitive-content handling, retention, pause/resume, and permissions.
- Launch and background behavior, notifications, import/export, account flows, synchronization, and companion-platform features where present.
- Appearance, themes, typography, icons, motion, sound, accessibility, and localization where present.

Features requiring another device, account, entitlement, or service remain in scope. Document the dependency and implement available portions without presenting simulated integrations as working features.

## Fidelity standards

- Reproduce layout, dimensions, spacing, typography, colors, materials, shadows, borders, icons, selection states, and transitions from the reference.
- Match keyboard and pointer behavior, focus rules, scrolling, timing, dismissal, and edge cases as carefully as appearance.
- Compare equivalent states side by side at the same window size, display scale, theme, and content.
- Use realistic fixtures: short and long text, multiline text, URLs, images, files, rich content, duplicates, and large histories as applicable.
- Preserve the reference's information hierarchy and interaction model. Do not substitute generic components or redesign workflows for convenience.
- Implement original code and use assets available for this project. Use the running app as a behavioral and visual reference.

## Engineering standards

- Inspect the repository before choosing architecture. Prefer platform capabilities that support faithful clipboard handling, global shortcuts, window behavior, and accessibility.
- Keep clipboard capture, storage, indexing, presentation, and OS integrations separated enough to test and evolve independently.
- Preserve clipboard formats and content faithfully. Prevent self-capture loops and handle rapid clipboard changes, unsupported formats, large payloads, and unavailable source apps gracefully.
- Make persistence reliable across restarts and upgrades. Keep schema migrations explicit and avoid silent data loss.
- Keep the interface responsive with large histories. Measure capture latency, search latency, memory usage, and scrolling performance using representative data.
- Treat clipboard data as private. Do not log raw clipboard content, commit personal captures, or transmit clipboard data without a user-enabled feature that requires it. Keep credentials out of source control.
- Request OS permissions only when needed, explain their purpose in the product, and handle denial or revocation gracefully.
- No dead controls, fake success states, placeholder integrations, or hardcoded demo content in completed features.

## Implementation workflow

1. Inspect the relevant Paste workflow and update the parity inventory.
2. Define observable acceptance criteria, including keyboard behavior and failure states.
3. Implement a working vertical slice with real capture, storage, and interactions where relevant.
4. Run appropriate automated checks and manually exercise the built app against the same reference workflow.
5. Compare screenshots, resolve visual and behavioral discrepancies, and record verification evidence.
6. Keep the inventory current and proceed to the next gap. Ask focused questions only when missing information materially blocks progress.

Prioritize a dependable capture → history → search → paste loop, then broaden feature coverage and polish. This ordering does not reduce the full-parity scope.

## Completion criteria

A feature is verified only when its real behavior matches the reference, relevant checks pass, and visual states have been compared. Use meaningful tests for persistence, search, clipboard formats, and OS integration boundaries; use hands-on verification for global shortcuts, focus, permissions, and cross-app paste behavior.

Full completion requires every discovered feature to be accounted for, every supported workflow verified, and all remaining differences disclosed. Report what changed, how it was verified, and what remains. Never claim a perfect clone based only on screenshots, compilation, or a passing unit test suite.

<!-- CODEGRAPH_START -->
## CodeGraph

This project has a CodeGraph MCP server (`codegraph_*` tools) configured. CodeGraph is a tree-sitter-parsed knowledge graph of every symbol, edge, and file. Reads are sub-millisecond and return structural information grep cannot.

### When to prefer codegraph over native search

Use codegraph for **structural** questions — what calls what, what would break, where is X defined, what is X's signature. Use native grep/read only for **literal text** queries (string contents, comments, log messages) or after you already have a specific file open.

| Question | Tool |
|---|---|
| "Where is X defined?" / "Find symbol named X" | `codegraph_search` |
| "What calls function Y?" | `codegraph_callers` |
| "What does Y call?" | `codegraph_callees` |
| "What would break if I changed Z?" | `codegraph_impact` |
| "Show me Y's signature / source / docstring" | `codegraph_node` |
| "Give me focused context for a task/area" | `codegraph_context` |
| "See several related symbols' source at once" | `codegraph_explore` |
| "What files exist under path/" | `codegraph_files` |
| "Is the index healthy?" | `codegraph_status` |

### Rules of thumb

- **Answer directly — don't delegate exploration.** For "how does X work" / architecture / trace questions, answer with 2-3 codegraph calls: `codegraph_context` first, then ONE `codegraph_explore` for the source of the symbols it surfaces. Codegraph IS the pre-built index, so spawning a separate file-reading sub-task/agent — or running a grep + read loop — repeats work codegraph already did and costs more for the same answer.
- **Trust codegraph results.** They come from a full AST parse. Do NOT re-verify them with grep — that's slower, less accurate, and wastes context.
- **Don't grep first** when looking up a symbol by name. `codegraph_search` is faster and returns kind + location + signature in one call.
- **Don't chain `codegraph_search` + `codegraph_node`** when you just want context — `codegraph_context` is one call.
- **Don't loop `codegraph_node` over many symbols** — one `codegraph_explore` call returns several symbols' source grouped in a single capped call, while each separate node/Read call re-reads the whole context and costs far more.
- **Index lag**: the file watcher debounces ~500ms behind writes; don't re-query immediately after editing a file in the same turn.

### If `.codegraph/` doesn't exist

The MCP server returns "not initialized." Ask the user: *"I notice this project doesn't have CodeGraph initialized. Want me to run `codegraph init -i` to build the index?"*
<!-- CODEGRAPH_END -->
