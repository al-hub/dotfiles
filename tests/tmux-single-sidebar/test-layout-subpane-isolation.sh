#!/usr/bin/env bash
set -euo pipefail
SOCKET="test-top-snap-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cleanup() { tmux -L "$SOCKET" kill-server 2>/dev/null || true; }
trap cleanup EXIT

tmux -L "$SOCKET" new-session -d -s main -n work 'sleep 60'
win_id="$(tmux -L "$SOCKET" display-message -p -t main '#{window_id}')"
export TMUX="$SOCKET"

source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_topology.sh"
source "$SCRIPT_DIR/scripts/tmux-session-launcher" --source-only 2>/dev/null || true

# Provision sidebar and subpane
topology_ensure_window "$win_id" 30 1
sub_pane="$(sidebar_window_subpane "$win_id")"
[ -n "$sub_pane" ] || { echo "FAIL: subpane not created"; exit 1; }

# Simulate title mutation in subpane
tmux -L "$SOCKET" select-pane -t "$sub_pane" -T "some_user_zsh_title"

# Perform snapshot_work_layout_transaction
snapshot_work_layout_transaction "$win_id"

saved="$(tmux -L "$SOCKET" show-option -wqv -t "$win_id" "$WORK_LAYOUT_OPTION")"
pane_count="$(echo "$saved" | grep -o '[0-9]\+x[0-9]\+' | wc -l)"

# A single work pane was created initially ('work'). The saved work_layout MUST contain exactly 1 pane.
if [ "$pane_count" -ne 1 ]; then
    echo "FAIL: work_layout contains $pane_count panes (expected 1 pure work pane). Saved layout was: '$saved'"
    exit 1
fi

# Also test prepare_window_for_archive_snapshot
archive_snap="$(tmux -L "$SOCKET" list-panes -a -F '#{session_name}	#{window_index}	#{pane_index}	#{pane_id}	#{pane_left}	#{pane_top}	#{pane_width}	#{pane_height}	#{pane_active}	#{pane_current_path}	#{pane_current_command}	#{pane_title}	#{window_name}	#{window_active}	#{window_layout}	#{pane_created}')"
archive_panes_snapshot="$archive_snap"
win_layout="$(tmux -L "$SOCKET" display-message -p -t "$win_id" '#{window_layout}')"

# Test archiving window logic
archived_work_layout="$(prepare_window_for_archive_snapshot "main" "0" "$win_layout")"
arch_pane_count="$(echo "$archived_work_layout" | grep -o '[0-9]\+x[0-9]\+' | wc -l)"
if [ "$arch_pane_count" -ne 1 ]; then
    echo "FAIL: archived_work_layout contains $arch_pane_count panes (expected 1). Layout was: '$archived_work_layout'"
    exit 1
fi

echo "PASS: layout snapshot perfectly isolates subpane"
