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
| P1 | Split/layout | Direct tmux split/resize commands while sidebar is open are not fully tracked by the single-sidebar layout store. The supported wrapper bindings target a work pane, but arbitrary tmux split commands can leave the saved/restored work layout inconsistent. | `AGENTS.md`, single-sidebar design contract, controller layout ownership | Confirmed design limitation |
| P1 | Session move | Sidebar ownership is tied to the active client target window. Switching session/window can move the single sidebar away from the user's expected visible work area; windows changed directly outside the wrapper are not automatically followed. | Design explicitly scopes relocation to active window and excludes window hooks | User-reported operational risk; targeted manual reproduction still required |
| P1 | Archive/restore | `d` uses asynchronous `tmux run-shell -b` deletion/archive. Immediate `o`, session movement, or focus changes can race with archive completion. | `run_session_delete`, `restore_archive`, `wait_for_sidebar_transition` | Remaining risk: restore critical tmux failures now abort with traceable reason |
| P1 | Restore layout | A sidebar-side split followed by archive/delete and `o` restore can restore work panes but not the exact sidebar/work focus or layout expected by the user. | User report; direct split is outside the tracked layout protocol | Reproduction scenario required |
| P2 | Destructive action | `d All` archives and terminates every session on the tmux server, not only sessions created by the current sidebar workflow. | `delete_all_sessions_after_archive` calls `tmux kill-server` | Intended but dangerous; requires explicit confirmation UX |
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
- A two-run E2E observed one restore-adjacent action-generation timeout; this
  remains a follow-up stability issue and is not treated as master-ready proof.

## Next audit order

1. Verify installer preservation against a live, pre-existing tmux server.
2. Reproduce direct split → `d` → `o` with pane IDs, layouts, focus, and archive timestamps recorded before and after every action.
3. Reproduce session/window movement with both configured wrapper shortcuts and raw tmux commands.
4. Add explicit confirmation and race detection for `d All` and asynchronous archive/restore operations.

Until these items are resolved, this branch remains unsuitable for `master`.
