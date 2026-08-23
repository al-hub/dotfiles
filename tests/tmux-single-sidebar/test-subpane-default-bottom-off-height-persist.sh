#!/usr/bin/env bash
# test-subpane-default-bottom-off-height-persist.sh
# Validates subpane constraints:
# 1. Default on fresh tmux boot: Always OFF (closed/hidden)
# 2. Default position on fresh tmux boot: Always bottom
# 3. Height-only persistence: Subpane height is preserved across cold server restarts and used on restore

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_SOCKET="subpane-bottom-off-test-$$"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"

tmuxc() {
    tmux -L "$TEST_SOCKET" "$@"
}

cleanup() {
    tmuxc kill-server >/dev/null 2>&1 || true
    rm -f "${STATE_DIR}/tmux-sidebar-subpane-height"
}
trap cleanup EXIT

export TMUX="$TEST_SOCKET"
source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_subpane_hub.sh"

echo "=== [1/4] Starting fresh tmux server and verifying Default OFF & Default Bottom ==="
tmuxc new-session -d -s "test-main" -x 120 -y 40 'sleep 60'
tmuxc set-option -gq '@dotfiles_sidebar_owner_client' "/dev/null"

win_id="$(tmuxc display-message -t "test-main:" -p '#{window_id}')"
provision_sidebar_window "$win_id" 35
launcher_pane="$(sidebar_window_pane "$win_id")"
[ -n "$launcher_pane" ] || { echo "FAIL: launcher pane missing"; exit 1; }

# Check subpane enabled status (Must be 0 / OFF)
sub_enabled="$(sidebar_subpane_get_enabled)"
if [ "$sub_enabled" != "0" ]; then
    echo "FAIL: Expected subpane to be OFF (0) by default, but got: $sub_enabled"
    exit 1
fi
echo "PASS: Subpane is OFF (0) by default on fresh server boot."

# Check subpane position (Must be bottom)
sub_pos="$(sidebar_subpane_get_position)"
if [ "$sub_pos" != "bottom" ]; then
    echo "FAIL: Expected subpane position to default to bottom, but got: $sub_pos"
    exit 1
fi
echo "PASS: Subpane position defaults to 'bottom'."

echo "=== [2/4] Setting custom subpane height (15), opening subpane, and verifying layout ==="
mkdir -p "$STATE_DIR"
persist_sidebar_subpane_height 15

# Toggle subpane ON
toggle_sidebar_subpane_global "$win_id"
sleep 0.3

sub_pane="$(sidebar_window_subpane "$win_id")"
if [ -z "$sub_pane" ]; then
    echo "FAIL: Subpane was not attached after toggle ON!"
    exit 1
fi

sub_h="$(tmuxc display-message -t "$sub_pane" -p '#{pane_height}')"
echo "Subpane attached with height: $sub_h"
if [ "$sub_h" -ne 15 ]; then
    echo "FAIL: Expected restored subpane height to be 15, got: $sub_h"
    exit 1
fi
echo "PASS: Subpane opened at bottom with restored height 15."

echo "=== [3/4] Resizing subpane to 18 and testing cold server restart ==="
tmuxc resize-pane -t "$sub_pane" -y 18
remember_sidebar_subpane_height_for_window "$win_id"

saved_h="$(read_persisted_sidebar_subpane_height || echo 0)"
if [ "$saved_h" -ne 18 ]; then
    echo "FAIL: Expected persisted height to be 18, got: $saved_h"
    exit 1
fi
echo "PASS: Resized height 18 was successfully persisted to disk."

# Kill tmux server completely (Cold Restart)
tmuxc kill-server
sleep 0.3

echo "=== [4/4] Starting NEW fresh tmux server and verifying cold boot invariants ==="
tmuxc new-session -d -s "test-restart" -x 120 -y 40 'sleep 60'
win_id2="$(tmuxc display-message -t "test-restart:" -p '#{window_id}')"
provision_sidebar_window "$win_id2" 35
launcher_pane2="$(sidebar_window_pane "$win_id2")"

# Invariant 1: Fresh boot must still be OFF
sub_enabled_fresh="$(sidebar_subpane_get_enabled)"
if [ "$sub_enabled_fresh" != "0" ]; then
    echo "FAIL: Fresh server boot after restart should be OFF (0), but got: $sub_enabled_fresh"
    exit 1
fi
echo "PASS: Cold restart correctly started with subpane OFF."

# Invariant 2: Position must still default to bottom
sub_pos_fresh="$(sidebar_subpane_get_position)"
if [ "$sub_pos_fresh" != "bottom" ]; then
    echo "FAIL: Cold restart position should default to bottom, but got: $sub_pos_fresh"
    exit 1
fi
echo "PASS: Cold restart correctly defaulted to 'bottom'."

# Invariant 3: Toggling ON restores height 18
toggle_sidebar_subpane_global "$win_id2"
sleep 0.3

sub_pane2="$(sidebar_window_subpane "$win_id2")"
if [ -z "$sub_pane2" ]; then
    echo "FAIL: Subpane was not attached on new server after toggle ON!"
    exit 1
fi

sub_h2="$(tmuxc display-message -t "$sub_pane2" -p '#{pane_height}')"
echo "Subpane attached on restarted server with height: $sub_h2"
if [ "$sub_h2" -ne 18 ]; then
    echo "FAIL: Expected subpane height after restart to restore persisted height 18, got: $sub_h2"
    exit 1
fi
echo "PASS: Subpane restored persisted height 18 on new server."

echo "=========================================================================="
echo "ALL INVARIANTS PASS: Subpane is default OFF, default Bottom, Height-Only Persisted!"
echo "=========================================================================="
