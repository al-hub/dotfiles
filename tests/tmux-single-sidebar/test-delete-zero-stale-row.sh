#!/usr/bin/env bash
set -euo pipefail

# Attached-PTY regression for a deleted numeric session remaining visible in
# another window-local sidebar and being accepted as an Enter target.
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec env \
    TMUX_KEYBOARD_E2E_SCENARIO=delete-zero-stale-row \
    TMUX_KEYBOARD_E2E_ANCHOR_SESSION=0 \
    TMUX_KEYBOARD_E2E_SYSCALL_TRACE="${TMUX_KEYBOARD_E2E_SYSCALL_TRACE:-0}" \
    bash "$TEST_DIR/test-keyboard-e2e.sh" "$@"
