#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec env TMUX_KEYBOARD_E2E_SCENARIO=direct-layout \
    TMUX_KEYBOARD_E2E_SPLIT_DIRECTION="${TMUX_KEYBOARD_E2E_SPLIT_DIRECTION:-horizontal}" \
    bash "$TEST_DIR/test-keyboard-e2e.sh"
