#!/usr/bin/env bash
# ==============================================================================
# tests/tmux-single-sidebar/test-incremental-session-discovery-stale-footer-detect.sh
#
# TDD Detection Test:
# 1. Verifies if pre-warmed background sidebars discover incrementally created new sessions
#    (e.g., sess-gamma created after sess-beta).
# 2. Verifies if transient switch footer messages ("⚡ switching to ...") are cleared
#    and restored to standard footer upon returning to the session.
# ==============================================================================

set -euo pipefail

SCENARIO_NAME="incremental-discovery-stale-footer"
TMUX_SESSION_LAUNCHER_TRACE=1
TMUX_SESSION_LAUNCHER_DEBUG=1
TMUX_INTERACTIVE_CREATE_PEER=false

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$TEST_DIR/test-interactive-common.sh"

echo "=== [1/5] Setting up interactive client on interactive-anchor ==="
setup_interactive_test
wait_until "anchor sidebar ready" sidebar_ready

anchor_win="$(tmuxc display-message -p -t '=interactive-anchor:' '#{window_id}')"
anchor_sb="$(tmuxc list-panes -t "$anchor_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
initial_width="$(tmuxc display-message -p -t "$anchor_sb" '#{pane_width}')"

echo "=== [2/5] Creating sess-beta with Pre-warmed sidebar ==="
tmuxc new-session -d -s sess-beta -x 160 -y 40 -c "$REPO_ROOT" 'sleep 300'
beta_win="$(tmuxc display-message -p -t '=sess-beta:' '#{window_id}')"
tmuxc set-option -wq -t "$beta_win" @dotfiles_sidebar_managed 1
tmuxc run-shell "$LAUNCHER --ensure-sidebar-window '$beta_win' $initial_width"

beta_sb="$(tmuxc list-panes -t "$beta_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
[ -n "$beta_sb" ] || { echo "FAIL: sess-beta sidebar missing"; exit 1; }
wait_until "sess-beta ready" "tmuxc show-options -wqv -t '$beta_win' @dotfiles_sidebar_ready | grep -Fq 1"
wait_until "sess-beta visible on anchor" "[ -n \"\$(sidebar_row_for 'sess-beta')\" ]"
# Give sess-beta enough time to complete initial background render and settle into idle
sleep 1.0

echo "=== [3/5] Creating sess-gamma AFTER sess-beta is idle in detached background ==="
tmuxc new-session -d -s sess-gamma -x 160 -y 40 -c "$REPO_ROOT" 'sleep 300'
gamma_win="$(tmuxc display-message -p -t '=sess-gamma:' '#{window_id}')"
tmuxc set-option -wq -t "$gamma_win" @dotfiles_sidebar_managed 1
# Do not run ensure-sidebar-window manually on gamma so it mirrors real user/tmux hook lifecycle
wait_until "sess-gamma visible on anchor" "[ -n \"\$(sidebar_row_for 'sess-gamma')\" ]"
sleep 0.5

echo "=== [4/5] Switching to sess-beta and checking if sess-gamma is present ==="
select_session_by_name "sess-beta"
wait_until "client on sess-beta" "[ \"\$(client_session)\" = 'sess-beta' ]"
wait_until "sess-beta sidebar ready after switch" sidebar_ready
sleep 0.3

beta_screen="$(tmuxc capture-pane -p -t "$beta_sb")"
echo "--- Captured Screen of sess-beta Sidebar ---"
echo "$beta_screen"
echo "--------------------------------------------"

detected_issues=0

# Detection Check 1: sess-gamma MUST be present in sess-beta sidebar
if ! echo "$beta_screen" | grep -Fq "sess-gamma"; then
    echo ""
    echo "=========================================================================="
    echo "DETECTED ISSUE 1 (RED): sess-gamma is MISSING in sess-beta's sidebar!"
    echo "                        Pre-warmed sidebar failed to discover incremental session."
    echo "=========================================================================="
    detected_issues=$((detected_issues + 1))
else
    echo "PASS: sess-gamma is present in sess-beta's sidebar."
fi

echo "=== [5/5] Testing Footer Message Cleanup across round-trip switch ==="
# In sess-beta, switch back to interactive-anchor (this prints "⚡ switching to interactive-anchor" on sess-beta footer)
select_session_by_name "interactive-anchor"
wait_until "client on interactive-anchor" "[ \"\$(client_session)\" = 'interactive-anchor' ]"
wait_until "anchor sidebar ready after return" sidebar_ready
sleep 0.3

# Now switch back to sess-beta
select_session_by_name "sess-beta"
wait_until "client back on sess-beta" "[ \"\$(client_session)\" = 'sess-beta' ]"
wait_until "sess-beta sidebar ready" sidebar_ready
sleep 0.3

beta_screen_return="$(tmuxc capture-pane -p -t "$beta_sb")"
echo "--- Captured Screen of sess-beta Sidebar upon Return ---"
echo "$beta_screen_return"
echo "--------------------------------------------------------"

# Detection Check 2: "⚡ switching" should NOT be stuck on the footer
if echo "$beta_screen_return" | grep -Fq "switching to"; then
    echo ""
    echo "=========================================================================="
    echo "DETECTED ISSUE 2 (RED): Stale transient message 'switching to' is stuck on footer!"
    echo "                        Footer was not cleaned up upon returning to sess-beta."
    echo "=========================================================================="
    detected_issues=$((detected_issues + 1))
else
    echo "PASS: Footer was cleanly restored upon return."
fi

if [ "$detected_issues" -gt 0 ]; then
    echo ""
    echo "SUMMARY: $detected_issues issues stably detected (RED)."
    exit 1
fi

echo ""
echo "=========================================================================="
echo "ALL PASS (GREEN): Incremental sessions discovered and footer cleanly restored!"
echo "=========================================================================="
exit 0
