#!/usr/bin/env bash
# TDD Test suite for verifying fixes for newly discovered defects (Issues 1-4)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-new-defects-$$"

tmuxc() { tmux -L "$SOCKET" "$@"; }

cleanup() {
    tmuxc kill-server >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

echo "=== TDD Test Suite: New Operations (Issues 1-4) ==="

# 1. Setup server and attached client on session main
tmuxc new-session -d -s main -n window0 -c "$REPO_ROOT" 'sleep 300'
setsid script -qefc "TERM=xterm-256color tmux -L $SOCKET attach-session -t main" /tmp/test-new-client.log >/dev/null 2>&1 &
sleep 2

CLIENT_TTY="$(tmuxc list-clients -F '#{client_tty}' | head -n 1)"
[ -n "$CLIENT_TTY" ] || { echo "FAIL: Client attachment failed"; exit 1; }

# Ensure sidebar on main
main_win="$(tmuxc list-windows -t main -F '#{window_id}' | head -n 1)"
tmuxc run-shell "$LAUNCHER --toggle-sidebar"
sleep 1.0
sidebar_pane="$(tmuxc list-panes -t "$main_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2=="dotfiles-session-sidebar"{print $1}')"

# Test 1: Issue 1 (Major) - Deleting currently active/attached session 'main' must delete session main and switch client to fallback
echo "Testing Issue 1: Deleting active attached session 'main'..."
tmuxc new-session -d -s fallback_sess -c "$REPO_ROOT" 'sleep 300'
# Select main in TUI and delete it
tmuxc select-pane -t "$sidebar_pane"
sleep 0.5
BEFORE_CAP="$(tmuxc capture-pane -p -t "$sidebar_pane")"
echo "TUI screen before d: $BEFORE_CAP"
tmuxc send-keys -t "$sidebar_pane" d
sleep 0.5
PROMPT_CAP="$(tmuxc capture-pane -p -t "$sidebar_pane")"
if echo "$PROMPT_CAP" | grep -Fq "Delete main?"; then
    echo "Found delete prompt for main"
    tmuxc send-keys -t "$sidebar_pane" y
    tmuxc send-keys -t "$sidebar_pane" Enter
    sleep 2.0
    ALL_SESS="$(tmuxc list-sessions -F '#{session_name}')"
    if echo "$ALL_SESS" | grep -Fq "^main$"; then
        echo "FAIL: Issue 1 - active session 'main' was NOT deleted"
        exit 1
    else
        echo "PASS: Issue 1 - active session 'main' was successfully deleted"
    fi
else
    echo "FAIL: Issue 1 - delete prompt for main not displayed. Captured: $PROMPT_CAP"
    exit 1
fi

# Re-setup test environment on session fallback_sess
fallback_win="$(tmuxc list-windows -t fallback_sess -F '#{window_id}' | head -n 1)"
tmuxc set-option -w -t "$fallback_win" @dotfiles_sidebar_managed 1
tmuxc run-shell "$LAUNCHER --ensure-sidebar-window $fallback_win"
sleep 0.5
sidebar_pane="$(tmuxc list-panes -t "$fallback_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2=="dotfiles-session-sidebar"{print $1}')"

# Test 2: Issue 2 - Single key 'q' in Delete prompt closes prompt immediately without Enter
echo "Testing Issue 2: Single key 'q' closes Delete prompt immediately..."
tmuxc select-pane -t "$sidebar_pane"
sleep 0.2
tmuxc send-keys -t "$sidebar_pane" d
sleep 0.5
tmuxc send-keys -t "$sidebar_pane" q
sleep 0.5
CANCEL_CAP="$(tmuxc capture-pane -p -t "$sidebar_pane")"
if echo "$CANCEL_CAP" | grep -Fq "Delete fallback_sess?"; then
    echo "FAIL: Issue 2 - single key 'q' did not close prompt immediately"
    exit 1
else
    echo "PASS: Issue 2 - single key 'q' closed prompt immediately"
fi

# Test 3: Issue 3 - Rename session 'r' pre-populates current session name
echo "Testing Issue 3: Rename session 'r' pre-populates existing session name..."
tmuxc send-keys -t "$sidebar_pane" r
sleep 0.5
RENAME_CAP="$(tmuxc capture-pane -p -t "$sidebar_pane")"
if echo "$RENAME_CAP" | grep -Fq "Rename: fallback_sess"; then
    echo "PASS: Issue 3 - rename prompt pre-populated existing session name"
else
    echo "FAIL: Issue 3 - rename prompt did not pre-populate session name. Captured: $RENAME_CAP"
    exit 1
fi
tmuxc send-keys -t "$sidebar_pane" q
sleep 0.5

# Test 4: Issue 4 - Multi-window navigation preserves sidebar width 35
echo "Testing Issue 4: Multi-window navigation preserves sidebar width..."
tmuxc new-window -t fallback_sess -n win2 -c "$REPO_ROOT" 'sleep 300'
sleep 0.5
tmuxc select-window -t fallback_sess:0
sleep 0.5
W0_SIDEBAR_WIDTH="$(tmuxc list-panes -t fallback_sess:0 -F '#{pane_title}|#{pane_width}' | awk -F '|' '$1=="dotfiles-session-sidebar"{print $2}')"
if [ "$W0_SIDEBAR_WIDTH" -eq 35 ]; then
    echo "PASS: Issue 4 - sidebar width preserved at 35 cells across window selection"
else
    echo "FAIL: Issue 4 - sidebar width drifted to $W0_SIDEBAR_WIDTH cells (expected 35)"
    exit 1
fi

echo "=== ALL NEW DEFECT TDD TESTS PASSED ==="
