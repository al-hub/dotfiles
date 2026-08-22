#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"

# 1. Test pure domain function is_infrastructure_session
if ! is_infrastructure_session "dotfiles-subpane-hub"; then
    echo "FAIL: dotfiles-subpane-hub should be recognized as infrastructure session"
    exit 1
fi

if is_infrastructure_session "my-work-session"; then
    echo "FAIL: my-work-session should not be recognized as infrastructure session"
    exit 1
fi

if is_infrastructure_session "0"; then
    echo "FAIL: 0 should not be recognized as infrastructure session"
    exit 1
fi

if is_infrastructure_session ""; then
    echo "FAIL: empty string should not be recognized as infrastructure session"
    exit 1
fi

# 2. Test sidebar_tmux_list_user_sessions with mocked sidebar_tmux_cmd
sidebar_tmux_cmd() {
    if [ "${1:-}" = "list-sessions" ]; then
        printf 'dotfiles-subpane-hub\t1700000000\t1700000000\n'
        printf 'work-session\t1700000001\t1700000001\n'
        printf '0\t1700000002\t1700000002\n'
    fi
}

output="$(sidebar_tmux_list_user_sessions)"
if echo "$output" | grep -q "dotfiles-subpane-hub"; then
    echo "FAIL: sidebar_tmux_list_user_sessions did not filter out dotfiles-subpane-hub"
    exit 1
fi

if ! echo "$output" | grep -q "work-session"; then
    echo "FAIL: sidebar_tmux_list_user_sessions missing work-session"
    exit 1
fi

if ! echo "$output" | grep -q "0"; then
    echo "FAIL: sidebar_tmux_list_user_sessions missing session 0"
    exit 1
fi

# Assert that each line separates into pure name, created, activity
parsed_work=0
parsed_zero=0
while IFS="$(printf '\t')" read -r name created activity; do
    [ -n "$name" ] || continue
    if [ "$name" = "work-session" ]; then
        [ "$created" = "1700000001" ] || { echo "FAIL: work-session created mismatch: $created"; exit 1; }
        [ "$activity" = "1700000001" ] || { echo "FAIL: work-session activity mismatch: $activity"; exit 1; }
        parsed_work=1
    elif [ "$name" = "0" ]; then
        [ "$created" = "1700000002" ] || { echo "FAIL: 0 created mismatch: $created"; exit 1; }
        [ "$activity" = "1700000002" ] || { echo "FAIL: 0 activity mismatch: $activity"; exit 1; }
        parsed_zero=1
    else
        echo "FAIL: unexpected session parsed: $name"
        exit 1
    fi
done <<< "$output"

if [ "$parsed_work" -ne 1 ] || [ "$parsed_zero" -ne 1 ]; then
    echo "FAIL: did not parse expected sessions with pure name"
    exit 1
fi

echo "PASS: infrastructure session registry unit tests"
