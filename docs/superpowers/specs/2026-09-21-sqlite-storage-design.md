# SQLite history storage — design

Status: approved in conversation on September 21, 2026 ("can we do sqlite?" → "ok make a plan for it").

## Problem

History is saved as one binary property list, `~/Library/Application Support/Elmers/history.plist`. On the
user's Mac it is 53 MB. `AppModel.persist()` encodes and rewrites the whole file after every change: each
capture, pin, rename, deletion, OCR result and link preview. Measured on a synthetic history of 2,000 items
(one in ten a 250 KB image, 57 MB total), a full save takes about 150–180 ms of disk and CPU work per change.
The file format cannot do better, because it has no way to write one item.

## Decision

Store history in SQLite, using the library that ships with macOS (`import SQLite3`) through a small internal
wrapper. No package dependencies are added. SwiftData and Core Data are not used because they hide the
migration steps and make it harder to control the stored bytes exactly.

## Scope of this change (stage 1)

- Saves write only what changed. `HistoryStore.save(_:)` compares the history with what it last wrote, then
  writes the changed item rows, pins and pinboards in one transaction. Payload bytes are written only when an
  item's fingerprint changes.
- The file layout is private and safe: `history.sqlite` plus its `-wal` and `-shm` files, all mode 0600, in a
  0700 directory. It uses write-ahead logging (WAL).
- The schema is versioned through `PRAGMA user_version`, with an explicit list of migration steps. A database
  from a newer version is rejected and left untouched, as `Archive` rejects a newer plist today.
- A damaged database is never modified or replaced. It fails the version or integrity check, the app shows
  its existing "History could not be opened" state, and editing stays disabled (`archiveReadable == false`).
- The existing plist is converted once. The store writes it into a staging database, reads it back, compares
  every item and pinboard for exact equality, then moves the staging file into place. Only after that does it
  rename the plist to `history.plist.migrated`. The plist is never deleted. An unreadable plist, or a
  conversion that does not match, leaves every file as it was.
- `History`, `ClipboardItem` and every `AppModel` call site keep their current shape. Only `persist()` and
  launch-time loading change.

## Explicitly not in stage 1 (follow-up plan)

- Loading metadata only, and reading payload bytes on demand. The whole history, images included, is still
  held in memory, as it is today. The schema supports lazy loading because payloads live in their own
  `representations` table.
- Full-text search (FTS5). Search still scans in memory.
- Raising the 2,000-item and 32 MB-per-capture limits. Those depend on lazy loading.

These three items together are "stage 2". They need `ClipboardItem` to carry metadata without its payload,
which touches copy, drag, preview, thumbnails, OCR and duplicate merging. They get their own design.

## Known trade-offs

- An older Elmers build run after conversion finds no `history.plist` and starts with an empty history. The
  converted archive stays available as `history.plist.migrated`.
- If `history.plist` reappears after conversion (for example, written by an older build), it is renamed to
  `.migrated` only when no `.migrated` file exists yet. Its contents are not merged.
- Items copied at exactly the same instant are ordered by insertion (newest insertion first), which matches
  `History.capture`.
