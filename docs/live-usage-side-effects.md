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
| P1 | Session move | Sidebar ownership must follow the active client window without duplicating the pane. | Attached-client active-window and multi-client conflict tests | Fixed for owner client; non-owner hooks are observation-only and external owner-operation conflicts fail closed |
| P1 | Archive/restore | `d` uses asynchronous `tmux run-shell -b` deletion/archive. External client changes can race with archive completion or restore client switching. | `test-multi-client-operation-conflict.sh`, operation trace | Fixed for detected external attachment/deletion/name-collision changes: operation fails closed, external sessions are preserved, and matching partial restore is rolled back |
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

## Current practical-scenario status matrix

This matrix evaluates only behavior that is meaningful and technically
available within tmux. A capability that requires tmux to preserve a process
after its session has been killed is explicitly excluded from the unresolved
bug list.

| Status | Area | Result and evidence |
| --- | --- | --- |
| Fixed | `c` prompt | Typed session name is visible before Enter; attached-PTY E2E PASS |
| Fixed | Numeric session `0` | Session selection no longer fails; numeric regression PASS |
| Fixed | Single sidebar | Session/window movement keeps one sidebar pane and process |
| Fixed | Split/layout | Wrapper and raw horizontal/vertical split geometry survives movement |
| Fixed | Current-session delete | Sidebar moves to fallback before target kill; TUI remains alive |
| Fixed | Delete → history restore | Real `d` → `o` → Enter flow restores the selected session |
| Fixed | Arbitrary topology | Non-linear four-pane topology restores logical slot/title/path/layout/focus |
| Fixed | Archive safety | Failed archive preserves the source session; archive is validated atomically |
| Fixed | Rapid input | Busy operation rejects/drains pending navigation and restore input |
| Fixed | `d All` scope | Only `@dotfiles_sidebar_managed` sessions are deleted |
| Fixed | External clients | Attach, target deletion, and restore name collision fail closed and preserve external sessions |
| Fixed | Failure rollback | Move, snapshot, layout, focus, and transition failure injection preserves safe state |
| Fixed | Archive compatibility | v1 archives remain readable; v2 stores logical pane metadata |
| Fixed | Installer side effects | Existing tmux server, invalid X display, and local OpenCode install paths are guarded |
| Excluded | Physical pane ID/PID continuity | Not a tmux archive capability after session/process termination; restore creates new panes and shells |
| Excluded | Running process/runtime continuation | Original process environment, scrollback, and in-progress CLI state are not serializable through tmux archive |
| Fixed | Multi-window topology | Attached-PTY two-window/four-pane-per-window archive/delete/restore preserves window order/name, geometry, active metadata, and one active-window sidebar |
| Pending verification | Live installer preservation | Existing user tmux server needs final install/update acceptance, beyond isolated sockets |
| Performance pending | External key latency | 40ms goal remains unmet at the tmux/PTY observation boundary; launcher internal target passes |

The remaining practical work is therefore limited to live pre-existing-server
installation acceptance and external key latency investigation.

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
- Non-owner `client-session-changed`/window hooks now record
  `external.client-change` without moving the shared sidebar. Archive/delete/
  restore revalidate session identity, client set, and owner tty/session/window
  before destructive or client-switch phases.

## Next audit order

1. Verify installer preservation against a live, pre-existing tmux server.
2. Exercise version 2 archives against multi-window and more arbitrary pane
   topologies, and add an end-to-end legacy version 1 archive fixture.
3. Measure external key latency separately from launcher internal latency and
   tmux/PTY observer settlement.

## 2026-07-26 arbitrary pane topology acceptance

The reproduction is `tests/tmux-single-sidebar/test-keyboard-e2e-arbitrary-topology.sh`.
It uses the attached PTY and performs the user sequence:

1. Create three sessions with `c`.
2. Select `topology-1` from the sidebar.
3. Create a four-pane non-linear work tree with `Ctrl+a |`, `Ctrl+a _`, and
   `Ctrl+a |`, returning to the sidebar with `Ctrl+a o` after each split.
4. Move to `topology-2` and back to `topology-1`.
5. Archive/delete with `d`, then enter history with `o` and restore with Enter.
6. Compare work-pane count, logical slot/title, geometry, commands, paths, and
   active focus; record pane IDs/PIDs as diagnostic values.

Observed result: PASS. The current-session delete path moves the shared sidebar
to the fallback session before killing the target, and the real `o` + Enter
history path restores the four-pane topology. Logical slot/title/path mapping,
pane count, geometry, and active focus are preserved. Physical pane IDs and
PIDs change as expected because restore creates new panes and shells; they are
diagnostic values, not semantic restore requirements.

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

## 2026-07-26 multi-window topology archive/restore implementation

tests/tmux-single-sidebar/test-keyboard-e2e-multi-window-topology.sh는
실사용 입력과 같은 attached PTY로 다음을 구성한다.

1. 하나의 session에 두 window를 생성한다.
2. 각 window에 서로 다른 가로·세로·quote split 조합으로 4개 work pane을 만든다.
3. Ctrl+a Tab 및 Ctrl+a Shift-Tab으로 window를 이동한다.
4. sidebar에서 peer session으로 이동했다가 target으로 돌아온다.
5. d로 archive/delete한 뒤 o와 Enter로 restore한다.

검증 메타데이터는 physical pane ID/PID가 아니라 window index/name과 pane
slot/title/path/command/geometry/active 상태를 비교한다. archive 파일에
window 2개, endwindow 2개, pane 8개가 기록되는지도 확인한다.

구현 후 결과:

`
PASS: multi-window topology and active-window sidebar metadata preserved
`

archive는 session 전체 window를 저장하고, restore는 새 pane ID를 기존
semantic pane 순서에 매핑한다. active window에는 기존 sidebar-inclusive
layout을 재적용하고 inactive window에는 sidebar를 생성하지 않는다.

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

## 2026-07-25 multi-client operation conflict reproduction

`tests/tmux-single-sidebar/test-multi-client-operation-conflict.sh` runs on a
dedicated tmux socket with an owner attached client and an external client. It
deliberately changes the topology during delayed operations:

```text
PASS: external client attach during delete causes conflict and preserves target
PASS: external target deletion is detected without follow-up kill
PASS: restore name collision preserves externally created session
PASS: conflict trace contains operation identity and reason
```

The owner fingerprint intentionally excludes the active pane id because moving
the shared sidebar can legitimately change that pane. It includes owner tty,
session, and window; session identity and client attachment sets are checked
separately for the operation target.
