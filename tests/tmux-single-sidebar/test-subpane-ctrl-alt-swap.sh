#!/usr/bin/env bash
set -euo pipefail
SOCKET="test-subpane-ctrl-alt-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

STATE_DIR="$(mktemp -d /tmp/test-ctrl-alt.XXXXXX)"

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

# 3. Simulate Ctrl+Alt+Up (swap-pane inside window)
tmux -L "$SOCKET" swap-pane -d -s "$launcher_p" -t "$sub_p"

# 4. Sync position detection
sync_sidebar_subpane_position_for_window "$win_id"
pos="$(sidebar_subpane_get_position)"
[ "$pos" = "top" ] || { echo "FAIL: expected position 'top' after swap-pane, got '$pos'"; exit 1; }
echo "PASS: auto-detected position 'top' after Ctrl+Alt+Up swap"

# 5. Swap back
tmux -L "$SOCKET" swap-pane -d -s "$launcher_p" -t "$sub_p"
sync_sidebar_subpane_position_for_window "$win_id"
pos2="$(sidebar_subpane_get_position)"
[ "$pos2" = "bottom" ] || { echo "FAIL: expected position 'bottom' after swap back, got '$pos2'"; exit 1; }
echo "PASS: auto-detected position 'bottom' after Ctrl+Alt+Down swap"

echo "ALL SUBPANE CTRL-ALT SWAP TESTS PASSED!"
