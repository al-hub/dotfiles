# Single Sidebar Design

## Status

This document describes the approved design for `feature/single-sidebar`.
It is a development contract, not a claim about the current `master`
implementation.

## Goal

Keep one sidebar pane and one sidebar process for the active tmux client.
When the client switches sessions, move the existing pane to the target
session's active window instead of creating or respawning another sidebar.

The implementation keeps the sidebar for the active client window. Runtime
`client-session-changed` and `after-select-window` hooks move the existing pane
to the newly active window while preserving its pane ID and process.

## Invariants

1. The server has zero or one pane titled `dotfiles-session-sidebar`.
2. The visible sidebar process is not respawned during session switching.
3. A successful session switch preserves the sidebar pane ID.
4. The sidebar is attached to the active client's target session and window.
5. Work layout snapshots exclude the sidebar pane.
6. Split shortcuts always target a work pane.
7. A failed move does not complete the client switch.
8. `master` behavior is unchanged until this branch is explicitly merged.
9. New archives carry version 2 pane identity and geometry metadata; version 1
   archives remain readable.
10. A session move snapshots the sidebar-inclusive window layout and reapplies
    it after moving the same pane into the target window.
11. A multi-pane target without compatible sidebar layout metadata rejects the
   move and rolls back instead of accepting a best-effort geometry.
12. Direct tmux split/resize/layout mutations refresh the sidebar-inclusive
   layout snapshot through guarded runtime hooks before a later move or restore.

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

1. Resolve the sidebar pane by pane ID/title.
2. Resolve the current client and its source window.
3. Save the source work layout.
4. Resolve the target session's active window and a work pane.
5. Validate that the target window has a usable work pane and save its
   work-only layout as the target baseline.
6. Move the existing sidebar pane to the target window.
7. Apply the sidebar width without replacing the target work layout.
8. Switch the explicit client to the target session.
9. Refresh the surviving TUI process.

If any step before client switching fails, keep the current client session and
report the failure. A move must use stable pane/window IDs, not ambiguous
session or window names.

If the client switch itself fails after the pane move, move the sidebar back to
the source window and restore the source work layout before reporting failure.

Archive restore is transactional at the tmux topology boundary: layout and
focus failures remove the partial restored session and switch the owning client
back to its original session. Version 2 archives verify restored pane geometry
and reselect the archived active pane. Paths and commands are restore inputs;
the original running process state is not serialized.

Window selection invokes the same move protocol through the runtime hook. A
hook guard prevents recursive move events while the pane is being relocated.

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

Window-to-window automatic relocation uses the same controller path as
session-to-session movement and is guarded by the active-client hook.

## Test contract

The scenario suite must verify:

- one global sidebar after opening and switching A -> B -> C;
- unchanged pane ID and process PID across successful switches;
- on/off idempotence and layout restoration;
- split shortcuts never split the sidebar;
- rapid switching never creates duplicates;
- target deletion and move failure have safe fallback behavior;
- active-window hooks move the same pane to a selected window;
- `d All` removes only sessions marked as sidebar-managed and preserves external sessions;
- current behavior on `master` remains untouched.
- a multi-pane target without a saved sidebar layout fails closed and preserves the source sidebar;
- raw horizontal and vertical split/resize followed by session movement preserves
  work-pane count, sidebar geometry, and the attached PTY sidebar process;

Failure injection through `TMUX_SESSION_LAUNCHER_FAIL_STEP` must verify move,
snapshot, restore-layout, focus, and transition rollback without leaving a
duplicate sidebar or an unrecoverable operation state.

The split-cycle reproductions now pass: real PTY horizontal `Ctrl+a |` and
vertical `Ctrl+a _` work splits preserve sidebar geometry and work topology
after switching away and returning. The controller uses the first work pane as
the stable insertion anchor and reapplies the saved full layout. A target with
multiple work panes but no compatible saved sidebar layout fails closed and
rolls back.
