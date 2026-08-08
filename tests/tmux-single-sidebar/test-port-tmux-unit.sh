#!/usr/bin/env bash
# Unit test for tmux port & adapter isolation in scripts/lib/sidebar_port_tmux.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"

# Mock sidebar_tmux_cmd for unit test
sidebar_tmux_cmd() {
    local cmd="$1"
    shift
    if [ "$cmd" = "display-message" ]; then
        echo "mock_session_1"
        return 0
    elif [ "$cmd" = "switch-client" ]; then
        echo "SWITCH_SUCCESS"
        return 0
    fi
    return 1
}

res="$(sidebar_port_get_current_session)"
[ "$res" = "mock_session_1" ] || { echo "FAIL: get_current_session expected 'mock_session_1', got '$res'"; exit 1; }

switch_res="$(sidebar_port_switch_client "/dev/pts/1" "target_session")"
[ "$switch_res" = "SWITCH_SUCCESS" ] || { echo "FAIL: switch_client failed"; exit 1; }

echo "PASS: tmux port unit tests"
