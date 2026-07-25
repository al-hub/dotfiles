#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec env \
    TMUX_KEYBOARD_E2E_SCENARIO=rapid-operations \
    TMUX_SESSION_LAUNCHER_TRACE=1 \
    TMUX_SESSION_LAUNCHER_TEST_OPERATION_DELAY="${TMUX_SESSION_LAUNCHER_TEST_OPERATION_DELAY:-0.4}" \
    bash "$TEST_DIR/test-keyboard-e2e.sh"
