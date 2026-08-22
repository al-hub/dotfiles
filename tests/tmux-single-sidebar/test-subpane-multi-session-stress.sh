#!/usr/bin/env bash
set -euo pipefail

SOCKET="test-multisess-stress-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="$(mktemp -d /tmp/test-multisess-stress-state.XXXXXX)"

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

# 1. Create 3 sessions
tmux -L "$SOCKET" new-session -d -s sess_1 -n work -x 120 -y 50 "sleep 100"
tmux -L "$SOCKET" new-session -d -s sess_2 -n work -x 120 -y 50 "sleep 100"
tmux -L "$SOCKET" new-session -d -s sess_3 -n work -x 120 -y 50 "sleep 100"
sleep 0.5

win_1="$(tmux -L "$SOCKET" display-message -p -t sess_1 "#{window_id}")"
win_2="$(tmux -L "$SOCKET" display-message -p -t sess_2 "#{window_id}")"
win_3="$(tmux -L "$SOCKET" display-message -p -t sess_3 "#{window_id}")"

source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_subpane_hub.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_switch.sh"

# Step 1: Open sidebar and subpane on sess_1 (height 22)
bash "$SCRIPT_DIR/dist/tmux-session-launcher" --ensure-sidebar-window "$win_1"
sleep 0.5
bash "$SCRIPT_DIR/dist/tmux-session-launcher" --toggle-subpane "$win_1"
sleep 0.5

sub_p="$(sidebar_window_subpane "$win_1" || true)"
[ -n "$sub_p" ] || { echo "FAIL: subpane not found in win_1"; exit 1; }
tmux -L "$SOCKET" resize-pane -t "$sub_p" -y 22
remember_sidebar_subpane_height_for_window "$win_1"
sleep 0.5

h_init="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
[ "$h_init" -eq 22 ] || { echo "FAIL: initial height not 22 ($h_init)"; exit 1; }

# Step 2: Switch to sess_2 (win_2)
bash "$SCRIPT_DIR/dist/tmux-session-launcher" --ensure-sidebar-window "$win_2"
sleep 0.5
sb_2="$(sidebar_window_pane "$win_2" || true)"

sidebar_switch_execute_hot "" "sess_2" "$win_2" "$sb_2" "30" "$sub_p" "22"
sleep 0.5

sub_1="$(sidebar_window_subpane "$win_1" || true)"
sub_2="$(sidebar_window_subpane "$win_2" || true)"
[ -z "$sub_1" ] || { echo "FAIL: subpane still in win_1"; exit 1; }
[ "$sub_2" = "$sub_p" ] || { echo "FAIL: subpane not in win_2"; exit 1; }
h_2="$(tmux -L "$SOCKET" display-message -p -t "$sub_2" "#{pane_height}")"
[ "$h_2" -eq 22 ] || { echo "FAIL: height in win_2 is $h_2, expected 22"; exit 1; }

# Step 3: In sess_2, toggle subpane OFF with s
bash "$SCRIPT_DIR/dist/tmux-session-launcher" --toggle-subpane "$win_2"
sleep 0.5
sub_2_off="$(sidebar_window_subpane "$win_2" || true)"
[ -z "$sub_2_off" ] || { echo "FAIL: subpane not removed from win_2"; exit 1; }

# Step 4: In sess_2, toggle subpane ON with s
bash "$SCRIPT_DIR/dist/tmux-session-launcher" --toggle-subpane "$win_2"
sleep 0.5
sub_2_on="$(sidebar_window_subpane "$win_2" || true)"
[ "$sub_2_on" = "$sub_p" ] || { echo "FAIL: subpane not restored in win_2"; exit 1; }
h_2_on="$(tmux -L "$SOCKET" display-message -p -t "$sub_2_on" "#{pane_height}")"
[ "$h_2_on" -eq 22 ] || { echo "FAIL: height is $h_2_on, expected 22"; exit 1; }

# Step 5: Switch to sess_3 (win_3)
bash "$SCRIPT_DIR/dist/tmux-session-launcher" --ensure-sidebar-window "$win_3"
sleep 0.5
sb_3="$(sidebar_window_pane "$win_3" || true)"
sidebar_switch_execute_hot "" "sess_3" "$win_3" "$sb_3" "30" "$sub_p" "22"
sleep 0.5

sub_3="$(sidebar_window_subpane "$win_3" || true)"
[ "$sub_3" = "$sub_p" ] || { echo "FAIL: subpane not in win_3"; exit 1; }
h_3="$(tmux -L "$SOCKET" display-message -p -t "$sub_3" "#{pane_height}")"
[ "$h_3" -eq 22 ] || { echo "FAIL: height in win_3 is $h_3, expected 22"; exit 1; }

echo "PASS: Multi-session subpane transition, toggle, and height restoration verified!"
