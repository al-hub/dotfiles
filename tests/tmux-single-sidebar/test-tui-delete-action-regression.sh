#!/usr/bin/env bash
# TDD Test for execute_tui_session_delete_action implementation in scripts/tmux-session-launcher
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUNCHER="$SCRIPT_DIR/scripts/tmux-session-launcher"

# Verify execute_tui_session_delete_action function definition exists in launcher
if ! grep -q 'execute_tui_session_delete_action()' "$LAUNCHER"; then
    echo "FAIL: execute_tui_session_delete_action function definition missing in $LAUNCHER"
    exit 1
fi

echo "PASS: execute_tui_session_delete_action definition test"
