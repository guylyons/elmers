# Paste Stack

User authorization: continue until full Paste parity. Reference: official Using Paste Stack help; installed 6.3.11 remains behind Accessibility prompt on September 15.

Use a separate in-memory FIFO queue of captured item snapshots. Preserve repeated copies as separate queue entries, independent of history deduplication. A nonactivating floating panel shows queue order and offers reverse, remove, close. Closing stops stack capture and releases Command-V. Retain pending items for reopening; verify this lifecycle against the reference once accessible.

Register Shift-Command-C separately from history activation. Register Command-V only while Stack is active, nonempty, and Accessibility is trusted. On invocation, poll pending clipboard changes, write the next entry, and dispatch Command-V to the current external app. Remove only after dispatch succeeds; invalid target or clipboard write failure retains the entry. Synthetic delivery targets the external process directly to avoid global shortcut recursion. Self-written clipboard generations never enter history or Stack again. Conflicts remain visible.

Tests: FIFO including duplicates, reversal/removal, failure retention; real isolated pasteboard delivery and target-app verification after permissions. Do not claim live parity from queue tests alone.
