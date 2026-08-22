#!/usr/bin/env bash
set -euo pipefail
SOCKET="test-subpane-pos-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

STATE_DIR="$(mktemp -d /tmp/test-subpane-pos-state.XXXXXX)"
export TMUX_SESSION_SIDEBAR_SUBPANE_HEIGHT_STATE_FILE="$STATE_DIR/height"
export TMUX_SESSION_SIDEBAR_SUBPANE_POSITION_STATE_FILE="$STATE_DIR/pos"

cleanup() {
    tmux -L "$SOCKET" kill-server 2>/dev/null || true
    rm -rf "$STATE_DIR"
}
trap cleanup EXIT

export TMUX="$SOCKET"
source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_subpane_hub.sh"

# 1. Setup session and provision launcher pane (height=50, width=120)
tmux -L "$SOCKET" new-session -d -s work-session -n main -x 120 -y 50 'sleep 60'
win_id="$(tmux -L "$SOCKET" display-message -p -t work-session '#{window_id}')"
work_p1="$(tmux -L "$SOCKET" display-message -p -t work-session '#{pane_id}')"
launcher_p="$(tmux -L "$SOCKET" split-window -P -F '#{pane_id}' -d -t "$win_id" -h -f -b -l 30 'sleep 60')"
tmux -L "$SOCKET" select-pane -t "$launcher_p" -T "dotfiles-session-sidebar"
tmux -L "$SOCKET" set-option -g @dotfiles_sidebar_subpane_height 12

# 2. Provision subpane (default: bottom, height 12)
sub_p="$(provision_sidebar_subpane "$win_id" "$launcher_p" 12 "")"
[ -n "$sub_p" ] || { echo "FAIL: could not provision subpane"; exit 1; }

# Verify initial heights: subpane height is 12, launcher height is ~36, launcher top < subpane top
sub_h="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" '#{pane_height}')"
launcher_h="$(tmux -L "$SOCKET" display-message -p -t "$launcher_p" '#{pane_height}')"
l_top="$(tmux -L "$SOCKET" display-message -p -t "$launcher_p" '#{pane_top}')"
s_top="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" '#{pane_top}')"

[ "$sub_h" -eq 12 ] || { echo "FAIL: expected subpane initial height 12, got $sub_h"; exit 1; }
[ "$launcher_h" -ge 35 ] && [ "$launcher_h" -le 38 ] || { echo "FAIL: expected launcher initial height ~36, got $launcher_h"; exit 1; }
[ "$s_top" -gt "$l_top" ] || { echo "FAIL: expected subpane top ($s_top) > launcher top ($l_top) by default"; exit 1; }
echo "PASS: initial layout verified (subpane bottom, h=$sub_h; launcher top, h=$launcher_h)"

# 3. Swap subpane position to top
sidebar_subpane_swap_position "$win_id"
pos="$(sidebar_subpane_get_position)"
[ "$pos" = "top" ] || { echo "FAIL: expected position 'top', got '$pos'"; exit 1; }

sub_h="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" '#{pane_height}')"
launcher_h="$(tmux -L "$SOCKET" display-message -p -t "$launcher_p" '#{pane_height}')"
l_top="$(tmux -L "$SOCKET" display-message -p -t "$launcher_p" '#{pane_top}')"
s_top="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" '#{pane_top}')"

[ "$s_top" -lt "$l_top" ] || { echo "FAIL: expected subpane top ($s_top) < launcher top ($l_top) after swap to top"; exit 1; }
[ "$sub_h" -eq 12 ] || { echo "FAIL: CRITICAL ASSERTION FAILED: expected subpane height EXACTLY 12 after swap to top, got $sub_h (launcher=$launcher_h)"; exit 1; }
[ "$launcher_h" -ge 35 ] && [ "$launcher_h" -le 38 ] || { echo "FAIL: expected launcher height ~36 after swap to top, got $launcher_h"; exit 1; }
echo "PASS: swapped to top position with dimension integrity preserved (subpane top, h=$sub_h; launcher bottom, h=$launcher_h)"

# 4. Swap back to bottom
sidebar_subpane_swap_position "$win_id"
pos="$(sidebar_subpane_get_position)"
[ "$pos" = "bottom" ] || { echo "FAIL: expected position 'bottom', got '$pos'"; exit 1; }

sub_h="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" '#{pane_height}')"
launcher_h="$(tmux -L "$SOCKET" display-message -p -t "$launcher_p" '#{pane_height}')"
l_top="$(tmux -L "$SOCKET" display-message -p -t "$launcher_p" '#{pane_top}')"
s_top="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" '#{pane_top}')"

[ "$s_top" -gt "$l_top" ] || { echo "FAIL: expected subpane top ($s_top) > launcher top ($l_top) after swap to bottom"; exit 1; }
[ "$sub_h" -eq 12 ] || { echo "FAIL: CRITICAL ASSERTION FAILED: expected subpane height EXACTLY 12 after swap to bottom, got $sub_h (launcher=$launcher_h)"; exit 1; }
[ "$launcher_h" -ge 35 ] && [ "$launcher_h" -le 38 ] || { echo "FAIL: expected launcher height ~36 after swap to bottom, got $launcher_h"; exit 1; }
echo "PASS: swapped back to bottom position with dimension integrity preserved (subpane bottom, h=$sub_h; launcher top, h=$launcher_h)"

# 5. Test work pane isolation
work_p2="$(tmux -L "$SOCKET" split-window -P -F '#{pane_id}' -d -t "$work_p1" -v 'sleep 60')"
pos_before="$(sidebar_subpane_get_position)"
tmux -L "$SOCKET" swap-pane -d -s "$work_p1" -t "$work_p2"
pos_after="$(sidebar_subpane_get_position)"
[ "$pos_after" = "$pos_before" ] || { echo "FAIL: work pane swap mutated subpane position from $pos_before to $pos_after"; exit 1; }

sidebar_subpane_swap_position "$win_id"
pos_before="$(sidebar_subpane_get_position)"
[ "$pos_before" = "top" ] || { echo "FAIL: expected pos to be top before work swap"; exit 1; }
tmux -L "$SOCKET" swap-pane -d -s "$work_p1" -t "$work_p2"
pos_after="$(sidebar_subpane_get_position)"
[ "$pos_after" = "top" ] || { echo "FAIL: work pane swap mutated subpane position from top to $pos_after"; exit 1; }
echo "PASS: work pane isolation verified (work pane swaps do not mutate subpane position)"

echo "ALL SUBPANE POSITION CONTRACT TESTS PASSED!"
