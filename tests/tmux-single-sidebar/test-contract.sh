#!/usr/bin/env bash
set -euo pipefail

# Contract test for the global single-sidebar design. It exercises one
# persistent pane/process across managed session targets.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-single-sidebar-contract-$$"
TMUX=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")
KEEP_RUN_DIR="${KEEP_RUN_DIR:-false}"

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

wait_for_sidebar_count()
{
    local expected="$1" deadline=$(( $(date +%s) + 5 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        [ "$(count_sidebars)" -eq "$expected" ] && return 0
        sleep 0.05
    done
    printf 'ERROR: expected sidebar count %s, got %s\n' "$expected" "$(count_sidebars)" >&2
    return 1
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

# Ensuring another session must not create a second sidebar.
"${TMUX[@]}" run-shell "$LAUNCHER --ensure-sidebar-session contract-b"
wait_for_sidebar_count 1

[ "$(count_sidebars)" -eq 1 ]
sidebar_after="$(${TMUX[@]} list-panes -a -F '#{pane_id}|#{pane_title}' |
    awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
pid_after="$(${TMUX[@]} display-message -p -t "$sidebar_after" '#{pane_pid}')"
[ "$sidebar_before" = "$sidebar_after" ]
[ "$pid_before" = "$pid_after" ]
printf 'PASS: target ensure preserves one global sidebar\n'
printf 'PASS: target ensure preserves sidebar pane identity/process\n'

# This contract test has no attached client, so an implicit active session is
# undefined. Use the explicit session toggle; active-window behavior is covered
# by attached-PTY scenarios where a client context exists.
"${TMUX[@]}" run-shell "$LAUNCHER --open-sidebar"
wait_for_sidebar_count 0
printf 'PASS: global off removes the single sidebar\n'
