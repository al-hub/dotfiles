# Window-local sidebar test plan

## Purpose

This document defines the tmux-native window-local sidebar contract on
`feature/single-sidebar`. The production path provisions one sidebar per
physical managed window and performs native client switching.

The tests use two observation boundaries:

- fast tmux contract tests for pane ownership, lifecycle, archive shape, and
  linked-window uniqueness;
- attached-PTY tests for the exact user path: prefix, `s`, `c`, arrows, Enter,
  split shortcuts, `d`, and `o`.

## Required invariants

For `@dotfiles_sidebar_enabled=1`, every unique managed `window_id` has exactly
one `dotfiles-session-sidebar` pane. A linked window is counted once because
tmux shares the physical window and its panes.

Normal session switching must perform only an explicit client-targeted
`switch-client`. It must not call `move-pane`, `join-pane`, `select-layout`,
layout restore, readiness mutation, or `render_full`.

The target sidebar must already exist and be input-ready before the client is
switched. The sidebar pane ID, PID, geometry, and the work-pane topology of
each window must remain stable across session switching.

## Test entrypoints

| Test | Boundary | Expected current result |
| --- | --- | --- |
| `test-window-local-contract.sh` | isolated tmux | PASS |
| `test-keyboard-e2e-window-local-switch.sh` | attached PTY | PASS |
| `test-keyboard-e2e-window-local-toggle.sh` | attached PTY | PASS |
| `test-window-local-lifecycle-contract.sh` | isolated tmux | PASS |
| `test-window-local-multi-client.sh` | isolated tmux | PASS |
| `test-keyboard-e2e-window-local-lifecycle.sh` | attached PTY | lifecycle scenario; run separately |

The older numeric-session and layout-metadata tests still encode the retired
global `move-pane` rollback contract. They are not failures of native switch;
replacement coverage is provided by the window-local contracts above.

## Measurements

Each attached-PTY switch records input time, `switch-client` time, target
sidebar readiness, stable frame time, pane geometry, work topology, and raw
trace lines. The migration is accepted only when:

- key-to-stable-frame p95 is at most 500ms;
- `move-pane`, `join-pane`, and `select-layout` count is zero during switch;
- `render_full` count is zero during normal switch;
- blank or partial frames are zero;
- sidebar geometry and work topology mismatches are zero;
- target sidebar readiness precedes client session change.

Failed tests preserve the run directory with pane, client, trace, debug, and
PTY artifacts. No test changes production files or the user's live tmux
server.

## Scope boundary

The tests do not require client-specific sidebar content for a linked window.
When multiple sessions link the same tmux window, the physical sidebar pane is
shared according to tmux semantics. Client-specific session switching remains
explicit through each client tty.
