#!/usr/bin/env bash
set -euo pipefail

# Test Scenario: Verifies that Candidate 1 prevents the cascading decay defect
# where transient hook observations overwrite Canonical User Intent across session switches.

SOCKET="test-intent-decay-repro-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="$(mktemp -d /tmp/test-intent-decay.XXXXXX)"

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
source "$SCRIPT_DIR/scripts/lib/sidebar_topology.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_switch.sh"

# Create 3 sessions
tmux -L "$SOCKET" new-session -d -s s1 -n work -x 120 -y 50 "sleep 100"
win_1="$(tmux -L "$SOCKET" display-message -p -t s1 "#{window_id}")"
sb_1="$(tmux -L "$SOCKET" split-window -P -F "#{pane_id}" -d -t "$win_1" -h -f -b -l 30 "sleep 100")"
tmux -L "$SOCKET" select-pane -t "$sb_1" -T "dotfiles-session-sidebar"
tmux -L "$SOCKET" set-option -p -q -t "$sb_1" @dotfiles_sidebar_pane 1

tmux -L "$SOCKET" new-session -d -s s2 -n work -x 120 -y 50 "sleep 100"
win_2="$(tmux -L "$SOCKET" display-message -p -t s2 "#{window_id}")"
sb_2="$(tmux -L "$SOCKET" split-window -P -F "#{pane_id}" -d -t "$win_2" -h -f -b -l 30 "sleep 100")"
tmux -L "$SOCKET" select-pane -t "$sb_2" -T "dotfiles-session-sidebar"
tmux -L "$SOCKET" set-option -p -q -t "$sb_2" @dotfiles_sidebar_pane 1

tmux -L "$SOCKET" new-session -d -s s3 -n work -x 120 -y 50 "sleep 100"
win_3="$(tmux -L "$SOCKET" display-message -p -t s3 "#{window_id}")"
sb_3="$(tmux -L "$SOCKET" split-window -P -F "#{pane_id}" -d -t "$win_3" -h -f -b -l 30 "sleep 100")"
tmux -L "$SOCKET" select-pane -t "$sb_3" -T "dotfiles-session-sidebar"
tmux -L "$SOCKET" set-option -p -q -t "$sb_3" @dotfiles_sidebar_pane 1

# Setup subpane at TOP with intentional height 20
sub_p="$(provision_sidebar_subpane "$win_1" "$sb_1" 20 "")"
tmux -L "$SOCKET" set-option -g @dotfiles_sidebar_subpane_height 20
persist_sidebar_subpane_height 20
sidebar_subpane_swap_position "$win_1"

echo "=== Initial Baseline Setup ==="
initial_h="$(tmux -L "$SOCKET" display-message -p -t "$sub_p" "#{pane_height}")"
initial_opt="$(tmux -L "$SOCKET" show-option -gqv @dotfiles_sidebar_subpane_height)"
echo "Initial Live Subpane Height: $initial_h (Expected: 20)"
echo "Initial Persistent Option: $initial_opt (Expected: 20)"

# Simulating 3 consecutive transitions where transient hook observation occurs:
sessions=("s2:$win_2:$sb_2" "s3:$win_3:$sb_3" "s1:$win_1:$sb_1")
step=1

for item in "${sessions[@]}"; do
    IFS=":" read -r target_sess target_win target_sb <<< "$item"
    echo "--- Step $step: Transitioning to $target_sess ---"
    
    # 1. Switch entry reads target_h from global option (Candidate 1: Intent decoupled from observation)
    current_intent="$(tmux -L "$SOCKET" show-option -gqv @dotfiles_sidebar_subpane_height)"
    
    # 2. Join pane into target window
    sidebar_switch_execute_hot "" "$target_sess" "$target_win" "$target_sb" "30" "$sub_p" "$current_intent"
    
    # 3. Simulate asynchronous hook firing during reflow via dist CLI
    bash "$SCRIPT_DIR/dist/tmux-session-launcher" --sync-sidebar-layout "$target_win" "manual-resize"
    
    # 4. Check whether intent remained uncorrupted
    observed_opt="$(tmux -L "$SOCKET" show-option -gqv @dotfiles_sidebar_subpane_height)"
    echo "After Step $step hook execution: Option height is: $observed_opt"
    
    if [ "$observed_opt" != "20" ]; then
        echo "❌ DEFECT DETECTED at Step $step: Global user intent (20) was corrupted to ($observed_opt)!"
        echo "FAIL: Monotonic decay feedback loop successfully reproduced."
        exit 1
    fi
    step=$((step + 1))
done

echo "✅ PASS: Global user intent remained uncorrupted (20) across all steps."
