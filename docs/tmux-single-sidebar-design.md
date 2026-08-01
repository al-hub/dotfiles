# Single Sidebar Design

## Status

This document describes the approved design for `feature/single-sidebar`.
It is a development contract, not a claim about the current `master`
implementation.

## Goal

Keep one logical sidebar state while giving each managed tmux window one stable
sidebar pane and process. When the client switches sessions, the target pane is
already provisioned and tmux performs only the native `switch-client`; no
physical pane is moved through the visible window.

This is the tmux-native compromise for “one sidebar”: state/ownership are
shared, while physical panes are window-local because tmux cannot display one
pane in two windows simultaneously. Session creation provisions the new
window on a cold hook path and refreshes existing sidebar snapshots.

## Invariants

1. Each managed window has zero or one pane titled `dotfiles-session-sidebar`;
   the logical sidebar state is shared server-wide.
2. The visible sidebar process is not respawned during session switching.
3. A successful session switch preserves the sidebar pane ID.
4. The active client always has a ready local sidebar pane after provisioning.
5. Work layout snapshots exclude the sidebar pane.
6. Split shortcuts always target a work pane.
7. A failed move does not complete the client switch.
8. `master` behavior is unchanged until this branch is explicitly merged.
9. New archives carry version 2 logical pane slot/title and geometry metadata;
   version 1 archives remain readable.
10. A multi-pane session move snapshots the sidebar-inclusive window layout and
    reapplies it after moving the same pane into the target window. A
    single-work-pane move uses the fast path and relies on the delta render
    barrier instead of a topology snapshot.
11. A multi-pane target without compatible sidebar layout metadata rejects the
   move and rolls back instead of accepting a best-effort geometry.
12. Direct tmux split/resize/layout mutations refresh the sidebar-inclusive
   layout snapshot through guarded runtime hooks before a later move or restore.
13. Archive/delete/restore operations own a unique operation token; stale
   asynchronous completion cannot overwrite a newer operation state.
14. Input buffered while an operation is busy is rejected and drained before
   the next TUI action is read.
15. Non-owner client hooks cannot move or claim the sidebar; owner operations
   revalidate session identity, client attachment, and owner client state before
   destructive or client-switch phases.
16. An external conflict fails the operation, preserves externally created
   sessions, removes only matching partial restore state, and restores the owner
   client/sidebar when safe.
17. Version 2 archives include all windows in the session. Restore preserves
   window order/name, pane topology/geometry/focus, and restores one sidebar
   only in the active window.
18. Transition readiness polling is observation-only: it must not issue
   `switch-client` or `select-pane` while waiting for the move to settle.
19. Runtime hooks defer sidebar metadata/focus synchronization while a
   transition is running; window-local switch completion does not synchronously
   snapshot or restore layout.
20. A normal session switch uses sidebar selection/state delta rendering and
   must not clear or fully repaint the sidebar pane; full render is reserved
   for geometry, topology, view-mode, or recovery fallback.

The sidebar owner client is stored in `@dotfiles_sidebar_owner_client`. A
second attached client cannot move or toggle the pane while another client
owns it. The owner is released only by an explicit sidebar off operation.

## State model

```text
ABSENT
  on  -> VISIBLE(session, window)

VISIBLE(session, window)
  off       -> ABSENT
  switch(B) -> VISIBLE(B, target-window)
  delete    -> VISIBLE(fallback) or ABSENT
```

The process-local TUI state remains independent from tmux ownership. The
current owner session and window are always resolved from the stable pane ID;
they are not immutable process startup values.

## Responsibilities

| Component | Responsibility |
| --- | --- |
| command dispatcher | CLI options and tmux bindings |
| sidebar controller | on/off and session-switch state transitions |
| tmux adapter | explicit pane/window/client queries and mutations |
| layout store | save, validate, restore work layouts |
| refresh transport | signal and fallback refresh request |
| TUI state/renderer | selection, session rows, input, and rendering |

