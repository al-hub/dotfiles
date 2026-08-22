#!/usr/bin/env bash
set -euo pipefail

# Attached-PTY RED contract for global on/off across all managed windows.
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec env TMUX_KEYBOARD_E2E_SCENARIO=window-local-toggle \
    TMUX_KEYBOARD_E2E_SYSCALL_TRACE="${TMUX_KEYBOARD_E2E_SYSCALL_TRACE:-0}" \
    TMUX_SESSION_LAUNCHER_TRACE=1 \
    bash "$TEST_DIR/test-keyboard-e2e.sh" "$@"
