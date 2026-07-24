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

`tests/tmux-single-sidebar/test-session-name-zero.sh` is the diagnostic RED regression for this gap. It must turn GREEN after the adapter uses an unambiguous session target or an equivalent stable session identifier.

## Checkpoint policy

This diagnosis is committed on `feature/single-sidebar` as a checkpoint. `master` is not merged or changed until the user explicitly confirms it.
