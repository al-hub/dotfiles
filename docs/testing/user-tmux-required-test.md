# User tmux required live suite

Run the required live suite against the currently attached user tmux client:

```sh
bash tests/tmux-single-sidebar/test-user-tmux-required-monitored.sh
```

The runner creates a temporary visible window in the user's current session,
opens the sidebar with the installed launcher, and exercises session creation,
arrow/Enter switching, horizontal and vertical work-pane topology, captures,
and trace/debug error scanning. It never creates a nested tmux or a second
attached client.

`Ctrl+a` prefix handling is intentionally separate: use the attached-PTY
keyboard suite with a real byte delay between `Ctrl+a` and `s`. `tmux
send-keys` targets a pane and does not exercise the tmux client key table.

Artifacts are kept under `/tmp/dotfiles-user-live-*`:

- `events.log`: wall-clock and monotonic millisecond events with run/input IDs
- `results.tsv`: per-create and per-switch latency and result
- `capture-*.log`: ANSI-aware sidebar snapshots
- `layout-*.tsv`: pane geometry and identity observations
- `clients-*.tsv`, `panes-*.tsv`: failure and cleanup state snapshots
- `trace.log`, `debug.log`, `error-matches.log`: launcher diagnostics
- `session-switch-manifest.tsv`: 전환별 source/target/actual session, operation ID,
  transition phase, first target/READY time, sidebar identity, duration,
  failure class, result
- `transition-samples.tsv`: Enter 직후부터 안정화 또는 timeout까지 25ms 관측
  경계의 client session, sidebar pane/PID/geometry, pane topology, trace line
  및 raw output offset, 실제 sample interval, full render/hook count.
  focused correlation과 user default runner 모두 생성합니다.
- `transition-events.tsv`: 입력, transition begin, 안정화 종료 또는 실패를
  operation ID와 연결한 테스트 event timeline
- `failure-*`: 첫 실패 시점의 client/pane/options/sidebar/raw client/trace/debug
  snapshot

The runner uses a 1 second session-create and 500ms session-switch contract.
It always removes test sessions/window/sidebar panes and restores the original
client/window/options, including after a failure.

For marker validation, each stabilized target capture must contain exactly one
current marker (`*` or `>*`) and exactly one selection marker (`>` or `>*`).
`>*` is one capture token, not two whitespace-separated tokens. The target
session must be both the observed client session and the selected row. A
normal transition must have zero non-geometry `render.full.begin` events for
the target sidebar; geometry-invalidated full renders are recorded separately.
The production transition also records `selection.sync.barrier`; a normal
transition must reach `result=ack` before `switch.end`, so the target current
marker cannot become visible before the selected marker is reconciled.

## Correlation boundary

The manifest treats a switch as successful only when the user-facing client
session reaches the target and the launcher operation reaches `READY`. A
controller-side `transition.finish result=success` is not sufficient by itself.
On a failed switch, the runner preserves the first failure snapshot and records
the actual client session and sidebar state before cleanup.

The focused correlation runner also classifies failures as `TARGET_NOT_REACHED`,
`CLIENT_REVERTED`, `SIDEBAR_DISAPPEARED`, or `PASS`. A sidebar gap is retained
as a failure even when the client eventually reaches the target, so an internal
`READY` event cannot hide an intermediate redraw/lifecycle discontinuity.

The isolated counterpart is:

```sh
TMUX_INTERACTIVE_RUN_DIR=/tmp/dotfiles-live-session-switch-correlation-run \
TMUX_INTERACTIVE_SOCKET=dotfiles-live-session-switch-correlation-run \
bash tests/tmux-single-sidebar/test-session-switch-live-correlation.sh
```

It sends keyboard bytes through an attached PTY, performs ten round-trip
switches, and stops at the first failure. User and isolated artifacts can be
compared by `operation_id`, phase list, client session, sidebar pane identity,
and transition duration.

The focused correlation observer records the target window's sidebar pane before
Enter. During a switch, passing through the source pane is expected and is not an
identity failure; identity is checked only after the target is first observed.
Full-render counts are scoped to the target pane and exclude renders preceded by
`geometry-invalidated`, `topology-invalidated`, or `external-layout-change`.
The scenario checks the marker invariant immediately before Enter and uses a
bounded stabilization loop so an observer defect cannot hang the suite.

Topology variants use the same live observer and prepare the target session
before the first switch:

```sh
TMUX_INTERACTIVE_RUN_DIR=/tmp/dotfiles-live-session-switch-horizontal \
TMUX_INTERACTIVE_SOCKET=dotfiles-live-session-switch-horizontal \
bash tests/tmux-single-sidebar/test-session-switch-live-correlation-horizontal.sh

TMUX_INTERACTIVE_RUN_DIR=/tmp/dotfiles-live-session-switch-vertical \
TMUX_INTERACTIVE_SOCKET=dotfiles-live-session-switch-vertical \
bash tests/tmux-single-sidebar/test-session-switch-live-correlation-vertical.sh
```

Each variant writes `topology.tsv` before switching and keeps the same
sidebar-gap, identity, geometry, redraw, and observer-quality gates.

The user runner uses a fast client/window observation boundary and records the
actual interval. A default tmux server must be running for this measurement;
the runner does not create one implicitly.

## 2026-07-30 observation

The user-server run reproduced the production symptoms: session creation was
811ms, 3.32s, and 10.79s across three iterations; six switch attempts were
either over 500ms or did not change the target session. The final tmux state
returned to one original session/window/pane. No known error string appeared
in trace/debug, so raw attached-PTY collection remains required before
declaring the absence of `returned 1` messages.
