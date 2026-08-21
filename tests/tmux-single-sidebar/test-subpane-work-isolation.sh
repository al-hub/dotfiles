#!/usr/bin/env bash
set -euo pipefail

SOCKET="test-subpane-work-iso-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="$(mktemp -d /tmp/test-subpane-work-iso-state.XXXXXX)"

cleanup() {
    tmux -L "$SOCKET" kill-server 2>/dev/null || true
    rm -rf "$STATE_DIR"
}
trap cleanup EXIT

export TMUX="$SOCKET"
export TMUX_SESSION_LAUNCHER_SOCKET="$SOCKET"
export TMUX_SESSION_SIDEBAR_SUBPANE_HEIGHT_STATE_FILE="$STATE_DIR/height"
export TMUX_SESSION_SIDEBAR_SUBPANE_POSITION_STATE_FILE="$STATE_DIR/pos"
export TMUX_SESSION_SIDEBAR_SUBPANE_ENABLED_STATE_FILE="$STATE_DIR/enabled"

tmux -L "$SOCKET" new-session -d -s main -n work -x 120 -y 50 "sleep 100"
sleep 0.5
win_id="$(tmux -L "$SOCKET" display-message -p -t main "#{window_id}")"

# 1. Open sidebar and enable subpane (height 22)
bash "$SCRIPT_DIR/dist/tmux-session-launcher" --ensure-current-sidebar "$win_id"
sleep 0.5
bash "$SCRIPT_DIR/dist/tmux-session-launcher" --toggle-subpane "$win_id"
sleep 0.5

sub_p="$(tmux -L "$SOCKET" list-panes -t "$win_id" -F "#{pane_id}|#{@dotfiles_sidebar_subpane}" | awk -F "|" '$2 == "1" { print $1 }')"
[ -n "$sub_p" ] || { echo "FAIL: subpane not found"; exit 1; }
tmux -L "$SOCKET" resize-pane -t "$sub_p" -y 22
sleep 0.5

h_init="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
[ "$h_init" -eq 22 ] || { echo "FAIL: initial subpane height is $h_init, expected 22"; exit 1; }

# 2. Focus in subpane and trigger work pane vertical split (Ctrl+a _)
tmux -L "$SOCKET" select-pane -t "$sub_p"
sleep 0.2
bash "$SCRIPT_DIR/dist/tmux-session-launcher" --split-vertical
sleep 0.5

sub_h="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
[ "$sub_h" -eq 22 ] || { echo "FAIL: subpane height changed after work split: $sub_h, expected 22"; exit 1; }

# 3. Toggle sidebar OFF and ON
bash "$SCRIPT_DIR/dist/tmux-session-launcher" --toggle-sidebar
sleep 0.5

bash "$SCRIPT_DIR/dist/tmux-session-launcher" --toggle-sidebar
sleep 0.5

sub_p_restored="$(tmux -L "$SOCKET" list-panes -t "$win_id" -F "#{pane_id}|#{@dotfiles_sidebar_subpane}" 2>/dev/null | awk -F "|" '$2 == "1" { print $1 }')"
[ -n "$sub_p_restored" ] || { echo "FAIL: subpane not restored after toggle"; exit 1; }

sub_h_restored="$(tmux -L "$SOCKET" display-message -p -t "$sub_p_restored" "#{pane_height}")"
[ "$sub_h_restored" -eq 22 ] || { echo "FAIL: restored subpane height is $sub_h_restored, expected 22"; exit 1; }

echo "PASS: Subpane isolation against work pane splits and sidebar toggles verified!"
