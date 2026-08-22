#!/usr/bin/env bash
set -euo pipefail
SOCKET="test-top-contract-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cleanup() { tmux -L "$SOCKET" kill-server 2>/dev/null || true; }
trap cleanup EXIT

tmux -L "$SOCKET" new-session -d -s main -n work 'sleep 60'
win_id="$(tmux -L "$SOCKET" display-message -p -t main '#{window_id}')"
export TMUX="$SOCKET"

source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_topology.sh"

# Ensure cluster (sidebar + subpane)
topology_ensure_window "$win_id" 30 1

declare sb sub w_panes act_w
topology_inspect "$win_id" sb sub w_panes act_w

[ -n "$sb" ] || { echo "FAIL: sidebar missing"; exit 1; }
[ -n "$sub" ] || { echo "FAIL: subpane missing"; exit 1; }
[ -n "$w_panes" ] || { echo "FAIL: work panes missing"; exit 1; }
[[ "$w_panes" != *"$sb"* ]] || { echo "FAIL: sidebar in work panes"; exit 1; }
[[ "$w_panes" != *"$sub"* ]] || { echo "FAIL: subpane in work panes"; exit 1; }

# Simulate subpane title change by shell
tmux -L "$SOCKET" select-pane -t "$sub" -T "some_user_zsh_title"

# Re-inspect to verify immunity to title mutations
topology_inspect "$win_id" sb sub w_panes act_w
[ -n "$sub" ] || { echo "FAIL: subpane not detected after title change"; exit 1; }
[[ "$w_panes" != *"$sub"* ]] || { echo "FAIL: subpane in work panes after title change"; exit 1; }

# Destroy cluster cleanly
topology_destroy_sidebar_cluster "$win_id"
topology_inspect "$win_id" sb sub w_panes act_w
[ -z "$sb" ] || { echo "FAIL: sidebar not destroyed"; exit 1; }
[ -z "$sub" ] || { echo "FAIL: subpane not destroyed"; exit 1; }

# Ensure single work pane remains at full width
work_count="$(echo "$w_panes" | wc -w)"
[ "$work_count" -eq 1 ] || { echo "FAIL: expected 1 work pane, got $work_count"; exit 1; }

echo "PASS: WindowTopologyManager contract"
