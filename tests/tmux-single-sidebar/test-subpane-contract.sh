#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOCKET="test-subpane-contract-$$"

tmux -L "$SOCKET" new-session -d -s main -n work 'sleep 60'
win_id="$(tmux -L "$SOCKET" display-message -p -t main '#{window_id}')"

export TMUX="$SOCKET"
source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"
source "$SCRIPT_DIR/scripts/tmux-session-launcher" --source-only 2>/dev/null || true

# Provision sidebar
provision_sidebar_window "$win_id" 30
launcher_pane="$(sidebar_window_pane "$win_id" || true)"
[ -n "$launcher_pane" ] || { echo "FAIL: launcher pane not created"; tmux -L "$SOCKET" kill-server; exit 1; }

# Provision subpane below launcher
sub_pane="$(provision_sidebar_subpane "$win_id" "$launcher_pane" 10 "sleep 60")"
[ -n "$sub_pane" ] || { echo "FAIL: subpane not created"; tmux -L "$SOCKET" kill-server; exit 1; }

# Verify subpane properties
sub_title="$(tmux -L "$SOCKET" display-message -p -t "$sub_pane" '#{pane_title}')"
[ "$sub_title" = "dotfiles-sidebar-subpane" ] || { echo "FAIL: subpane title '$sub_title'"; tmux -L "$SOCKET" kill-server; exit 1; }

# Verify finding subpane
found_sub="$(sidebar_window_subpane "$win_id")"
[ "$found_sub" = "$sub_pane" ] || { echo "FAIL: sidebar_window_subpane found '$found_sub' expected '$sub_pane'"; tmux -L "$SOCKET" kill-server; exit 1; }

# Verify destroying subpane
destroy_sidebar_subpane "$win_id"
found_after="$(sidebar_window_subpane "$win_id")"
[ -z "$found_after" ] || { echo "FAIL: subpane still exists after destroy"; tmux -L "$SOCKET" kill-server; exit 1; }

tmux -L "$SOCKET" kill-server
echo "PASS: subpane contract test"
