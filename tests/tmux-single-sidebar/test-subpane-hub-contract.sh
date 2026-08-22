#!/usr/bin/env bash
set -euo pipefail
SOCKET="test-hub-contract-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cleanup() { tmux -L "$SOCKET" kill-server 2>/dev/null || true; }
trap cleanup EXIT

export TMUX="$SOCKET"
source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_subpane_hub.sh"

# 1. Ensure Hub Session
subpane_hub_ensure_session
subpane_hub_is_alive || { echo "FAIL: hub session not alive after ensure"; exit 1; }

# 2. Idempotent call
subpane_hub_ensure_session
subpane_hub_is_alive || { echo "FAIL: hub session not alive after 2nd ensure"; exit 1; }

# 3. Create a window in another session and acquire hub pane
tmux -L "$SOCKET" new-session -d -s work-session -n main 'sleep 60'
win_id="$(tmux -L "$SOCKET" display-message -p -t work-session '#{window_id}')"
launcher_p="$(tmux -L "$SOCKET" split-window -P -F '#{pane_id}' -d -t "$win_id" -h -f -b -l 30 'sleep 60')"

att_pane="$(subpane_hub_acquire_pane "$launcher_p" 10)"
[ -n "$att_pane" ] || { echo "FAIL: could not acquire hub pane"; exit 1; }

# Verify option set on acquired pane
is_sub="$(tmux -L "$SOCKET" show-option -pqv -t "$att_pane" @dotfiles_sidebar_subpane 2>/dev/null || echo 0)"
[ "$is_sub" = "1" ] || { echo "FAIL: @dotfiles_sidebar_subpane not set on acquired pane"; exit 1; }

# Release pane
subpane_hub_release_pane "$att_pane"

# Re-acquire
att_pane2="$(subpane_hub_acquire_pane "$launcher_p" 10)"
[ "$att_pane" = "$att_pane2" ] || { echo "FAIL: re-acquired pane identity changed"; exit 1; }

# Destroy hub
subpane_hub_destroy
! subpane_hub_is_alive || { echo "FAIL: hub session still alive after destroy"; exit 1; }

echo "PASS: SubpaneHubManager contract"
