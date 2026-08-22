# Live Session Switch Regression

## Reproduction

The live tmux server reproduced `session switch failed: active sidebar client is unavailable` when a session named `0` existed alongside the attached session.

Observed live state:

- attached client: `aaaaaaaaaaaaaaaaaaa`
- sidebar pane: `%18`
- work pane: `%2`
- sessions: `0`, `aaaaaaaaaaaaaaaaaaa`, `bbbbbbbbbbbbbbbbbb`, and others

Sending `Down` then `Enter` to the live sidebar left the client attached to the original session and removed the sidebar pane.

## Cause

`tmux-sidebar-tmux-adapter` enumerated each session with:

```sh
tmux list-panes -s -t "=$session_name"
```

For the live session set, the query for `=0` returned the sidebar pane belonging to `aaaaaaaaaaaaaaaaaaa`, and the query for `=aaaaaaaaaaaaaaaaaaa` returned it again. The global discovery result therefore contained `%18` twice.

The launcher then passed the multi-line pane result into owner/client resolution. `sidebar_tmux_client_tty_for_session` could not resolve a valid owner/client pair, so `switch_session` aborted with `sidebar-client-unavailable`.

## Test gap

The earlier isolated tests used names such as `contract-a`, `contract-b`, and `keyboard-1`. They did not include a numeric session named `0`, so they passed without exercising tmux's ambiguous target parsing.

`tests/tmux-single-sidebar/test-session-name-zero.sh` is the regression for this gap. It is GREEN after global discovery uses one all-pane query and session-window/client mutations use stable session IDs.

## Remaining restore issue

The numeric session switch is fixed, but the full PTY history restore scenario still has a separate focus/input race. The first two archive Enter actions can complete, while a later Enter may not reach the sidebar event loop after the async owner handoff. This remains separate from numeric target resolution and is tracked by `test-keyboard-e2e.sh`.

The deletion prompt input issue was separately traced to `prompt_line` inheriting the main loop's noncanonical `min 0/time 0` mode. Prompt input now uses canonical blocking mode with CR-to-newline conversion, and the PTY test sends real CR bytes for session names. Deletion/archive verification passes; repeated history restore remains unresolved.

## Trace-assisted diagnosis

The launcher trace can be enabled with `TMUX_SESSION_LAUNCHER_TRACE=1` and records a correlation ID across raw input, dispatch, prompt, switch transition, and action completion. Arrow Down is recorded as `1b5b42`; Enter is recorded as `0d`.

The keyboard E2E test writes its input trace to the retained run directory when `KEEP_RUN_DIR=true`. Set `TEST_TRACE_VERBOSE=true` to include the tmux client/pane/active snapshot immediately before each physical key write. Timeout records include the same snapshot automatically.

The latest trace proves that six session switches reach `action.complete`, while the legacy `script(1)` transport can have a live sidebar pane and an apparently active sidebar but no corresponding `input.read.result` for the next Down byte. This narrows that failure to the `script` child PTY → tmux client → sidebar input handoff; it is not evidence of a launcher session-switch failure.

The current implementation adds `@dotfiles_sidebar_input_ready` and `@dotfiles_sidebar_prompt_ready` markers, waits for two stable transition samples, and reasserts client focus after a switch. Contract, numeric-session, and lifecycle regressions pass. The attached-PTY E2E still reproduces a missing Down `input.read.result` after `transition.ready` and `action.complete`, even when tmux reports the sidebar as active. This separates tmux topology readiness from actual PTY input-channel readiness and keeps full-E2E promotion blocked.

The E2E now runs a tmux control-mode observer and records client session/window/pane, activity, key table, prefix, pane tty/input-off state, and session-change notifications. `script --log-in` preserves the raw bytes received by the script process. A recent legacy-transport failure contains the failing Down byte in that input log, while launcher `input.read.result` is absent. Because tmux `client_activity` does not change for every Enter byte, it is treated as supporting telemetry rather than proof of byte delivery.

The test now also provides `tests/tmux-single-sidebar/pty-bridge.c`, a small test-only `forkpty(3)` transport that logs stdin→PTY writes and PTY→client output with timestamps and hex bytes, including termios, FD flags, window size, poll revents, and signals. `TMUX_KEYBOARD_E2E_SCENARIO=minimal` isolates one session switch followed by one Down; both bridge and `script(1)` pass this short case, so the failure is state-dependent in the longer workflow.

The full scenario now verifies explicit targets `keyboard-1` through `keyboard-6`; it no longer counts the initial cursor wrap from `keyboard-6` to the anchor as a session switch. With that ambiguity removed, the interposer showed that `script(1)` read and wrote the post-switch Down (`1b5b42`) successfully, but its unconsumed coprocess stdout repeatedly returned `EPIPE` while output was being written. The launcher then stopped receiving subsequent input. The test was therefore masking an output backpressure/closed-pipe problem as a session-switch failure.

`tests/tmux-single-sidebar/pty-interposer.c` provides the no-package fallback when `strace` is unavailable and traces libc PTY/socket/poll operations in both `script(1)` and its tmux child. The E2E now redirects unused `script` stdout/stderr to `/dev/null`; `--log-out` remains the retained client-output channel. Minimal and full scenarios pass with both bridge and `script(1)`, and script full E2E passes three consecutive runs. The bridge remains a comparison transport, while the real script path is now covered by acceptance.

## Checkpoint policy

This diagnosis is committed on `feature/single-sidebar` as a checkpoint. `master` is not merged or changed until the user explicitly confirms it.
