#!/usr/bin/env bash
set -euo pipefail

# Deliberately RED reproduction for the vertical work-split topology.
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec env TMUX_KEYBOARD_E2E_SCENARIO=split-cycle \
    TMUX_KEYBOARD_E2E_SPLIT_DIRECTION=vertical \
    TMUX_KEYBOARD_E2E_SYSCALL_TRACE="${TMUX_KEYBOARD_E2E_SYSCALL_TRACE:-0}" \
    bash "$TEST_DIR/test-keyboard-e2e.sh" "$@"
