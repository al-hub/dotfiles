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

# 3. Manually resize subpane to 18 lines
tmux -L "$SOCKET" resize-pane -t "$sub_p" -y 18
actual_h="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" '#{pane_height}')"
[ "$actual_h" -eq 18 ] || { echo "FAIL: resize-pane failed, got $actual_h"; exit 1; }

# 4. Remember subpane height
remember_sidebar_subpane_height_for_window "$win_id"
saved_opt="$(tmux -L "$SOCKET" show-option -gqv @dotfiles_sidebar_subpane_height 2>/dev/null || echo 0)"
[ "$saved_opt" = "18" ] || { echo "FAIL: expected saved option 18, got $saved_opt"; exit 1; }

# 5. Destroy subpane
destroy_sidebar_subpane "$win_id"

# 6. Re-provision subpane without passing height (should reuse saved 18)
sub_p2="$(provision_sidebar_subpane "$win_id" "$launcher_p" "" "")"
[ -n "$sub_p2" ] || { echo "FAIL: could not re-provision subpane"; exit 1; }
recreated_h="$(tmux -L "$SOCKET" display-message -p -t "$sub_p2" '#{pane_height}')"
[ "$recreated_h" -eq 18 ] || { echo "FAIL: expected re-provisioned height 18, got $recreated_h"; exit 1; }

echo "PASS: Subpane height persistence and restoration contract"
