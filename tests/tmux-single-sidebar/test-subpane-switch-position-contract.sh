#!/usr/bin/env bash
set -euo pipefail
SOCKET="test-subpane-switch-pos-$$"
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
source "$SCRIPT_DIR/scripts/lib/sidebar_topology.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_switch.sh"

# 1. Setup isolated test socket, 2 sessions s1 and s2 (120x50)
tmux -L "$SOCKET" new-session -d -s s1 -n main -x 120 -y 50 'sleep 60'
win_s1="$(tmux -L "$SOCKET" display-message -p -t s1 '#{window_id}')"
launcher_s1="$(tmux -L "$SOCKET" split-window -P -F '#{pane_id}' -d -t "$win_s1" -h -f -b -l 30 'sleep 60')"
tmux -L "$SOCKET" select-pane -t "$launcher_s1" -T "dotfiles-session-sidebar"
tmux -L "$SOCKET" set-option -g @dotfiles_sidebar_subpane_height 12

tmux -L "$SOCKET" new-session -d -s s2 -n main -x 120 -y 50 'sleep 60'
win_s2="$(tmux -L "$SOCKET" display-message -p -t s2 '#{window_id}')"
launcher_s2="$(tmux -L "$SOCKET" split-window -P -F '#{pane_id}' -d -t "$win_s2" -h -f -b -l 30 'sleep 60')"
tmux -L "$SOCKET" select-pane -t "$launcher_s2" -T "dotfiles-session-sidebar"

# 2. Provisions subpane in s1 (default bottom, height 12)
sub_p="$(provision_sidebar_subpane "$win_s1" "$launcher_s1" 12 "")"
[ -n "$sub_p" ] || { echo "FAIL: could not provision subpane in s1"; exit 1; }

# 3. Switches subpane to "top" position via sidebar_subpane_swap_position
sidebar_subpane_swap_position "$win_s1"
pos="$(sidebar_subpane_get_position)"
[ "$pos" = "top" ] || { echo "FAIL: expected position 'top' in s1, got '$pos'"; exit 1; }

# Asserts subpane is at top in s1 (subpane_top < launcher_top, height=12)
sub_h="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" '#{pane_height}')"
l_top="$(tmux -L "$SOCKET" display-message -p -t "$launcher_s1" '#{pane_top}')"
s_top="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" '#{pane_top}')"

[ "$s_top" -lt "$l_top" ] || { echo "FAIL: expected subpane top ($s_top) < launcher top ($l_top) in s1"; exit 1; }
[ "$sub_h" -eq 12 ] || { echo "FAIL: expected subpane height 12 in s1, got $sub_h"; exit 1; }
echo "PASS: s1 subpane positioned at top (s_top=$s_top < l_top=$l_top, h=$sub_h)"

# 4. Calls sidebar_switch_execute_hot to switch to s2
sidebar_switch_execute_hot "" "s2" "$win_s2" "$launcher_s2" "30" "$sub_p" "12"

# CRITICAL ASSERTION: In s2, subpane is STILL at top (subpane_top < launcher_top, height=12, launcher_top > subpane_top)
sub_h="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" '#{pane_height}')"
l_top="$(tmux -L "$SOCKET" display-message -p -t "$launcher_s2" '#{pane_top}')"
s_top="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" '#{pane_top}')"

[ "$s_top" -lt "$l_top" ] || { echo "FAIL: CRITICAL ASSERTION FAILED: expected subpane top ($s_top) < launcher top ($l_top) after switch to s2"; exit 1; }
[ "$l_top" -gt "$s_top" ] || { echo "FAIL: CRITICAL ASSERTION FAILED: expected launcher top ($l_top) > subpane top ($s_top) in s2"; exit 1; }
[ "$sub_h" -eq 12 ] || { echo "FAIL: expected subpane height 12 after switch to s2, got $sub_h"; exit 1; }
echo "PASS: s2 subpane preserved at top after hot switch (s_top=$s_top < l_top=$l_top, h=$sub_h)"

# 5. Switches subpane to "bottom" position via sidebar_subpane_swap_position
sidebar_subpane_swap_position "$win_s2"
pos="$(sidebar_subpane_get_position)"
[ "$pos" = "bottom" ] || { echo "FAIL: expected position 'bottom' in s2, got '$pos'"; exit 1; }

# 6. Calls sidebar_switch_execute_hot to switch back to s1
sidebar_switch_execute_hot "" "s1" "$win_s1" "$launcher_s1" "30" "$sub_p" "12"

# CRITICAL ASSERTION: In s1, subpane is at bottom (subpane_top > launcher_top, height=12)
sub_h="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" '#{pane_height}')"
l_top="$(tmux -L "$SOCKET" display-message -p -t "$launcher_s1" '#{pane_top}')"
s_top="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" '#{pane_top}')"

[ "$s_top" -gt "$l_top" ] || { echo "FAIL: CRITICAL ASSERTION FAILED: expected subpane top ($s_top) > launcher top ($l_top) after switch back to s1"; exit 1; }
[ "$sub_h" -eq 12 ] || { echo "FAIL: expected subpane height 12 after switch to s1, got $sub_h"; exit 1; }
echo "PASS: s1 subpane preserved at bottom after hot switch (s_top=$s_top > l_top=$l_top, h=$sub_h)"

echo "ALL SUBPANE SWITCH POSITION CONTRACT TESTS PASSED!"
