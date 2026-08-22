#!/usr/bin/env bash
set -euo pipefail

# Test Scenario: Verifies that rapid, repeated 'P' key swaps (e.g. 20 consecutive swaps)
# preserve the subpane height with 100% fidelity without any decay or drift.

SOCKET="test-p-rapid-loop-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="$(mktemp -d /tmp/test-p-loop.XXXXXX)"

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

# 1. Setup 50-row window
tmux -L "$SOCKET" new-session -d -s work -n main -x 120 -y 50 "sleep 100"
win_id="$(tmux -L "$SOCKET" display-message -p -t work "#{window_id}")"
launcher_p="$(tmux -L "$SOCKET" split-window -P -F "#{pane_id}" -d -t "$win_id" -h -f -b -l 30 "sleep 100")"
tmux -L "$SOCKET" select-pane -t "$launcher_p" -T "dotfiles-session-sidebar"
tmux -L "$SOCKET" set-option -p -q -t "$launcher_p" @dotfiles_sidebar_pane 1
tmux -L "$SOCKET" set-option -g @dotfiles_sidebar_enabled 1
tmux -L "$SOCKET" set-option -wq -t "$win_id" @dotfiles_sidebar_ready 1

source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_subpane_hub.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_topology.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_switch.sh"

# Initial state: subpane at bottom with height 25
sub_p="$(provision_sidebar_subpane "$win_id" "$launcher_p" 25 "")"
tmux -L "$SOCKET" set-option -g @dotfiles_sidebar_subpane_height 25
persist_sidebar_subpane_height 25

echo "=== Initial: Bottom, Height = 25 ==="

# Test Loop 1: 20 consecutive P key swaps at height 25
for i in $(seq 1 20); do
    sidebar_subpane_swap_position "$win_id"
    pos="$(sidebar_subpane_get_position)"
    h_live="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
    h_opt="$(tmux -L "$SOCKET" show-option -gqv @dotfiles_sidebar_subpane_height)"

    if [ $((i % 2)) -eq 1 ]; then
        expected_pos="top"
    else
        expected_pos="bottom"
    fi

    if [ "$pos" != "$expected_pos" ]; then
        echo "FAIL (Swap $i): Expected position $expected_pos, got $pos"
        exit 1
    fi

    if [ "$h_live" -ne 25 ] || [ "$h_opt" -ne 25 ]; then
        echo "FAIL (Swap $i): Height decayed! Live=$h_live, Opt=$h_opt (Expected: 25)"
        exit 1
    fi
done
echo "PASS: 20 consecutive P key swaps at height 25 maintained exact height 25!"

# Test Loop 2: Resize to 17, then 20 consecutive P key swaps at height 17
tmux -L "$SOCKET" resize-pane -t "$sub_p" -y 17
remember_sidebar_subpane_height_for_window "$win_id"

for i in $(seq 1 20); do
    sidebar_subpane_swap_position "$win_id"
    pos="$(sidebar_subpane_get_position)"
    h_live="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
    h_opt="$(tmux -L "$SOCKET" show-option -gqv @dotfiles_sidebar_subpane_height)"

    if [ "$h_live" -ne 17 ] || [ "$h_opt" -ne 17 ]; then
        echo "FAIL (Swap $i at 17): Height decayed! Live=$h_live, Opt=$h_opt (Expected: 17)"
        exit 1
    fi
done
echo "PASS: 20 consecutive P key swaps at height 17 maintained exact height 17!"
echo "ALL RAPID P KEY LOOP TESTS PASSED (40/40 SWAPS 100% GREEN)!"
