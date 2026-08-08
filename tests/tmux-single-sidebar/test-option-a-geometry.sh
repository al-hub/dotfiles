#!/usr/bin/env bash
# TDD test script for Option A: Inheriting active client geometry on background session creation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-opt-a-$$"

tmuxc() { tmux -L "$SOCKET" "$@"; }

cleanup() {
    tmuxc kill-server >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

echo "=== TDD Test Suite: Option A Client Geometry Inheritance ==="

# Setup attached client with 80x40 terminal geometry
tmuxc new-session -d -s main -n window0 -c "$REPO_ROOT" 'sleep 300'
setsid script -qefc "stty rows 40 cols 80; TERM=xterm-256color tmux -L $SOCKET attach-session -t main" /tmp/test-opt-a-client.log >/dev/null 2>&1 &
sleep 2

CLIENT_TTY="$(tmuxc list-clients -F '#{client_tty}' | head -n 1)"
[ -n "$CLIENT_TTY" ] || { echo "FAIL: Client attachment failed"; exit 1; }

# Ensure sidebar on main
main_win="$(tmuxc list-windows -t main -F '#{window_id}' | head -n 1)"
tmuxc run-shell "$LAUNCHER --toggle-sidebar"
sleep 1.0
sidebar_pane="$(tmuxc list-panes -t "$main_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2=="dotfiles-session-sidebar"{print $1}')"

# Test Option A: Create session sessA and sessB via TUI
echo "Creating sessA and sessB via TUI..."
tmuxc select-pane -t "$sidebar_pane"
sleep 0.5

# Create sessA
tmuxc send-keys -t "$sidebar_pane" c
sleep 0.5
tmuxc send-keys -t "$sidebar_pane" "sessA" Enter
sleep 1.0

# Create sessB
tmuxc send-keys -t "$sidebar_pane" c
sleep 0.5
tmuxc send-keys -t "$sidebar_pane" "sessB" Enter
sleep 1.0

if ! tmuxc has-session -t sessB 2>/dev/null; then
    echo "DEBUG: sessB not found. Sidebar pane output:"
    tmuxc capture-pane -p -t "$sidebar_pane" || true
    exit 1
fi
sidebar_sessB="$(tmuxc list-panes -t sessB -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2=="dotfiles-session-sidebar"{print $1}')"
PRE_PANE_HEIGHT="$(tmuxc display-message -p -t "$sidebar_sessB" '#{pane_height}')"
echo "sessB sidebar pane height BEFORE switch-client: $PRE_PANE_HEIGHT"

# Switch client to sessB
tmuxc send-keys -t "$sidebar_pane" Down Enter
sleep 1.0

POST_PANE_HEIGHT="$(tmuxc display-message -p -t "$sidebar_sessB" '#{pane_height}')"
FOOTER_LINE="$(tmuxc capture-pane -p -t "$sidebar_sessB" | grep -n "j/k" | head -n 1 | cut -d: -f1 || echo 0)"

echo "sessB sidebar pane height AFTER switch-client: $POST_PANE_HEIGHT, Footer at line: $FOOTER_LINE"

if [ "$PRE_PANE_HEIGHT" -ge 35 ] && [ "$FOOTER_LINE" -eq "$POST_PANE_HEIGHT" ]; then
    echo "PASS: Option A successfully inherited active client geometry and anchored footer at line $FOOTER_LINE"
else
    echo "FAIL: Option A failed. pre_height=$PRE_PANE_HEIGHT, post_height=$POST_PANE_HEIGHT, footer_line=$FOOTER_LINE"
    exit 1
fi

echo "=== ALL OPTION A TDD TESTS PASSED ==="
