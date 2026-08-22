#!/usr/bin/env bash
set -euo pipefail

# Test Scenario: Verifies that Candidate A + Candidate B preserves manual mouse resize during rapid session switch
# and restores canonical intent when switching across heterogeneous window dimensions.

SOCKET="test-mouse-detect-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="$(mktemp -d /tmp/test-mouse-detect.XXXXXX)"

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

# 1. Setup 2 large sessions (50 rows) and 1 small session (24 rows)
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

tmux -L "$SOCKET" new-session -d -s sess_small -n work -x 120 -y 24 "sleep 100"
win_small="$(tmux -L "$SOCKET" display-message -p -t sess_small "#{window_id}")"
sb_small="$(tmux -L "$SOCKET" split-window -P -F "#{pane_id}" -d -t "$win_small" -h -f -b -l 30 "sleep 100")"
tmux -L "$SOCKET" select-pane -t "$sb_small" -T "dotfiles-session-sidebar"
tmux -L "$SOCKET" set-option -p -q -t "$sb_small" @dotfiles_sidebar_pane 1

source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_subpane_hub.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_topology.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_switch.sh"

# Initial state: subpane in sess_1 with default height 12
sub_p="$(provision_sidebar_subpane "$win_1" "$sb_1" 12 "")"
tmux -L "$SOCKET" set-option -g @dotfiles_sidebar_subpane_height 12
persist_sidebar_subpane_height 12

echo "=== Initial State: Subpane height is 12 ==="
echo "Option height: $(tmux -L "$SOCKET" show-option -gqv @dotfiles_sidebar_subpane_height)"
echo "Live height: $(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"

# -------------------------------------------------------------------------
# Test Part 1 (Candidate A): Rapid Mouse Resize followed by Enter Switch
# -------------------------------------------------------------------------
echo "--- Test Part 1: User drags mouse to resize subpane to 28 in sess_1 ---"
# Simulate physical mouse drag directly in the active window
tmux -L "$SOCKET" resize-pane -t "$sub_p" -y 28

# User immediately hits Enter before async hook subshell can execute
# switch_session executes sync_attached_subpane_user_intent:
synced_intent="$(sync_attached_subpane_user_intent "" "$win_1")"
echo "Synced intent promoted by switch_session: $synced_intent (Expected: 28)"

# Execute switch to sess_2
sidebar_switch_execute_hot "" "sess_2" "$win_2" "$sb_2" "30" "$sub_p" "$synced_intent"
h_in_sess_2="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
echo "Live height in sess_2 after switch: $h_in_sess_2"

if [ "$h_in_sess_2" -ne 28 ]; then
    echo "❌ DEFECT: User manual resize to 28 was lost and reverted to $h_in_sess_2!"
    exit 1
fi
echo "✅ Part 1 Passed: Manual resize (28) was 100% preserved in target session."

# -------------------------------------------------------------------------
# Test Part 2 (Candidate B): Switching Through Heterogeneous Dimensions
# -------------------------------------------------------------------------
echo "--- Test Part 2: Switch through small window (24 rows) and return to 50 rows ---"
# Switch into sess_small (which has 24 rows, so max subpane is 18 rows)
current_intent="$(tmux -L "$SOCKET" show-option -gqv @dotfiles_sidebar_subpane_height)"
echo "Intent before entering small session: $current_intent"
sidebar_switch_execute_hot "" "sess_small" "$win_small" "$sb_small" "30" "$sub_p" "$current_intent"
h_in_small="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
echo "Clamped height rendered in sess_small: $h_in_small"

# Now switch back to sess_1 (which has 50 rows)
# The canonical intent must NOT have been permanently crushed to h_in_small!
intent_after_small="$(tmux -L "$SOCKET" show-option -gqv @dotfiles_sidebar_subpane_height)"
echo "Intent after exiting small session: $intent_after_small"
sidebar_switch_execute_hot "" "sess_1" "$win_1" "$sb_1" "30" "$sub_p" "$intent_after_small"
h_in_sess_1_restored="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
echo "Restored height in sess_1: $h_in_sess_1_restored (Expected: 28)"

if [ "$h_in_sess_1_restored" -ne 28 ]; then
    echo "❌ DEFECT: Clamped small dimension crushed canonical intent to $h_in_sess_1_restored!"
    exit 1
fi

echo "✅ Part 2 Passed: Canonical intent restored to 28."
echo "✅ ALL DETECTION TESTS PASSED (100% GREEN)."
