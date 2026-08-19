#!/usr/bin/env bash
# Unit test for restore_terminal clean teardown without command-not-found errors
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Running restore_terminal Unit Tests ==="

test_restore_terminal_clean() {
    local target_script="$1"
    local label="$2"

    # Run subshell that sources the launcher functions and executes restore_terminal
    local err_out
    err_out="$(
        bash -c '
            set -euo pipefail
            TARGET="$1"
            REPO_ROOT="$2"
            # Mock prerequisites
            stty_state=""
            SIDEBAR_WINDOW_ID=""
            stop_tick_timer() { :; }
            show_cursor() { :; }
            tmux() { :; }

            # Source launcher functions omitting main execution
            source <(sed "/^main \"\\\$@\"$/d" "$TARGET")

            # Execute restore_terminal and capture stderr
            restore_terminal
        ' _ "$target_script" "$REPO_ROOT" 2>&1
    )" || true

    if [[ "$err_out" =~ "command not found" ]] || [[ "$err_out" =~ "sidebar_tmux_control_stop" ]]; then
        echo "FAIL: $label produced error on restore_terminal: $err_out"
        return 1
    fi

    echo "PASS: $label executes restore_terminal cleanly without command-not-found"
    return 0
}

test_restore_terminal_clean "$REPO_ROOT/scripts/tmux-session-launcher" "scripts/tmux-session-launcher"
test_restore_terminal_clean "$REPO_ROOT/dist/tmux-session-launcher" "dist/tmux-session-launcher"

echo "=== All restore_terminal Unit Tests Passed ==="
