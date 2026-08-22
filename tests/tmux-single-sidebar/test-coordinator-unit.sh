#!/usr/bin/env bash
# Unit test for coordinator module in scripts/lib/sidebar_coordinator.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_coordinator.sh"

status="$(sidebar_coordinator_init "test_coord_session")"
[ "$status" = "INIT_OK" ] || { echo "FAIL: coordinator init failed"; exit 1; }

echo "PASS: coordinator unit tests"
