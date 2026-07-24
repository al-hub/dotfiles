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
| P0 | Installer | Installing the `tmux` item unconditionally calls `tmux kill-server` on the default socket. A running user's tmux server can be terminated during install. | `install.sh:after_install_item/cleanup_tmux_runtime` | Confirmed by code; must be fixed or explicitly guarded before real installation |
| P1 | `c` prompt | `c` enters `New:` mode but typed session name is not rendered because prompt input uses `stty -echo`. The session is created, but the user receives no visible input feedback. | Isolated installed launcher capture: after `c`, and after typing `demo-session` before Enter, the pane still showed only `New:` | Reproduced |
| P1 | Split/layout | Direct tmux split/resize commands while sidebar is open are not fully tracked by the single-sidebar layout store. The supported wrapper bindings target a work pane, but arbitrary tmux split commands can leave the saved/restored work layout inconsistent. | `AGENTS.md`, single-sidebar design contract, controller layout ownership | Confirmed design limitation |
| P1 | Session move | Sidebar ownership is tied to the active client target window. Switching session/window can move the single sidebar away from the user's expected visible work area; windows changed directly outside the wrapper are not automatically followed. | Design explicitly scopes relocation to active window and excludes window hooks | User-reported operational risk; targeted manual reproduction still required |
| P1 | Archive/restore | `d` uses asynchronous `tmux run-shell -b` deletion/archive. Immediate `o`, session movement, or focus changes can race with archive completion. Restore also tolerates several tmux failures with `|| true`, which can leave a restored session without the expected sidebar/client state. | `run_session_delete`, `restore_archive`, `wait_for_sidebar_transition` | User-reported and code-supported risk; needs deterministic manual reproduction |
| P1 | Restore layout | A sidebar-side split followed by archive/delete and `o` restore can restore work panes but not the exact sidebar/work focus or layout expected by the user. | User report; direct split is outside the tracked layout protocol | Reproduction scenario required |
| P2 | Destructive action | `d All` archives and terminates every session on the tmux server, not only sessions created by the current sidebar workflow. | `delete_all_sessions_after_archive` calls `tmux kill-server` | Intended but dangerous; requires explicit confirmation UX |
| P2 | Installer/X | With `DISPLAY` set but no usable X server, installation invokes `xrdb -merge` and emits an X connection error. Installation continues, but the result is noisy and can be misleading. | Isolated install with `DISPLAY=:0` | Reproduced as non-fatal warning |
| P2 | Installer/network | If `opencode` is not already available, `install.sh` runs the external OpenCode installer even when repository files are supplied through `file://`. | `install_opencode_cli` | Confirmed code behavior; scope should be explicit before real install |

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

## Next audit order

1. Add an installer guard that refuses to kill an attached/default tmux server and verify installation against a live server.
2. Make prompt input visibly echo the session name and test cancellation/long names.
3. Reproduce direct split → `d` → `o` with pane IDs, layouts, focus, and archive timestamps recorded before and after every action.
4. Reproduce session/window movement with both configured wrapper shortcuts and raw tmux commands.
5. Add explicit confirmation and race detection for `d All` and asynchronous archive/restore operations.

Until these items are resolved, this branch remains unsuitable for `master`.
