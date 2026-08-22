#!/usr/bin/env bash
set -euo pipefail

SOCKET="test-top-switch-decay-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="$(mktemp -d /tmp/test-top-switch-decay.XXXXXX)"

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

# 1. Create 3 sessions
tmux -L "$SOCKET" new-session -d -s s1 -n work -x 120 -y 50 "sleep 100"
win_1="$(tmux -L "$SOCKET" display-message -p -t s1 "#{window_id}")"
sb_1="$(tmux -L "$SOCKET" split-window -P -F "#{pane_id}" -d -t "$win_1" -h -f -b -l 30 "sleep 100")"
tmux -L "$SOCKET" select-pane -t "$sb_1" -T "dotfiles-session-sidebar"
tmux -L "$SOCKET" set-option -p -q -t "$sb_1" @dotfiles_sidebar_pane 1

tmux -L "$SOCKET" new-session -d -s s2 -n work -x 120 -y 50 "sleep 100"
win_2="$(tmux -L "$SOCKET" display-message -p -t s2 "#{window_id}")"
sb_2="$(tmux -L "$SOCKET" split-window -P -F "#{pane_id}" -d -t "$win_2" -h -f -b -l 30 "sleep 100")"
tmux -L "$SOCKET" select-pane -t "$sb_2" -T "dotfiles-session-sidebar"
tmux -L "$SOCKET" set-option -p -q -t "$sb_2" @dotfiles_sidebar_pane 1

tmux -L "$SOCKET" new-session -d -s s3 -n work -x 120 -y 50 "sleep 100"
win_3="$(tmux -L "$SOCKET" display-message -p -t s3 "#{window_id}")"
sb_3="$(tmux -L "$SOCKET" split-window -P -F "#{pane_id}" -d -t "$win_3" -h -f -b -l 30 "sleep 100")"
tmux -L "$SOCKET" select-pane -t "$sb_3" -T "dotfiles-session-sidebar"
tmux -L "$SOCKET" set-option -p -q -t "$sb_3" @dotfiles_sidebar_pane 1

# Provision subpane in s1 with height 20
sub_p="$(provision_sidebar_subpane "$win_1" "$sb_1" 20 "")"
tmux -L "$SOCKET" set-option -g @dotfiles_sidebar_subpane_height 20
persist_sidebar_subpane_height 20
sidebar_subpane_swap_position "$win_1"

pos="$(sidebar_subpane_get_position)"
h1="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
s_top1="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_top}")"
l_top1="$(tmux -L "$SOCKET" display-message -p -t "$sb_1" "#{pane_top}")"

[ "$pos" = "top" ] || exit 1
[ "$h1" -eq 20 ] || exit 1
[ "$s_top1" -lt "$l_top1" ] || exit 1

# Switch to s2
sidebar_switch_execute_hot "" "s2" "$win_2" "$sb_2" "30" "$sub_p" "20"
h2="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
s_top2="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_top}")"
l_top2="$(tmux -L "$SOCKET" display-message -p -t "$sb_2" "#{pane_top}")"

[ "$h2" -eq 20 ] || { echo "FAIL: height decayed to $h2 in s2"; exit 1; }
[ "$s_top2" -lt "$l_top2" ] || { echo "FAIL: subpane not at top in s2"; exit 1; }

# Switch to s3
sidebar_switch_execute_hot "" "s3" "$win_3" "$sb_3" "30" "$sub_p" "20"
h3="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
s_top3="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_top}")"
l_top3="$(tmux -L "$SOCKET" display-message -p -t "$sb_3" "#{pane_top}")"

[ "$h3" -eq 20 ] || { echo "FAIL: height decayed to $h3 in s3"; exit 1; }
[ "$s_top3" -lt "$l_top3" ] || { echo "FAIL: subpane not at top in s3"; exit 1; }

# Toggle subpane OFF and ON in s3
destroy_sidebar_subpane "$win_3"
sub_p_reopen="$(provision_sidebar_subpane "$win_3" "$sb_3" 20 "")"
h3_reopen="$(tmux -L "$SOCKET" display-message -p -t "$sub_p_reopen" "#{pane_height}")"
s_top3_reopen="$(tmux -L "$SOCKET" display-message -p -t "$sub_p_reopen" "#{pane_top}")"
l_top3_reopen="$(tmux -L "$SOCKET" display-message -p -t "$sb_3" "#{pane_top}")"

[ "$h3_reopen" -eq 20 ] || { echo "FAIL: height is $h3_reopen after toggle, expected 20"; exit 1; }
[ "$s_top3_reopen" -lt "$l_top3_reopen" ] || { echo "FAIL: subpane not at top after toggle"; exit 1; }

# Switch back to s1
sidebar_switch_execute_hot "" "s1" "$win_1" "$sb_1" "30" "$sub_p_reopen" "20"
h1_final="$(tmux -L "$SOCKET" display-message -p -t "$sub_p_reopen" "#{pane_height}")"
s_top1_final="$(tmux -L "$SOCKET" display-message -p -t "$sub_p_reopen" "#{pane_top}")"
l_top1_final="$(tmux -L "$SOCKET" display-message -p -t "$sb_1" "#{pane_top}")"

[ "$h1_final" -eq 20 ] || { echo "FAIL: height decayed to $h1_final in s1"; exit 1; }
[ "$s_top1_final" -lt "$l_top1_final" ] || { echo "FAIL: subpane not at top in s1"; exit 1; }

echo "PASS: Top position subpane switches with ZERO height decay and exact position preservation!"