Core state transitions must call the adapter boundary rather than embed
unscoped `tmux` commands. Tests can then provide deterministic success and
failure adapters.

## Session switch protocol

1. Resolve the active client and target window by stable IDs.
2. Resolve the current client and its source window.
3. Ensure and verify the target window's ready local sidebar pane.
4. Switch the explicit client to the target session.
5. Mark `STABILIZE`/`READY` after client verification; target pane rendering
   remains local to that pane and is not requested as a whole-window redraw.

If any step before client switching fails, keep the current client session and
report the failure. A move must use stable pane/window IDs, not ambiguous
session or window names.

If the client switch fails, keep the source client and preserve both
window-local sidebar panes; there is no sidebar move rollback.

Archive restore is transactional at the tmux topology boundary: layout and
focus failures remove the partial restored session and switch the owning client
back to its original session. Version 2 archives verify restored pane geometry,
reapply pane titles/logical slots, and reselect the archived active pane. Paths
and command signatures are restore metadata; the original running process,
physical pane ID, and PID are not serialized or required to remain identical.

Window selection invokes the same local-provision protocol through the runtime
hook. Readiness polling does not repair focus or client state; those mutations
belong to the transition protocol. Hook-triggered metadata synchronization is
deferred during switch-client and never performs a synchronous layout snapshot
in the window-local hot path.

## On/off policy

The first implementation retains the current user-visible semantics: `Ctrl+a
s` creates or removes the sidebar and restores the work layout when removing
it. A later optimization may park the pane in a holder window to preserve TUI
state while hidden; that is not part of the first migration.

## Compatibility boundary

The following bindings remain part of the public behavior contract:

- `Ctrl+a s`
- `Ctrl+a |`, `_`, `%`, and `\"`
- `Ctrl+a n`
- pane navigation, mouse selection, session Enter, create, rename, delete,
  and history actions

Window-to-window automatic selection ensures a local sidebar in the active
window and is guarded by the active-client hook; it does not relocate a pane.

## Test contract

The scenario suite must verify:

- one local sidebar per managed window after opening and switching A -> B -> C;
- unchanged per-window sidebar pane ID and process PID across successful session switches;
- on/off idempotence and layout restoration;
- split shortcuts never split the sidebar;
- rapid switching never creates duplicates;
- target deletion and target provisioning failure have safe fallback behavior;
- active-window hooks provision or reuse the local pane without moving another window's pane;
- `d All` removes only sessions marked as sidebar-managed and preserves external sessions;
- current behavior on `master` remains untouched.
- a multi-pane target without a saved sidebar layout fails closed and preserves the source sidebar;
- raw horizontal and vertical split/resize followed by session movement preserves
  work-pane count, sidebar geometry, and the attached PTY sidebar process;
- archive/delete of the current session moves the sidebar to the fallback before
  kill and keeps the TUI available for a subsequent history restore;
- arbitrary topology archive/restore preserves semantic pane slot, title, path,
  geometry, and active focus while allowing new work-pane IDs/PIDs;

Failure injection through `TMUX_SESSION_LAUNCHER_FAIL_STEP` must verify
provisioning, snapshot, restore-layout, focus, and transition rollback without leaving a
duplicate sidebar or an unrecoverable operation state.

Archive/delete/restore stress coverage must verify operation-token ownership,
pending-input rejection, failed archive preservation, and final idle/failed
state after rapid `d`, `o`, navigation, and Enter input.

Multi-client conflict coverage must verify external client attachment, target
session deletion, restore-name collision, and owner session/window changes
without creating a duplicate sidebar or deleting an external session.

The split-cycle reproductions now pass: real PTY horizontal `Ctrl+a |` and
vertical `Ctrl+a _` work splits preserve sidebar geometry and work topology
after switching away and returning. The controller uses the first work pane as
the stable insertion anchor and reapplies the saved full layout. A target with
multiple work panes but no compatible saved sidebar layout fails closed and
rolls back.
