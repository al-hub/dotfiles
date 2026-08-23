#!/usr/bin/env bash
set -euo pipefail

# Test Scenario: Verifies that when a user manually resizes the subpane via mouse drag (e.g. to 28)
# and immediately switches session (Enter), the user's latest manual resize is 100% preserved.

SOCKET="test-mouse-resize-fidelity-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="$(mktemp -d /tmp/test-mouse-res-fid.XXXXXX)"

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

# 1. Setup 2 sessions
tmux -L "$SOCKET" new-session -d -s sess_1 -n work -x 120 -y 50 "sleep 100"
win_1="$(tmux -L "$SOCKET" display-message -p -t sess_1 "#{window_id}")"

tmux -L "$SOCKET" new-session -d -s sess_2 -n work -x 120 -y 50 "sleep 100"
win_2="$(tmux -L "$SOCKET" display-message -p -t sess_2 "#{window_id}")"

# Step 1: Open sidebar and subpane on sess_1 (default 12)
bash "$SCRIPT_DIR/dist/tmux-session-launcher" --ensure-sidebar-window "$win_1"
bash "$SCRIPT_DIR/dist/tmux-session-launcher" --toggle-subpane "$win_1"

source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_subpane_hub.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_topology.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_switch.sh"

sub_p="$(sidebar_window_subpane "$win_1" || true)"
[ -n "$sub_p" ] || { echo "FAIL: subpane not found in win_1"; exit 1; }

echo "=== Initial: subpane height = $(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}") ==="

# Step 2: User manually resizes subpane to 28 via mouse drag
echo "--- Simulating User Mouse Drag to 28 ---"
tmux -L "$SOCKET" resize-pane -t "$sub_p" -y 28

# Allow async tmux hook (run-shell -b) to update option
for i in {1..20}; do
    h_opt="$(tmux -L "$SOCKET" show-option -gqv @dotfiles_sidebar_subpane_height 2>/dev/null || true)"
    [ "$h_opt" = "28" ] && break
    sleep 0.05
done

# Step 3: User immediately switches to sess_2 (Enter in launcher)
echo "--- Simulating Immediate Session Switch to sess_2 ---"
bash "$SCRIPT_DIR/dist/tmux-session-launcher" --ensure-sidebar-window "$win_2"
sb_2="$(sidebar_window_pane "$win_2" || true)"

# Execute switch without relying on async hook race
h_before_switch="$(tmux -L "$SOCKET" show-option -gqv @dotfiles_sidebar_subpane_height)"
echo "Option height before switch execution: $h_before_switch"

# switch_session simulation
sidebar_switch_execute_hot "" "sess_2" "$win_2" "$sb_2" "30" "$sub_p" "$h_before_switch"

h_after_switch="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
echo "Height in sess_2 after switch: $h_after_switch (Expected: 28)"

if [ "$h_after_switch" -ne 28 ]; then
    echo "❌ DEFECT DETECTED: Manual resize (28) was lost and reset to ($h_after_switch)!"
    exit 1
else
    echo "✅ PASS: Manual resize (28) was 100% preserved in target session."
    exit 0
fi
