#!/usr/bin/env bash
# ==============================================================================
# tests/tmux-single-sidebar/test-sidebar-ghost-row-stale-footer-detect.sh
#
# Standalone Isolated TDD Detection Test:
# Stably reproduces and detects:
# 1. Ghost duplicate rows / stray markers left in the terminal buffer during
#    consecutive session switches across sessions with differing geometries/subpanes.
# 2. Stale transient switch footer messages ("⚡ switching to...") stuck on the footer.
# ==============================================================================

set -euo pipefail

SCENARIO_NAME="ghost-row-stale-footer-detect"
TMUX_SESSION_LAUNCHER_TRACE=1
TMUX_SESSION_LAUNCHER_DEBUG=1
TMUX_INTERACTIVE_CREATE_PEER=false

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$TEST_DIR/test-interactive-common.sh"

echo "=== [1/5] Setting up isolated interactive test with attached client ==="
setup_interactive_test
wait_until "anchor sidebar ready" sidebar_ready

anchor_win="$(tmuxc display-message -p -t '=interactive-anchor:' '#{window_id}')"
anchor_sb="$(tmuxc list-panes -t "$anchor_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
initial_width="$(tmuxc display-message -p -t "$anchor_sb" '#{pane_width}')"

echo "=== [2/5] Creating 5 additional sessions to match multi-session topology ==="
SESSIONS=("interactive-anchor" "sess-alpha" "sess-beta" "sess-gamma" "sess-delta" "sess-epsilon")

for s in "sess-alpha" "sess-beta" "sess-gamma" "sess-delta" "sess-epsilon"; do
    tmuxc new-session -d -s "$s" -x 160 -y 50 -c "$REPO_ROOT" 'sleep 300'
    s_win="$(tmuxc display-message -p -t "=$s:" '#{window_id}')"
    tmuxc set-option -wq -t "$s_win" @dotfiles_sidebar_managed 1
    tmuxc run-shell "$LAUNCHER --ensure-sidebar-window '$s_win' $initial_width"
    wait_until "$s sidebar ready" "tmuxc show-options -wqv -t '$s_win' @dotfiles_sidebar_ready | grep -Fq 1"
done

# In sess-alpha, toggle subpane on so geometry differences exist across sessions
alpha_win="$(tmuxc display-message -p -t '=sess-alpha:' '#{window_id}')"
tmuxc run-shell "$LAUNCHER --toggle-subpane '$alpha_win'"
sleep 0.5

echo "=== [3/5] Performing 10 consecutive session moves and switches ==="
detected_ghost_rows=0
detected_missing_views=0
detected_stale_footers=0

for step in $(seq 1 10); do
    cur_sess="$(client_session)"
    cur_sb="$(tmuxc list-panes -t "=$cur_sess:" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
    
    # Send Down then Enter to switch to next session
    tmuxc send-keys -t "$cur_sb" Down
    sleep 0.05
    tmuxc send-keys -t "$cur_sb" Enter
    sleep 0.45
    
    new_sess="$(client_session)"
    new_sb="$(tmuxc list-panes -t "=$new_sess:" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
    
    # Wait up to 2s for target sidebar to consume marker and render rows
    wait_until "sidebar on $new_sess rendered" "tmuxc capture-pane -p -t '$new_sb' | grep -Fq '$new_sess'" || true
    
    screen="$(tmuxc capture-pane -p -t "$new_sb")"
    session_rows="$(echo "$screen" | head -n -1)"
    
    echo "--- Step $step: Switched to $new_sess (Sidebar: $new_sb) ---"
    echo "$screen"
    echo "-------------------------------------------------------------"
    
    # Detection 1: Ghost duplicate rows (check if any session name appears >1 time in session list)
    for s in "${SESSIONS[@]}"; do
        occ="$(echo "$session_rows" | grep -c -F "$s" || true)"
        if [ "$occ" -gt 1 ]; then
            echo "⚠️ DETECTED GHOST ROW: Session '$s' appears $occ times in session list!"
            detected_ghost_rows=$((detected_ghost_rows + 1))
            break
        fi
    done
    
    # Detection 2: Blank screen / missing current session in visible rows
    if ! echo "$screen" | grep -Fq "$new_sess"; then
        echo "⚠️ DETECTED BLANK/MISSING VIEW: Current session '$new_sess' not visible in sidebar!"
        detected_missing_views=$((detected_missing_views + 1))
    fi
    
    # Detection 3: Stale transient message on footer
    if echo "$screen" | grep -Fq "switching to"; then
        echo "⚠️ DETECTED STALE FOOTER: 'switching to' message is stuck on footer!"
        detected_stale_footers=$((detected_stale_footers + 1))
    fi
    
    sleep 0.1
done

echo "=== [4/5] Summary of Detected Anomalies in Isolated Test ==="
echo "Ghost Duplicate Rows detected: $detected_ghost_rows / 10 switches"
echo "Blank / Missing Views detected: $detected_missing_views / 10 switches"
echo "Stale Footer Messages detected: $detected_stale_footers / 10 switches"

if [ "$detected_ghost_rows" -gt 0 ] || [ "$detected_missing_views" -gt 0 ] || [ "$detected_stale_footers" -gt 0 ]; then
    echo ""
    echo "=========================================================================="
    echo "DETECTED ISSUES IN ISOLATED TEST (RED): Display anomalies stably detected!"
    echo "=========================================================================="
    exit 1
fi

echo "ALL CLEAN (GREEN)"
exit 0
