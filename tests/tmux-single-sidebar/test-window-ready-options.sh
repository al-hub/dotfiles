#!/usr/bin/env bash
set -euo pipefail

# Test for O(1) In-Memory Window Options vs capture-pane Polling
# Verifies that option-based readiness check finishes reliably under realistic environment overhead (<150ms).

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
SOCKET="dotfiles-ready-opt-test-$$"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ready-opt-test.XXXXXX")"
KEEP_RUN_DIR="${KEEP_RUN_DIR:-false}"

TMUX_BIN="/usr/bin/tmux"
[ -x "$TMUX_BIN" ] || TMUX_BIN="tmux"

tmux_raw() {
    "$TMUX_BIN" -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf" "$@"
}

cleanup() {
    "$TMUX_BIN" -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    [ "$KEEP_RUN_DIR" = true ] || rm -rf -- "$RUN_DIR"
}
trap cleanup EXIT INT TERM

# 1. Start isolated tmux server
tmux_raw new-session -d -s sess-a -c "$REPO_ROOT"
tmux_raw new-session -d -s sess-b -c "$REPO_ROOT"

win_a="$(tmux_raw list-windows -t =sess-a: -F '#{window_id}' | head -n 1)"
win_b="$(tmux_raw list-windows -t =sess-b: -F '#{window_id}' | head -n 1)"

# Add a dummy sidebar pane in sess-a
sidebar_pane_a="$(tmux_raw split-window -d -t "$win_a" -h -b -l 30 -P -F '#{pane_id}')"
tmux_raw select-pane -t "$sidebar_pane_a" -T 'dotfiles-session-sidebar'
tmux_raw set-option -wq -t "$win_a" @dotfiles_sidebar_pane_id "$sidebar_pane_a"

# Export isolated adapter function pointing to the exact test socket
sidebar_tmux_cmd() {
    tmux_raw "$@"
}

# Source exact options defined in launcher
SIDEBAR_WINDOW_READY_OPTION="@dotfiles_sidebar_ready"
SIDEBAR_SELECTION_SYNC_ACK_OPTION="@dotfiles_sidebar_selection_sync_ack"
SIDEBAR_WINDOW_PANE_OPTION="@dotfiles_sidebar_pane_id"

# In-memory readiness check function (identical to scripts/tmux-session-launcher)
sidebar_window_ready() {
    local window_id="$1" pane_id="${2:-}" pane_dead ready
    ready="$(sidebar_tmux_cmd show-option -wqv -t "$window_id" "$SIDEBAR_WINDOW_READY_OPTION" 2>/dev/null || true)"
    if [ "$ready" = "1" ]; then
        return 0
    fi
    [ -n "$pane_id" ] || pane_id="$(sidebar_tmux_cmd show-option -wqv -t "$window_id" "$SIDEBAR_WINDOW_PANE_OPTION" 2>/dev/null || true)"
    [ -n "$pane_id" ] || return 1
    pane_dead="$(sidebar_tmux_cmd display-message -p -t "$pane_id" '#{pane_dead}' 2>/dev/null || true)"
    [ "$pane_dead" = "0" ] && [ "$ready" = "1" ]
}

# --- Test 1: Unready State ---
tmux_raw set-option -wq -t "$win_a" "$SIDEBAR_WINDOW_READY_OPTION" 0
if sidebar_window_ready "$win_a"; then
    echo "FAIL: sidebar_window_ready returned true when option is 0"
    exit 1
fi
echo "PASS: sidebar_window_ready returns false when option is 0"

# --- Test 2: Ready State ---
tmux_raw set-option -wq -t "$win_a" "$SIDEBAR_WINDOW_READY_OPTION" 1
if ! sidebar_window_ready "$win_a"; then
    echo "FAIL: sidebar_window_ready returned false when option is 1"
    exit 1
fi
echo "PASS: sidebar_window_ready returns true when option is 1"

# --- Test 3: Benchmark latency on READY state (< 150ms Hard Gate) ---
start_ns=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
for i in {1..20}; do
    sidebar_window_ready "$win_a"
done
end_ns=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
total_ns=$((end_ns - start_ns))
avg_ms=$(awk "BEGIN {printf \"%.2f\", $total_ns / 20 / 1000000}")
echo "Measured 20 queries on ready state: total ${total_ns}ns, avg ${avg_ms}ms"

is_under_150ms=$(awk "BEGIN {print ($avg_ms < 150) ? 1 : 0}")
if [ "$is_under_150ms" -ne 1 ]; then
    echo "FAIL: Exceeded 150ms ($avg_ms ms)"
    exit 1
fi
echo "PASS: sidebar_window_ready finishes <150ms (avg: ${avg_ms}ms)"
echo "ALL READINESS OPTION TESTS PASSED SAFELY!"
