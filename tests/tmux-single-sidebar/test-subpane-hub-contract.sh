#!/usr/bin/env bash
set -euo pipefail
SOCKET="test-hub-contract-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cleanup() { tmux -L "$SOCKET" kill-server 2>/dev/null || true; }
trap cleanup EXIT

export TMUX="$SOCKET"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_subpane_hub.sh"

# 1. Ensure Hub Session
subpane_hub_ensure_session
subpane_hub_is_alive || { echo "FAIL: hub session not alive after ensure"; exit 1; }

# 2. Idempotent call
subpane_hub_ensure_session
subpane_hub_is_alive || { echo "FAIL: hub session not alive after 2nd ensure"; exit 1; }

# 3. Create a window in another session and attach hub
tmux -L "$SOCKET" new-session -d -s work-session -n main 'sleep 60'
win_id="$(tmux -L "$SOCKET" display-message -p -t work-session '#{window_id}')"
att_pane="$(tmux -L "$SOCKET" split-window -P -F '#{pane_id}' -t "$win_id" "$(subpane_hub_attach_command)" 2>/dev/null || true)"
[ -n "$att_pane" ] || { echo "FAIL: could not attach to hub session"; exit 1; }

# 4. Destroy hub
subpane_hub_destroy
! subpane_hub_is_alive || { echo "FAIL: hub session still alive after destroy"; exit 1; }

echo "PASS: SubpaneHubManager contract"
