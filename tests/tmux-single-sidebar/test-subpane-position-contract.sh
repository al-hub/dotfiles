#!/usr/bin/env bash
set -euo pipefail
SOCKET="test-subpane-pos-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cleanup() { tmux -L "$SOCKET" kill-server 2>/dev/null || true; }
trap cleanup EXIT

export TMUX="$SOCKET"
source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_subpane_hub.sh"

# 1. Setup session and provision launcher pane
tmux -L "$SOCKET" new-session -d -s work-session -n main -x 120 -y 50 'sleep 60'
win_id="$(tmux -L "$SOCKET" display-message -p -t work-session '#{window_id}')"
launcher_p="$(tmux -L "$SOCKET" split-window -P -F '#{pane_id}' -d -t "$win_id" -h -f -b -l 30 'sleep 60')"
tmux -L "$SOCKET" select-pane -t "$launcher_p" -T "dotfiles-session-sidebar"

# 2. Provision subpane (default: bottom)
sub_p="$(provision_sidebar_subpane "$win_id" "$launcher_p" "" "")"
[ -n "$sub_p" ] || { echo "FAIL: could not provision subpane"; exit 1; }

l_top="$(tmux -L "$SOCKET" display-message -p -t "$launcher_p" '#{pane_top}')"
s_top="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" '#{pane_top}')"
[ "$s_top" -gt "$l_top" ] || { echo "FAIL: expected subpane top ($s_top) > launcher top ($l_top) by default"; exit 1; }
echo "PASS: default position is bottom"

# 3. Swap subpane position to top
sidebar_subpane_swap_position "$win_id"
pos="$(sidebar_subpane_get_position)"
[ "$pos" = "top" ] || { echo "FAIL: expected position 'top', got '$pos'"; exit 1; }

l_top="$(tmux -L "$SOCKET" display-message -p -t "$launcher_p" '#{pane_top}')"
s_top="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" '#{pane_top}')"
[ "$s_top" -lt "$l_top" ] || { echo "FAIL: expected subpane top ($s_top) < launcher top ($l_top) after swap to top"; exit 1; }
echo "PASS: swapped to top position in live window"

# 4. Release/destroy subpane and re-provision in another window
destroy_sidebar_subpane "$win_id"
tmux -L "$SOCKET" new-window -d -t work-session -n win2 'sleep 60'
win2_id="$(tmux -L "$SOCKET" display-message -p -t work-session:1 '#{window_id}')"
launcher_p2="$(tmux -L "$SOCKET" split-window -P -F '#{pane_id}' -d -t "$win2_id" -h -f -b -l 30 'sleep 60')"
tmux -L "$SOCKET" select-pane -t "$launcher_p2" -T "dotfiles-session-sidebar"

sub_p2="$(provision_sidebar_subpane "$win2_id" "$launcher_p2" "" "")"
[ -n "$sub_p2" ] || { echo "FAIL: could not re-provision subpane in win2"; exit 1; }

l2_top="$(tmux -L "$SOCKET" display-message -p -t "$launcher_p2" '#{pane_top}')"
s2_top="$(tmux -L "$SOCKET" display-message -p -t "$sub_p2" '#{pane_top}')"
[ "$s2_top" -lt "$l2_top" ] || { echo "FAIL: expected subpane top ($s2_top) < launcher top ($l2_top) in win2"; exit 1; }
echo "PASS: preserved top position across windows and re-provision"

# 5. Swap back to bottom
sidebar_subpane_swap_position "$win2_id"
pos2="$(sidebar_subpane_get_position)"
[ "$pos2" = "bottom" ] || { echo "FAIL: expected position 'bottom', got '$pos2'"; exit 1; }

l2_top="$(tmux -L "$SOCKET" display-message -p -t "$launcher_p2" '#{pane_top}')"
s2_top="$(tmux -L "$SOCKET" display-message -p -t "$sub_p2" '#{pane_top}')"
[ "$s2_top" -gt "$l2_top" ] || { echo "FAIL: expected subpane top ($s2_top) > launcher top ($l2_top) after swap back"; exit 1; }
echo "PASS: swapped back to bottom position"

echo "ALL SUBPANE POSITION CONTRACT TESTS PASSED!"
