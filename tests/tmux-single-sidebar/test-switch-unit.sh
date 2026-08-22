#!/usr/bin/env bash
# Unit test for switch application service in scripts/lib/sidebar_switch.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_switch.sh"

# Mock sidebar_port_switch_client and sidebar_tmux_cmd
switched_target=""
captured_cmd=()
sidebar_port_switch_client() {
    local tty="$1" target="$2"
    switched_target="$target"
    return 0
}

sidebar_tmux_cmd() {
    captured_cmd=("$@")
    return 0
}

# Test 1: Fallback port switch
sidebar_switch_execute_hot "/dev/pts/0" "target_session_99" "" ""
[ "$switched_target" = "target_session_99" ] || { echo "FAIL: hot path switch expected 'target_session_99', got '$switched_target'"; exit 1; }

# Test 2: Compound pipeline switch with target window and sidebar pane
sidebar_switch_execute_hot "/dev/pts/1" "sess_alpha" "@10" "%5"
[ "${captured_cmd[0]}" = "switch-client" ] || { echo "FAIL: expected switch-client first, got '${captured_cmd[0]}'"; exit 1; }
cmd_str="${captured_cmd[*]}"
[[ "$cmd_str" == *"switch-client -c /dev/pts/1 -t =sess_alpha:"* ]] || { echo "FAIL: switch-client missing from compound command"; exit 1; }
[[ "$cmd_str" == *"select-pane -t %5"* ]] || { echo "FAIL: select-pane missing from compound command"; exit 1; }

echo "PASS: switch unit tests"
