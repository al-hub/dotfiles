# Full live-compatible keyboard test

`tests/tmux-single-sidebar/test-live-full-monitored.sh` runs the complete
attached-PTY keyboard workflow without attaching a nested tmux to the user's
server.

It creates a private tmux socket and run directory, invokes
`test-keyboard-e2e.sh` with `SCENARIO=full`, and monitors `client.log` and
`trace.log` while the test is running. Raw PTY messages are ANSI-normalized
and matching `--ensure-sidebar-window ... returned 1` or `session switch
failed` events are written with monitor timestamps and byte offsets.

Example:

```sh
TMUX_KEYBOARD_E2E_SYSCALL_TRACE=0 \
  bash tests/tmux-single-sidebar/test-live-full-monitored.sh
```

The runner keeps artifacts under `/tmp/dotfiles-live-full-*` and kills only
the private test server on exit, including failure and interruption paths.
It does not alter the currently attached user tmux server.

The 2026-07-30 run reached these results:

- PASS: sidebar toggle, six keyboard-created sessions, six session switches,
  and archive/delete of six sessions.
- FAIL: restore flow timed out while waiting for action-generation progress.
- FAIL/observed: raw PTY captured 81 occurrences of the empty-target
  `--ensure-sidebar-window ' returned 1` message.
- Cleanup: private socket was gone; the user's default tmux remained attached
  with one session and one window.

The raw message count is an observation, not a count of hook invocations: a
status/message redraw can repeat the same bytes in the PTY stream.

## User-server comparison

Running the same full runner against the user's `default` socket did not
enter the workflow. The existing server has
`@dotfiles_sidebar_owner_client=/dev/pts/0`; the runner's additional attached
PTY was `/dev/pts/6`, so the owner guard prevented it from becoming the
sidebar controller and `sidebar input readiness` timed out.

This is a real environment difference, not a passing result. An exact
user-visible test must send input through the already-owned `/dev/pts/0`
client (or explicitly test owner handoff), rather than attach a second client.
