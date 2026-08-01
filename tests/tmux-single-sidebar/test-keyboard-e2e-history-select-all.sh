#!/usr/bin/env bash
set -euo pipefail

# Regression for the real attached-PTY archive workflow. It verifies that
# rapid history selection has an explicit all-mark operation and that restore
# reports the selected/restored cardinality instead of silently omitting rows.
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec env TMUX_KEYBOARD_E2E_SCENARIO=history-select-all \
    TMUX_KEYBOARD_E2E_SYSCALL_TRACE=0 \
    TMUX_SESSION_LAUNCHER_TRACE=1 \
    bash "$TEST_DIR/test-keyboard-e2e.sh" "$@"
