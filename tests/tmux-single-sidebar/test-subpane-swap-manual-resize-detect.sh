#!/usr/bin/env bash
set -euo pipefail

# Test Scenario: Detects failure to preserve manual mouse resize when pressing 'p' to swap subpane position.
# Verifies that after manual mouse resize to 26, pressing 'p' (swap position) preserves height=26,
# and after another resize to 22 and pressing 'p' again, height=22 is preserved.

SOCKET="test-p-swap-detect-$$"
SCRIPT_DIR="$(pwd)"
STATE_DIR="$(mktemp -d /tmp/test-p-swap-detect.XXXXXX)"

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

# 1. Setup session with 50 rows
tmux -L "$SOCKET" new-session -d -s work -n main -x 120 -y 50 "sleep 100"
win_id="$(tmux -L "$SOCKET" display-message -p -t work "#{window_id}")"
launcher_p="$(tmux -L "$SOCKET" split-window -P -F "#{pane_id}" -d -t "$win_id" -h -f -b -l 30 "sleep 100")"
tmux -L "$SOCKET" select-pane -t "$launcher_p" -T "dotfiles-session-sidebar"
tmux -L "$SOCKET" set-option -p -q -t "$launcher_p" @dotfiles_sidebar_pane 1
tmux -L "$SOCKET" set-option -g @dotfiles_sidebar_enabled 1
tmux -L "$SOCKET" set-option -wq -t "$win_id" @dotfiles_sidebar_ready 1
tmux -L "$SOCKET" set-option -wq -t "$win_id" @dotfiles_sidebar_window_ready 1

source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_subpane_hub.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_topology.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_switch.sh"

# Initial state: subpane in work session at BOTTOM with height 12
sub_p="$(provision_sidebar_subpane "$win_id" "$launcher_p" 12 "")"
tmux -L "$SOCKET" set-option -g @dotfiles_sidebar_subpane_height 12
persist_sidebar_subpane_height 12
sleep 0.6

echo "=== Initial State: Subpane at BOTTOM with height 12 ==="
echo "Option height: $(tmux -L "$SOCKET" show-option -gqv @dotfiles_sidebar_subpane_height)"
echo "Live height: $(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"

# -------------------------------------------------------------------------
# Test Step 1: User drags mouse to resize subpane to 26 in work session
# -------------------------------------------------------------------------
echo "--- Step 1: User drags mouse to resize subpane to 26 ---"
tmux -L "$SOCKET" resize-pane -t "$sub_p" -y 26

# Simulate after-resize-pane hook invocation (sync_sidebar_layout manual-resize)
bash "$SCRIPT_DIR/dist/tmux-session-launcher" --sync-sidebar-layout "$win_id" "manual-resize"

opt_after_hook="$(tmux -L "$SOCKET" show-option -gqv @dotfiles_sidebar_subpane_height)"
echo "Option height after manual-resize hook: $opt_after_hook (Expected: 26 if synced, Actual: $opt_after_hook)"

if [ "$opt_after_hook" -ne 26 ]; then
    echo "❌ DEFECT DETECTED in Hook: manual-resize hook failed to persist subpane height (26) to @dotfiles_sidebar_subpane_height (got $opt_after_hook)!"
    exit 1
fi
echo "✅ Step 1 Passed: manual-resize hook persisted 26."

# -------------------------------------------------------------------------
# Test Step 2: User presses 'p' to swap position to TOP
# -------------------------------------------------------------------------
echo "--- Step 2: User presses 'p' to swap position to TOP ---"
sidebar_subpane_swap_position "$win_id"

h_top="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
opt_top="$(tmux -L "$SOCKET" show-option -gqv @dotfiles_sidebar_subpane_height)"
pos_top="$(sidebar_subpane_get_position)"
echo "After Swap to TOP: Pos=$pos_top, Live=$h_top, Option=$opt_top"

if [ "$h_top" -ne 26 ]; then
    echo "❌ DEFECT DETECTED in Swap: Manual resize to 26 was destroyed after 'p' swap (got $h_top)!"
    exit 1
fi

echo "✅ Step 2 Passed: Height 26 preserved after swap to TOP."

# -------------------------------------------------------------------------
# Test Step 3: User resizes top subpane to 22 and presses 'p' back to BOTTOM
# -------------------------------------------------------------------------
echo "--- Step 3: User resizes top subpane to 22 and presses 'p' back to BOTTOM ---"
sleep 0.6
tmux -L "$SOCKET" resize-pane -t "$sub_p" -y "$(sidebar_subpane_calc_resize_length "top" 22)"
bash "$SCRIPT_DIR/dist/tmux-session-launcher" --sync-sidebar-layout "$win_id" "manual-resize"

sidebar_subpane_swap_position "$win_id"

h_bot="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
opt_bot="$(tmux -L "$SOCKET" show-option -gqv @dotfiles_sidebar_subpane_height)"
pos_bot="$(sidebar_subpane_get_position)"
echo "After Swap to BOTTOM: Pos=$pos_bot, Live=$h_bot, Option=$opt_bot"

if [ "$h_bot" -ne 22 ]; then
    echo "❌ DEFECT DETECTED in Swap 2: Manual resize to 22 was destroyed after swap back (got $h_bot)!"
    exit 1
fi

echo "✅ ALL DETECTION TESTS PASSED (100% GREEN)."
