#!/usr/bin/env bash
set -euo pipefail

SOCKET="test-swap-switch-immediate-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="$(mktemp -d /tmp/test-swap-switch-imm.XXXXXX)"

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

# 1. Setup 3 sessions
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

# 2. Provision subpane in s1 at bottom with height 18
sub_p="$(provision_sidebar_subpane "$win_1" "$sb_1" 18 "")"
tmux -L "$SOCKET" set-option -g @dotfiles_sidebar_subpane_height 18
persist_sidebar_subpane_height 18

h_start="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
[ "$h_start" -eq 18 ] || exit 1

# 3. User swaps position to top in s1
sidebar_subpane_swap_position "$win_1"
h_swapped="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
pos_swapped="$(sidebar_subpane_get_position)"
s_top_swapped="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_top}")"
l_top_swapped="$(tmux -L "$SOCKET" display-message -p -t "$sb_1" "#{pane_top}")"

[ "$pos_swapped" = "top" ] || exit 1
[ "$h_swapped" -eq 18 ] || exit 1
[ "$s_top_swapped" -lt "$l_top_swapped" ] || exit 1

# 4. Immediately switch to s2 (Enter)
sidebar_switch_execute_hot "" "s2" "$win_2" "$sb_2" "30" "$sub_p" "18"
h_s2="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
s_top_s2="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_top}")"
l_top_s2="$(tmux -L "$SOCKET" display-message -p -t "$sb_2" "#{pane_top}")"

[ "$h_s2" -eq 18 ] || { echo "FAIL: height decayed to $h_s2 in s2"; exit 1; }
[ "$s_top_s2" -lt "$l_top_s2" ] || { echo "FAIL: subpane not at top in s2"; exit 1; }

# 5. Immediately switch to s3 (Enter)
sidebar_switch_execute_hot "" "s3" "$win_3" "$sb_3" "30" "$sub_p" "18"
h_s3="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
s_top_s3="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_top}")"
l_top_s3="$(tmux -L "$SOCKET" display-message -p -t "$sb_3" "#{pane_top}")"

[ "$h_s3" -eq 18 ] || { echo "FAIL: height decayed to $h_s3 in s3"; exit 1; }
[ "$s_top_s3" -lt "$l_top_s3" ] || { echo "FAIL: subpane not at top in s3"; exit 1; }

# 6. Toggle subpane OFF and ON in s3
destroy_sidebar_subpane "$win_3"
sub_p_re="$(provision_sidebar_subpane "$win_3" "$sb_3" 18 "")"
h_s3_re="$(tmux -L "$SOCKET" display-message -p -t "$sub_p_re" "#{pane_height}")"
s_top_s3_re="$(tmux -L "$SOCKET" display-message -p -t "$sub_p_re" "#{pane_top}")"
l_top_s3_re="$(tmux -L "$SOCKET" display-message -p -t "$sb_3" "#{pane_top}")"

[ "$h_s3_re" -eq 18 ] || { echo "FAIL: height changed to $h_s3_re after toggle"; exit 1; }
[ "$s_top_s3_re" -lt "$l_top_s3_re" ] || { echo "FAIL: subpane not at top after toggle"; exit 1; }

# 7. Switch back to s1
sidebar_switch_execute_hot "" "s1" "$win_1" "$sb_1" "30" "$sub_p_re" "18"
h_s1_final="$(tmux -L "$SOCKET" display-message -p -t "$sub_p_re" "#{pane_height}")"
s_top_s1_final="$(tmux -L "$SOCKET" display-message -p -t "$sub_p_re" "#{pane_top}")"
l_top_s1_final="$(tmux -L "$SOCKET" display-message -p -t "$sb_1" "#{pane_top}")"

[ "$h_s1_final" -eq 18 ] || { echo "FAIL: height decayed to $h_s1_final in s1"; exit 1; }
[ "$s_top_s1_final" -lt "$l_top_s1_final" ] || { echo "FAIL: subpane not at top in s1"; exit 1; }

echo "PASS: Swap to top immediately followed by rapid switches and toggles preserves 100% geometry!"
