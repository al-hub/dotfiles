#!/usr/bin/env bash
set -euo pipefail

# TDD contract test for the approved single-sidebar design. It exercises the
# production move-pane path and guards the global pane/process invariant.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-single-sidebar-contract-$$"
TMUX=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")

cleanup()
{
    "${TMUX[@]}" kill-server >/dev/null 2>&1 || true
}
trap cleanup EXIT

count_sidebars()
{
    "${TMUX[@]}" list-panes -a -F '#{pane_title}' 2>/dev/null |
        awk '$0 == "dotfiles-session-sidebar" { count++ } END { print count + 0 }'
}

"${TMUX[@]}" new-session -d -s contract-a -c "$REPO_ROOT" 'sleep 300'
"${TMUX[@]}" new-session -d -s contract-b -c "$REPO_ROOT" 'sleep 300'
"${TMUX[@]}" split-window -d -t '=contract-a:' -h -b -l 35 "$LAUNCHER --sidebar"

for attempt in $(seq 1 50); do
    [ "$(count_sidebars)" -eq 1 ] && break
    sleep 0.05
done

[ "$(count_sidebars)" -eq 1 ]
sidebar_before="$(${TMUX[@]} list-panes -t '=contract-a:' -F '#{pane_id}|#{pane_title}' |
    awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
pid_before="$(${TMUX[@]} display-message -p -t "$sidebar_before" '#{pane_pid}')"
[ -n "$sidebar_before" ]
[ -n "$pid_before" ]

# This is the current switch path's target-sidebar operation. The desired
# implementation must move the existing pane instead of creating another one.
"${TMUX[@]}" run-shell "$LAUNCHER --ensure-sidebar-session contract-b"
sleep 0.2

[ "$(count_sidebars)" -eq 1 ]
sidebar_after="$(${TMUX[@]} list-panes -t '=contract-b:' -F '#{pane_id}|#{pane_title}' |
    awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
pid_after="$(${TMUX[@]} display-message -p -t "$sidebar_after" '#{pane_pid}')"
[ "$sidebar_before" = "$sidebar_after" ]
[ "$pid_before" = "$pid_after" ]
printf 'PASS: single sidebar remains unique across target session ensure\n'
printf 'PASS: sidebar pane ID and process PID survive target session move\n'

"${TMUX[@]}" run-shell "$LAUNCHER --open-sidebar"
sleep 0.1
[ "$(count_sidebars)" -eq 0 ]
printf 'PASS: active-window toggle removes the single sidebar\n'

"${TMUX[@]}" run-shell "$LAUNCHER --open-sidebar"
for attempt in $(seq 1 50); do
    [ "$(count_sidebars)" -eq 1 ] && break
    sleep 0.05
done
[ "$(count_sidebars)" -eq 1 ]
printf 'PASS: active-window toggle recreates exactly one sidebar\n'
