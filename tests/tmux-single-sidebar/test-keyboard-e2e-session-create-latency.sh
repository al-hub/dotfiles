#!/usr/bin/env bash
set -euo pipefail

# Attached-PTY reproduction for slow c/New/Enter session creation and
# --ensure-sidebar-window failures rendered outside the sidebar.
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec env TMUX_KEYBOARD_E2E_SCENARIO=session-create-latency \
    TMUX_KEYBOARD_E2E_ANCHOR_SESSION="${TMUX_KEYBOARD_E2E_ANCHOR_SESSION:-0}" \
    TMUX_KEYBOARD_E2E_SEED_LIVE_TOPOLOGY="${TMUX_KEYBOARD_E2E_SEED_LIVE_TOPOLOGY:-0}" \
    TMUX_KEYBOARD_E2E_TRANSPORT="${TMUX_KEYBOARD_E2E_TRANSPORT:-script}" \
    TMUX_KEYBOARD_E2E_SYSCALL_TRACE="${TMUX_KEYBOARD_E2E_SYSCALL_TRACE:-0}" \
    TMUX_SESSION_LAUNCHER_TRACE=1 \
    TMUX_SESSION_LAUNCHER_DEBUG=1 \
    bash "$TEST_DIR/test-keyboard-e2e.sh" "$@"
