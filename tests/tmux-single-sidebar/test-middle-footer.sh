#!/usr/bin/env bash
# TDD test script for verifying footer anchoring at the bottom of sidebar pane
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-middle-footer-$$"

tmuxc() { tmux -L "$SOCKET" "$@"; }

cleanup() {
    tmuxc kill-server >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

echo "=== TDD Test Suite: Footer Anchoring Bug (Issue 1) ==="

# 1. Setup server and attached client on session main
tmuxc new-session -d -s main -n window0 -c "$REPO_ROOT" 'sleep 300'
tmuxc set-option -g default-size 80x40 2>/dev/null || true
setsid script -qefc "stty rows 40 cols 80; TERM=xterm-256color tmux -L $SOCKET attach-session -t main" /tmp/test-footer-client.log >/dev/null 2>&1 &
sleep 2

CLIENT_TTY="$(tmuxc list-clients -F '#{client_tty}' | head -n 1)"
[ -n "$CLIENT_TTY" ] || { echo "FAIL: Client attachment failed"; exit 1; }

# Ensure sidebar on main
main_win="$(tmuxc list-windows -t main -F '#{window_id}' | head -n 1)"
tmuxc run-shell "$LAUNCHER --toggle-sidebar"
sleep 1.0
sidebar_pane="$(tmuxc list-panes -t "$main_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2=="dotfiles-session-sidebar"{print $1}')"

# Test 1: Create new session via TUI and check footer position on new session
echo "Testing footer line position on new session creation..."
tmuxc select-pane -t "$sidebar_pane"
sleep 0.5
tmuxc send-keys -t "$sidebar_pane" c
sleep 0.5
tmuxc send-keys -t "$sidebar_pane" "sess_test_footer"
tmuxc send-keys -t "$sidebar_pane" Enter
sleep 1.5

new_sidebar_pane="$(tmuxc list-panes -t sess_test_footer -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2=="dotfiles-session-sidebar"{print $1}')"
PANE_HEIGHT="$(tmuxc display-message -p -t "$new_sidebar_pane" '#{pane_height}')"
FOOTER_LINE_NO="$(tmuxc capture-pane -p -t "$new_sidebar_pane" | grep -n "j/k" | head -n 1 | cut -d: -f1 || echo 0)"

echo "Pane height: $PANE_HEIGHT, Footer line found at: $FOOTER_LINE_NO"

if [ "$FOOTER_LINE_NO" -eq "$PANE_HEIGHT" ]; then
    echo "PASS: Footer correctly anchored at bottom line $PANE_HEIGHT"
else
    echo "FAIL: Footer incorrectly placed at line $FOOTER_LINE_NO (expected $PANE_HEIGHT)"
    exit 1
fi

echo "=== ALL FOOTER ANCHORING TDD TESTS PASSED ==="
