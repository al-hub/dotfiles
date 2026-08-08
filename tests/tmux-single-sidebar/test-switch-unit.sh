#!/usr/bin/env bash
# Unit test for switch application service in scripts/lib/sidebar_switch.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_switch.sh"

# Mock sidebar_port_switch_client
switched_target=""
sidebar_port_switch_client() {
    local tty="$1" target="$2"
    switched_target="$target"
    return 0
}

sidebar_switch_execute_hot "/dev/pts/0" "target_session_99"
[ "$switched_target" = "target_session_99" ] || { echo "FAIL: hot path switch expected 'target_session_99', got '$switched_target'"; exit 1; }

echo "PASS: switch unit tests"
