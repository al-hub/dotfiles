# Live Usage Side-Effect and Bug Audit

## Audit scope

Date: 2026-07-25

Branch: `feature/single-sidebar`

`master` is not used as an acceptance target. The audit uses an isolated HOME,
temporary install state, and a dedicated tmux socket so the user's real files
and tmux server are not modified.

## Priority findings

| Priority | Area | Finding | Evidence | Status |
| --- | --- | --- | --- | --- |
| P0 | Installer | Installing the `tmux` item previously terminated the default tmux server. | `install.sh:after_install_item/cleanup_tmux_runtime` | Fixed: existing server is preserved and restart is user-controlled |
| P1 | `c` prompt | `c` entered `New:` mode but typed session name was not rendered because prompt input used `stty -echo`. | Isolated installed launcher capture | Fixed: modal prompt enables echo |
| P1 | Split/layout | Direct tmux split/resize commands while sidebar is open must update the sidebar-inclusive layout metadata before a later session move/archive/restore. | `test-keyboard-e2e-direct-layout.sh`, layout hook trace | Fixed on this branch: after-command and resize hooks save full layout metadata; sync is guarded and does not enter user operation-busy state |
| P1 | Session move | Sidebar ownership must follow the active client window without duplicating the pane. | Attached-client active-window hook test with pane ID/PID assertion | Fixed for active client window; multi-client behavior remains follow-up |
| P1 | Archive/restore | `d` uses asynchronous `tmux run-shell -b` deletion/archive. Immediate `o`, session movement, or focus changes can race with archive completion. | `test-keyboard-e2e-rapid-operations.sh`, operation trace | Fixed for buffered keyboard input on this branch: unique operation ownership, pending-input drain, stale completion protection, and archive-failure preservation; external concurrent tmux clients remain follow-up |
| P1 | Restore layout | A sidebar-side split followed by session movement can restore work panes but not the exact sidebar/work focus or layout expected by the user. | Horizontal/vertical PTY split-cycle tests | Fixed for tracked wrapper topology; metadata-missing multi-pane targets fail closed |
| P2 | Destructive action | `d All` must not terminate unrelated tmux sessions. | Managed-session contract test | Fixed: only `@dotfiles_sidebar_managed` sessions are removed |
| P2 | Installer/X | With `DISPLAY` set but no usable X server, installation previously invoked `xrdb -merge` and emitted an X connection error. | Isolated install with `DISPLAY=:0` | Fixed: `xrdb -query` must succeed first |
| P2 | Installer/network | If `opencode` is not already available, `install.sh` previously ran the external OpenCode installer even for local `file://` installs. | `install_opencode_cli` | Fixed: remote CLI installation is opt-in |

## User-reported scenarios to preserve

These scenarios must remain in the audit suite until individually explained:

1. Start from an already-used tmux server and run the install command.
2. Press `c`, type a new session name, and verify the characters are visible before Enter.
3. Split a work pane to the right of the sidebar.
4. Delete/archive the selected session with `d`.
5. Enter history with `o` and restore the same session.
6. Move between sessions with Down/Enter repeatedly.
7. Verify the sidebar remains visible, focused, unique, and attached to the expected window after every move.

## What is currently proven safe

The automated PTY scenario proves the following on this branch when using the
configured sidebar bindings and explicit target sessions:

- one sidebar pane remains globally unique;
- `keyboard-1` through `keyboard-6` can be selected;
- archive/delete and restore complete;
- `d All` terminates the isolated tmux server;
- numeric session `0` no longer causes duplicate sidebar discovery;
- the legacy E2E transport failure was caused by an unconsumed test stdout pipe and is fixed in the harness.

These results do not prove that arbitrary user-created splits, multiple windows,
pre-existing sessions, or live installation are side-effect free.

## 2026-07-25 implementation status

- Installer tmux-server preservation, X display probing, and OpenCode CLI opt-in
  changes are implemented on `feature/single-sidebar`.
- The modal prompt visibly echoes typed names, and the PTY E2E asserts this with
  `capture-pane`.
- Restore critical tmux failures now produce `restore.abort` trace events instead
  of being silently ignored.
- Single-sidebar contract and one complete keyboard E2E pass.
- Earlier two-run E2E observed one restore-adjacent action-generation timeout;
  the operation guard and prompt-state test were strengthened afterward.
- The current repeated keyboard E2E and direct-layout PTY E2E are PASS; raw
  direct split/resize is now covered separately from the wrapper shortcut path.
- Runtime active-window hooks now move the existing sidebar pane and preserve
  pane ID/PID; a dedicated attached-client test passes.
- `d All` now targets sessions marked `@dotfiles_sidebar_managed` and preserves
  external sessions; a dedicated contract test passes.
