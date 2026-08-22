#!/usr/bin/env bash
set -euo pipefail

SOCKET="test-swap-resize-fidelity-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="$(mktemp -d /tmp/test-swap-res-fid.XXXXXX)"

cleanup() {
    tmux -L "$SOCKET" kill-server 2>/dev/null || true
    rm -rf "$STATE_DIR"
}
trap cleanup EXIT

export TMUX="$SOCKET"
export TMUX_SESSION_SIDEBAR_SUBPANE_HEIGHT_STATE_FILE="$STATE_DIR/height"
export TMUX_SESSION_SIDEBAR_SUBPANE_POSITION_STATE_FILE="$STATE_DIR/pos"
export TMUX_SESSION_SIDEBAR_SUBPANE_ENABLED_STATE_FILE="$STATE_DIR/enabled"

source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_subpane_hub.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_topology.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_switch.sh"

# 1. Setup 2 sessions
tmux -L "$SOCKET" new-session -d -s sess_1 -n work -x 120 -y 50 "sleep 100"
win_1="$(tmux -L "$SOCKET" display-message -p -t sess_1 "#{window_id}")"
sb_1="$(tmux -L "$SOCKET" split-window -P -F "#{pane_id}" -d -t "$win_1" -h -f -b -l 30 "sleep 100")"
tmux -L "$SOCKET" select-pane -t "$sb_1" -T "dotfiles-session-sidebar"
tmux -L "$SOCKET" set-option -p -q -t "$sb_1" @dotfiles_sidebar_pane 1

tmux -L "$SOCKET" new-session -d -s sess_2 -n work -x 120 -y 50 "sleep 100"
win_2="$(tmux -L "$SOCKET" display-message -p -t sess_2 "#{window_id}")"
sb_2="$(tmux -L "$SOCKET" split-window -P -F "#{pane_id}" -d -t "$win_2" -h -f -b -l 30 "sleep 100")"
tmux -L "$SOCKET" select-pane -t "$sb_2" -T "dotfiles-session-sidebar"
tmux -L "$SOCKET" set-option -p -q -t "$sb_2" @dotfiles_sidebar_pane 1

# Step 1: Initial subpane at bottom with height 15
sub_p="$(provision_sidebar_subpane "$win_1" "$sb_1" 15 "")"
tmux -L "$SOCKET" set-option -g @dotfiles_sidebar_subpane_height 15
persist_sidebar_subpane_height 15

# Step 2: User manually resizes subpane to 24 in sess_1
tmux -L "$SOCKET" resize-pane -t "$sub_p" -y 24

# Step 3: User swaps position to top via P (sidebar_subpane_swap_position)
sidebar_subpane_swap_position "$win_1"
h_top="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
pos_top="$(sidebar_subpane_get_position)"
[ "$pos_top" = "top" ] || exit 1
[ "$h_top" -eq 24 ] || { echo "FAIL: manual resize 24 was destroyed to $h_top"; exit 1; }

# Step 4: Immediately switch to sess_2 (Enter)
h_opt="$(tmux -L "$SOCKET" show-option -gqv @dotfiles_sidebar_subpane_height)"
sidebar_switch_execute_hot "" "sess_2" "$win_2" "$sb_2" "30" "$sub_p" "$h_opt"
h_s2="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
s_top_s2="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_top}")"
l_top_s2="$(tmux -L "$SOCKET" display-message -p -t "$sb_2" "#{pane_top}")"
[ "$s_top_s2" -lt "$l_top_s2" ] || exit 1
[ "$h_s2" -eq 24 ] || { echo "FAIL: height decayed from 24 to $h_s2 in sess_2"; exit 1; }

# Step 5: In sess_2, user manually resizes subpane to 19
tmux -L "$SOCKET" resize-pane -t "$sub_p" -y "$(sidebar_subpane_calc_resize_length "top" 19)"

# Step 6: User swaps position to bottom via P
sidebar_subpane_swap_position "$win_2"
h_bot="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
pos_bot="$(sidebar_subpane_get_position)"
[ "$pos_bot" = "bottom" ] || exit 1
[ "$h_bot" -eq 19 ] || { echo "FAIL: manual resize 19 was destroyed to $h_bot"; exit 1; }

# Step 7: Immediately switch back to sess_1 (Enter)
h_opt2="$(tmux -L "$SOCKET" show-option -gqv @dotfiles_sidebar_subpane_height)"
sidebar_switch_execute_hot "" "sess_1" "$win_1" "$sb_1" "30" "$sub_p" "$h_opt2"
h_s1_final="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
s_top_s1_final="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_top}")"
l_top_s1_final="$(tmux -L "$SOCKET" display-message -p -t "$sb_1" "#{pane_top}")"
[ "$s_top_s1_final" -gt "$l_top_s1_final" ] || exit 1
[ "$h_s1_final" -eq 19 ] || { echo "FAIL: height decayed from 19 to $h_s1_final in sess_1"; exit 1; }

echo "PASS: Manual resize followed by position swap and session switches maintains 100% height fidelity with ZERO decay!"
