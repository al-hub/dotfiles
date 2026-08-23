#!/usr/bin/env bash
# ==============================================================================
# tests/tmux-single-sidebar/test-mouse-width-resize-switch.sh
#
# TDD Detection Test:
# Verifies whether resizing the sidebar width via mouse/window-resized (e.g. 30 -> 45)
# persists across multi-session switching (Enter key) to another session and back.
# ==============================================================================

set -euo pipefail

SCENARIO_NAME="mouse-width-resize-switch"
TMUX_SESSION_LAUNCHER_TRACE=1
TMUX_SESSION_LAUNCHER_DEBUG=1
TMUX_INTERACTIVE_CREATE_PEER=false

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$TEST_DIR/test-interactive-common.sh"

echo "=== [1/4] Setting up interactive client on interactive-anchor ==="
setup_interactive_test
wait_until "anchor sidebar ready" sidebar_ready

anchor_win="$(tmuxc display-message -p -t '=interactive-anchor:' '#{window_id}')"
anchor_sb="$(tmuxc list-panes -t "$anchor_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
initial_width="$(tmuxc display-message -p -t "$anchor_sb" '#{pane_width}')"
echo "Anchor sidebar ($anchor_sb) initial width: $initial_width"

echo "=== [2/4] Creating background session (peer-mouse-test) with Eager Warm sidebar ==="
tmuxc new-session -d -s peer-mouse-test -x 160 -y 40 -c "$REPO_ROOT" 'sleep 300'
peer_win="$(tmuxc display-message -p -t '=peer-mouse-test:' '#{window_id}')"
tmuxc set-option -wq -t "$peer_win" @dotfiles_sidebar_managed 1
tmuxc run-shell "$LAUNCHER --ensure-sidebar-window '$peer_win' $initial_width"

peer_sb="$(tmuxc list-panes -t "$peer_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
[ -n "$peer_sb" ] || { echo "FAIL: peer sidebar missing"; exit 1; }
wait_until "peer sidebar ready" "tmuxc show-options -wqv -t '$peer_win' @dotfiles_sidebar_ready | grep -Fq 1"
wait_until "peer-mouse-test visible" "[ -n \"\$(sidebar_row_for 'peer-mouse-test')\" ]"
sleep 0.3

echo "=== [3/4] Simulating mouse border resize on anchor sidebar (Target Width: 45) ==="
TARGET_WIDTH=45

# In tmux, mouse dragging a pane border directly adjusts geometry and fires the window-resized hook (NOT after-resize-pane):
tmuxc set-hook -u -g after-resize-pane 2>/dev/null || true
tmuxc resize-pane -t "$anchor_sb" -x "$TARGET_WIDTH"
tmuxc run-shell "$LAUNCHER --sync-sidebar-layout '$anchor_win' window-resized"
sleep 0.3

anchor_current_width="$(tmuxc display-message -p -t "$anchor_sb" '#{pane_width}')"
echo "Anchor sidebar width right after resize: $anchor_current_width"

if [ "$anchor_current_width" -ne "$TARGET_WIDTH" ]; then
    echo "FAIL: Failed to resize anchor sidebar to $TARGET_WIDTH (current: $anchor_current_width)"
    exit 1
fi

echo "=== [4/4] Switching to peer-mouse-test and checking inherited width ==="
select_session_by_name "peer-mouse-test"
wait_until "client on peer-mouse-test" "[ \"\$(client_session)\" = 'peer-mouse-test' ]"
wait_until "peer sidebar ready after switch" sidebar_ready
sleep 0.3

peer_current_width="$(tmuxc display-message -p -t "$peer_sb" '#{pane_width}')"
global_opt_width="$(tmuxc show-option -gqv '@dotfiles-session-sidebar-width' || echo none)"
echo "Target session (peer-mouse-test) sidebar width after switch: $peer_current_width"
echo "Global stored option width: $global_opt_width"

# CRITICAL ASSERTION:
# If mouse resize (window-resized) was not persisted globally, the target sidebar
# will have reverted back to initial_width (e.g. 30 or 35) instead of TARGET_WIDTH (45).
if [ "$peer_current_width" -ne "$TARGET_WIDTH" ]; then
    echo ""
    echo "=========================================================================="
    echo "DETECTED (RED): Target sidebar width reverted to $peer_current_width (expected $TARGET_WIDTH)!"
    echo "                Global option is: $global_opt_width"
    echo "                Mouse drag resize (window-resized) was lost across session switch."
    echo "=========================================================================="
    exit 1
fi

# Switch back to interactive-anchor and verify width
select_session_by_name "interactive-anchor"
wait_until "client back on anchor" "[ \"\$(client_session)\" = 'interactive-anchor' ]"
wait_until "anchor sidebar ready after return" sidebar_ready
sleep 0.3

anchor_return_width="$(tmuxc display-message -p -t "$anchor_sb" '#{pane_width}')"
echo "Anchor sidebar width after return switch: $anchor_return_width"

if [ "$anchor_return_width" -ne "$TARGET_WIDTH" ]; then
    echo ""
    echo "=========================================================================="
    echo "DETECTED (RED): Anchor sidebar width reverted to $anchor_return_width (expected $TARGET_WIDTH) on return!"
    echo "=========================================================================="
    exit 1
fi

echo ""
echo "=========================================================================="
echo "PASS (GREEN): Sidebar width ($TARGET_WIDTH) was perfectly preserved across multi-session switches!"
echo "=========================================================================="
exit 0
