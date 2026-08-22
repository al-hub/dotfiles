#!/usr/bin/env bash
set -euo pipefail

# Attached-PTY lifecycle entrypoint. The scenario currently shares the
# existing multi-window archive/restore path; its assertions are being moved
# to window-local expectations by the contract suite.
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec env TMUX_KEYBOARD_E2E_SCENARIO=multi-window-topology \
    TMUX_KEYBOARD_E2E_SYSCALL_TRACE="${TMUX_KEYBOARD_E2E_SYSCALL_TRACE:-0}" \
    bash "$TEST_DIR/test-keyboard-e2e.sh" "$@"
