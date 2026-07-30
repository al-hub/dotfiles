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

The runner uses a 1 second session-create and 500ms session-switch contract.
It always removes test sessions/window/sidebar panes and restores the original
client/window/options, including after a failure.

## 2026-07-30 observation

The user-server run reproduced the production symptoms: session creation was
811ms, 3.32s, and 10.79s across three iterations; six switch attempts were
either over 500ms or did not change the target session. The final tmux state
returned to one original session/window/pane. No known error string appeared
in trace/debug, so raw attached-PTY collection remains required before
declaring the absence of `returned 1` messages.
