#!/usr/bin/env bash
set -euo pipefail
SOCKET="test-top-unit-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cleanup() { tmux -L "$SOCKET" kill-server 2>/dev/null || true; }
trap cleanup EXIT

tmux -L "$SOCKET" new-session -d -s main -n work 'sleep 60'
win_id="$(tmux -L "$SOCKET" display-message -p -t main '#{window_id}')"
export TMUX="$SOCKET"

source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"

# Create a pane and tag with option
p1="$(tmux -L "$SOCKET" split-window -P -F '#{pane_id}' -t "$win_id" 'sleep 60')"
tmux -L "$SOCKET" set-option -p -q -t "$p1" @dotfiles_sidebar_subpane 1
# Mutate title
tmux -L "$SOCKET" select-pane -t "$p1" -T "zsh_overwritten_title"

# Test finding subpane even with overwritten title
found="$(sidebar_window_subpane "$win_id")"
[ "$found" = "$p1" ] || { echo "FAIL: sidebar_window_subpane expected '$p1', got '$found'"; exit 1; }

# Test predicate
sidebar_port_is_subpane "$p1" || { echo "FAIL: sidebar_port_is_subpane for $p1"; exit 1; }

echo "PASS: immutable option pane identification"
