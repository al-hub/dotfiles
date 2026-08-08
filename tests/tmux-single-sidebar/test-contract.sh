#!/usr/bin/env bash
set -euo pipefail

# Contract test for the window-local sidebar design. It exercises one sidebar
# per managed window and verifies that ensuring another window does not replace
# the existing pane/process.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-single-sidebar-contract-$$"
TMUX=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-single-sidebar-contract.XXXXXX")"
STATE_FILE="$RUN_DIR/sidebar-width"
KEEP_RUN_DIR="${KEEP_RUN_DIR:-false}"

cleanup()
{
    "${TMUX[@]}" kill-server >/dev/null 2>&1 || true
    [ "$KEEP_RUN_DIR" = true ] || rm -rf -- "$RUN_DIR"
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
"${TMUX[@]}" set-environment -g TMUX_SESSION_SIDEBAR_WIDTH_STATE_FILE "$STATE_FILE"
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

# Ensuring another managed window creates its own local sidebar; the existing
# sidebar in contract-a must remain unchanged.
"${TMUX[@]}" run-shell "$LAUNCHER --ensure-sidebar-session contract-b" || true
wait_for_sidebar_count 2

[ "$(count_sidebars)" -eq 2 ]
sidebar_after="$(${TMUX[@]} list-panes -a -F '#{pane_id}|#{pane_title}' |
    awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
pid_after="$(${TMUX[@]} display-message -p -t "$sidebar_after" '#{pane_pid}')"
[ "$sidebar_before" = "$sidebar_after" ]
[ "$pid_before" = "$pid_after" ]
printf 'PASS: target ensure creates one sidebar per managed window\n'
printf 'PASS: target ensure preserves sidebar pane identity/process\n'

# A manual pane resize is followed by the same layout hook used by tmux's
# after-resize-pane event. The last user width must become the shared default
# used when another managed window is ensured.
"${TMUX[@]}" resize-pane -t "$sidebar_before" -x 45
"${TMUX[@]}" run-shell "$LAUNCHER --sync-sidebar-layout @0 manual-resize"
for attempt in $(seq 1 50); do
    [ "$(${TMUX[@]} show-option -gqv @dotfiles-session-sidebar-width 2>/dev/null || true)" = 45 ] && break
    sleep 0.05
done
[ "$(${TMUX[@]} show-option -gqv @dotfiles-session-sidebar-width 2>/dev/null || true)" = 45 ]
[ "$(sed -n '1p' "$STATE_FILE" 2>/dev/null || true)" = 45 ]
"${TMUX[@]}" run-shell "$LAUNCHER --ensure-sidebar-session contract-b"
contract_b_sidebar="$(${TMUX[@]} list-panes -t '=contract-b:' -F '#{pane_id}|#{pane_title}' |
    awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
[ "$(${TMUX[@]} display-message -p -t "$contract_b_sidebar" '#{pane_width}')" = 45 ]
printf 'PASS: manual sidebar resize is saved as the global width\n'
printf 'PASS: manual sidebar resize is persisted outside the tmux server\n'
printf 'PASS: newly ensured session reuses the last global sidebar width\n'

# A stale window option must not prevent the normal provision path from
# creating/identifying the real sidebar pane.
stale_contract_a_sidebar="$(${TMUX[@]} list-panes -t '=contract-a:' -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
"${TMUX[@]}" kill-pane -t "$stale_contract_a_sidebar"
"${TMUX[@]}" set-option -wq -t @0 @dotfiles_sidebar_pane_id %stale-pane
"${TMUX[@]}" set-option -wq -t @0 @dotfiles_sidebar_ready 1
"${TMUX[@]}" run-shell "$LAUNCHER --ensure-sidebar-session contract-a" || true
wait_for_sidebar_count 2
actual_contract_a_sidebar="$(${TMUX[@]} list-panes -t '=contract-a:' -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
[ "$(${TMUX[@]} show-options -wqv -t @0 @dotfiles_sidebar_pane_id)" = "$actual_contract_a_sidebar" ]
[ "$(${TMUX[@]} show-options -wqv -t @0 @dotfiles_sidebar_ready)" = 1 ]
printf 'PASS: stale sidebar metadata is invalidated and repaired\n'

# A second toggle during provisioning must not remove the newly-created
# sidebar or start a duplicate lifecycle.
"${TMUX[@]}" set-option -gq @dotfiles_sidebar_provisioning 1
"${TMUX[@]}" run-shell "$LAUNCHER --open-sidebar" || true
[ "$(count_sidebars)" -eq 2 ]
"${TMUX[@]}" set-option -gq @dotfiles_sidebar_provisioning 0
printf 'PASS: toggle during provisioning is suppressed\n'

# This contract test has no attached client, so an implicit active session is
# undefined. Use the explicit session toggle; active-window behavior is covered
# by attached-PTY scenarios where a client context exists.
"${TMUX[@]}" run-shell "$LAUNCHER --toggle-sidebar"
wait_for_sidebar_count 0
printf 'PASS: global off removes the single sidebar\n'
