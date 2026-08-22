#!/usr/bin/env bash
set -euo pipefail
SOCKET="test-subpane-height-$$"
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

# 2. Provision subpane without explicit height (should use default)
sub_p="$(provision_sidebar_subpane "$win_id" "$launcher_p" "" "")"
[ -n "$sub_p" ] || { echo "FAIL: could not provision subpane"; exit 1; }

# 3. Manually resize subpane to 18 lines (simulating mouse drag)
tmux -L "$SOCKET" resize-pane -t "$sub_p" -y 18
actual_h="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" '#{pane_height}')"
[ "$actual_h" -eq 18 ] || { echo "FAIL: resize-pane failed, got $actual_h"; exit 1; }

# 4. Destroy subpane directly (should automatically capture and save height 18)
destroy_sidebar_subpane "$win_id"
saved_opt="$(tmux -L "$SOCKET" show-option -gqv @dotfiles_sidebar_subpane_height 2>/dev/null || echo 0)"
[ "$saved_opt" = "18" ] || { echo "FAIL: expected saved option 18 on destroy, got $saved_opt"; exit 1; }

# 5. Re-provision subpane without passing height (should reuse saved 18)
sub_p2="$(provision_sidebar_subpane "$win_id" "$launcher_p" "" "")"
[ -n "$sub_p2" ] || { echo "FAIL: could not re-provision subpane"; exit 1; }
recreated_h="$(tmux -L "$SOCKET" display-message -p -t "$sub_p2" '#{pane_height}')"
[ "$recreated_h" -eq 18 ] || { echo "FAIL: expected re-provisioned height 18, got $recreated_h"; exit 1; }

# 6. Test with top position and resize to 22
sidebar_subpane_set_position "top"
tmux -L "$SOCKET" resize-pane -t "$sub_p2" -y 22
actual_h2="$(tmux -L "$SOCKET" display-message -p -t "$sub_p2" '#{pane_height}')"
[ "$actual_h2" -eq 22 ] || { echo "FAIL: resize-pane to 22 failed, got $actual_h2"; exit 1; }

destroy_sidebar_subpane "$win_id"
saved_opt2="$(tmux -L "$SOCKET" show-option -gqv @dotfiles_sidebar_subpane_height 2>/dev/null || echo 0)"
[ "$saved_opt2" = "22" ] || { echo "FAIL: expected saved option 22 on destroy, got $saved_opt2"; exit 1; }

sub_p3="$(provision_sidebar_subpane "$win_id" "$launcher_p" "" "")"
[ -n "$sub_p3" ] || { echo "FAIL: could not re-provision top subpane"; exit 1; }
recreated_h2="$(tmux -L "$SOCKET" display-message -p -t "$sub_p3" '#{pane_height}')"
[ "$recreated_h2" -eq 22 ] || { echo "FAIL: expected re-provisioned top height 22, got $recreated_h2"; exit 1; }

# 7. Test persistence across tmux server kill & restart
state_file="$(mktemp -u /tmp/test-subpane-state.XXXXXX)"
export TMUX_SESSION_SIDEBAR_SUBPANE_HEIGHT_STATE_FILE="$state_file"
export TMUX_SESSION_SIDEBAR_SUBPANE_POSITION_STATE_FILE="${state_file}.pos"
trap 'tmux -L "$SOCKET" kill-server 2>/dev/null || true; rm -f "$state_file"*' EXIT

persist_sidebar_subpane_height 26
persist_sidebar_subpane_position "bottom"

tmux -L "$SOCKET" kill-server 2>/dev/null || true
_drain_retries=0
while tmux -L "$SOCKET" has-session 2>/dev/null && [ "$_drain_retries" -lt 50 ]; do
    sleep 0.05
    _drain_retries=$((_drain_retries + 1))
done
tmux -L "$SOCKET" new-session -d -s brand-new -n main -x 120 -y 50 'sleep 60'
win_id_new="$(tmux -L "$SOCKET" display-message -p -t brand-new '#{window_id}')"
launcher_p_new="$(tmux -L "$SOCKET" split-window -P -F '#{pane_id}' -d -t "$win_id_new" -h -f -b -l 30 'sleep 60')"

sub_p4="$(provision_sidebar_subpane "$win_id_new" "$launcher_p_new" "" "")"
[ -n "$sub_p4" ] || { echo "FAIL: could not provision subpane on new server"; exit 1; }
recreated_h3="$(tmux -L "$SOCKET" display-message -p -t "$sub_p4" '#{pane_height}')"
[ "$recreated_h3" -eq 26 ] || { echo "FAIL: expected disk-persisted height 26, got $recreated_h3"; exit 1; }

echo "PASS: Subpane height persistence and restoration contract (bottom, top & server restart)"