- Operation state is exposed through `@dotfiles_sidebar_operation` and input is
  rejected while save/delete/restore/move is in progress.
- The sidebar owner client is recorded in `@dotfiles_sidebar_owner_client`, and
  injected move failure preserves the source pane/window in a dedicated test.
- Raw split archive smoke coverage now records a non-empty work-layout snapshot;
  version 2 now records pane IDs, geometry, active state, and window geometry;
  restore verifies geometry and active-pane focus. Exact arbitrary-topology
  identity remains a follow-up acceptance item.
- Archive output is now validated before rename, uses a process-unique filename,
  and bulk archive failure prevents managed session deletion. Restore imports
  shell history only after topology/client/sidebar success and records an
  archive marker to avoid duplicate imports.
- A two-client PTY test confirms that a non-owner client cannot toggle the
  shared sidebar.
- Stale owner client metadata is cleared before a new sidebar owner is claimed.
- Failure injection covers snapshot, move, client-switch, restore-layout,
  sidebar-focus, and transition rollback boundaries.
- Async archive/delete/restore now use unique operation IDs. Workers verify
  ownership before finalizing state; pending PTY input is drained after a busy
  operation and logged as rejected.

## Next audit order

1. Verify installer preservation against a live, pre-existing tmux server.
2. Reproduce direct split → `d` → `o` with pane IDs, layouts, focus, and archive timestamps recorded before and after every action. The direct split/resize hook path is now implemented; arbitrary pane identity restoration remains a follow-up topology test.
3. Repeat active-window and rapid restore E2E at least three consecutive times.
4. Exercise version 2 archives against more arbitrary pane topologies and add
   an end-to-end legacy version 1 archive fixture.

## 2026-07-25 split-cycle reproduction

The real-PTY acceptance test is `tests/tmux-single-sidebar/test-keyboard-e2e-split-cycle.sh`.
It performs the user sequence:

1. Open/focus the sidebar and create `split-cycle-1` through `split-cycle-3`.
2. Select `split-cycle-1` and press `Ctrl+a |` to create the configured
   horizontal work split.
3. Return focus to the sidebar with the standard tmux `Ctrl+a o` pane rotation.
4. Select `split-cycle-2`, then return to `split-cycle-1`.
5. Compare sidebar count/width, work-pane count, and window layout before and
   after the round trip.

Current result is PASS after full-layout restore was added:

```text
PASS: split-cycle preserved horizontal work split and sidebar geometry
```

The fix snapshots the sidebar-inclusive source layout before moving, uses the
first work pane as a stable insertion anchor, and reapplies the saved layout
after the move using the target pane order. Pane IDs, geometry, and active focus
are verified before the session switch completes.

The vertical variant is `tests/tmux-single-sidebar/test-keyboard-e2e-split-cycle-vertical.sh`.
It uses `Ctrl+a _` and also passes:

```text
PASS: split-cycle preserved vertical work split and sidebar geometry
```

The controller now preserves the full-height sidebar placement beside the
stacked work panes. If a multi-pane target has no compatible saved sidebar
layout metadata, the move fails closed and rolls back.

## 2026-07-25 direct split/resize reproduction

`tests/tmux-single-sidebar/test-keyboard-e2e-direct-layout.sh` runs the same
attached-PTY session creation, navigation, and session round-trip while the
work pane is changed through raw tmux `split-window` and `resize-pane` commands.
Both directions are covered:

```text
PASS: split-cycle preserved horizontal work split and sidebar geometry
PASS: split-cycle preserved vertical work split and sidebar geometry
```

The runtime installs `after-split-window`, `after-resize-pane`, layout/pane
mutation hooks, `window-resized`, and `window-pane-changed`. Layout sync writes
only the sidebar-inclusive snapshot and uses a short global re-entry guard; it
does not mark the user-facing archive/move operation busy. This prevents a raw
split from disabling the sidebar TUI while preserving the metadata needed by a
later session move.

Until these items are resolved, this branch remains unsuitable for `master`.

## 2026-07-25 rapid archive/restore reproduction

`tests/tmux-single-sidebar/test-keyboard-e2e-rapid-operations.sh` injects a
0.4-second test-only operation delay and sends keyboard input while delete and
restore are still busy. It repeats the delete/navigation and restore/navigation
flows three times.

```text
PASS: rapid d→o/session navigation input is rejected during delete (3 iterations)
PASS: rapid restore→navigation input is rejected during restore (3 iterations)
```

The trace records `operation.begin`, worker PID/id, `input.rejected`, ownership
mismatch, and final completion/failure. A failed single-session archive now
leaves the session intact instead of deleting it after an unsuccessful archive.
