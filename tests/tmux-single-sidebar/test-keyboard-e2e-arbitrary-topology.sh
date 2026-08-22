#!/usr/bin/env bash
set -euo pipefail

# Attached-PTY acceptance test for arbitrary pane-tree semantic restoration.
# Physical pane IDs/PIDs are expected to change because restore recreates panes
# and shells; logical slot/title/path/topology must remain stable.
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec env TMUX_KEYBOARD_E2E_SCENARIO=arbitrary-topology \
    TMUX_KEYBOARD_E2E_SYSCALL_TRACE="${TMUX_KEYBOARD_E2E_SYSCALL_TRACE:-0}" \
    bash "$TEST_DIR/test-keyboard-e2e.sh" "$@"
