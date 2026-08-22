#!/usr/bin/env bash
set -euo pipefail

# Multi-window archive/restore regression. The scenario uses an attached PTY
# for every user action and compares semantic before/after metadata.
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec env TMUX_KEYBOARD_E2E_SCENARIO=multi-window-topology \
    TMUX_KEYBOARD_E2E_SYSCALL_TRACE="${TMUX_KEYBOARD_E2E_SYSCALL_TRACE:-0}" \
    bash "$TEST_DIR/test-keyboard-e2e.sh" "$@"
