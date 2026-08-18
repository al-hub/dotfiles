# Sidebar timestamp debugging

Debug output is disabled by default. Enable it for a reproduction with:

```sh
TMUX_SESSION_LAUNCHER_DEBUG=1 \
TMUX_SESSION_LAUNCHER_DEBUG_FILE=/tmp/tmux-sidebar-debug.log \
TMUX_SESSION_LAUNCHER_TRACE=1 \
TMUX_SESSION_LAUNCHER_TRACE_FILE=/tmp/tmux-sidebar-trace.log
```

`DEBUG` records coarse lifecycle messages with microsecond timestamps, PID, and
pane ID. `TRACE` records operation, hook, pane, client, and transition events.
Turn both streams off by unsetting the variables or setting them to `0`.

For attached-PTY tests, preserve the failure artifact with:

```sh
KEEP_RUN_DIR=true TMUX_KEYBOARD_E2E_TRANSPORT=script \
TMUX_SESSION_LAUNCHER_TRACE=1 \
TMUX_SESSION_LAUNCHER_TRACE_FILE=/tmp/tmux-sidebar-trace.log \
bash tests/tmux-single-sidebar/test-keyboard-e2e-repeat.sh
```

The test run directory contains the raw PTY input/output, pane layout,
selection state, and client snapshots needed to correlate a sidebar loss with
the hook or operation that preceded it.
