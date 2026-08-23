#!/usr/bin/env bash
# ==============================================================================
# tests/tmux-single-sidebar/test-first-enter-warm-session-flicker-detect.sh
#
# TDD Detection Test:
# Verifies whether switching into a background-warmed session for the first time
# via attached PTY keyboard Enter triggers a full screen redraw (`render_full` / flicker)
# due to `client-session-attached` and `session_topology_changed`.
# ==============================================================================

set -euo pipefail

SCENARIO_NAME="first-enter-flicker-detect"
TMUX_SESSION_LAUNCHER_TRACE=1
TMUX_SESSION_LAUNCHER_DEBUG=1
TMUX_INTERACTIVE_CREATE_PEER=false

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$TEST_DIR/test-interactive-common.sh"

echo "=== [1/4] Setting up attached client in interactive-anchor ==="
setup_interactive_test
wait_until "anchor sidebar ready" sidebar_ready

echo "=== [2/4] Spawning peer-warmed session in background with Eager Warm sidebar ==="
tmuxc new-session -d -s peer-warmed -x 120 -y 30 -c "$REPO_ROOT" 'sleep 300'
peer_win="$(tmuxc display-message -p -t '=peer-warmed:' '#{window_id}')"
tmuxc set-option -wq -t "$peer_win" @dotfiles_sidebar_managed 1
tmuxc run-shell "$LAUNCHER --ensure-sidebar-window '$peer_win' 35"

peer_sb="$(tmuxc list-panes -t "$peer_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
[ -n "$peer_sb" ] || { echo "FAIL: peer-warmed sidebar missing"; exit 1; }
echo "Peer-warmed sidebar ready at: $peer_sb (window=$peer_win)"

# Wait for peer-warmed sidebar to complete its initial background boot and appear in anchor list
wait_until "peer-warmed ready" "tmuxc show-options -wqv -t '$peer_win' @dotfiles_sidebar_ready | grep -Fq 1"
wait_until "peer-warmed visible" "[ -n \"\$(sidebar_row_for 'peer-warmed')\" ]"
sleep 0.5

# Snapshot trace file before switch
trace_before="$RUN_DIR/trace-before.log"
cp "$TRACE_FILE" "$trace_before" 2>/dev/null || touch "$trace_before"
peer_full_renders_before=$(grep -F "pane=$peer_sb" "$trace_before" | grep -c "render.full.begin" 2>/dev/null || echo 0)
echo "Baseline peer sidebar ($peer_sb) full_render count before switch: $peer_full_renders_before"

echo "=== [3/4] Navigating to peer-warmed in sidebar and switching ==="
select_session_by_name "peer-warmed"
wait_until "client on peer-warmed" "[ \"\$(client_session)\" = 'peer-warmed' ]"
wait_until "peer sidebar ready after switch" sidebar_ready

sleep 0.3

echo "=== [4/4] Analyzing Trace Events for Full Render / Flicker Detection ==="
trace_after="$RUN_DIR/trace-after.log"
cp "$TRACE_FILE" "$trace_after" 2>/dev/null || touch "$trace_after"

peer_full_renders_after=$(grep -F "pane=$peer_sb" "$trace_after" | grep -c "render.full.begin" 2>/dev/null || echo 0)
new_peer_full_renders=$((peer_full_renders_after - peer_full_renders_before))

echo "Trace analysis for target sidebar ($peer_sb):"
echo "- Target sidebar full renders before switch: $peer_full_renders_before"
echo "- Target sidebar full renders after switch:  $peer_full_renders_after"
echo "- Delta full renders on switch:              $new_peer_full_renders"

recent_events="$(grep -F "pane=$peer_sb" "$trace_after" | grep -E 'render\.full|selection\.refresh|render\.fast_path|mark_full_render|marker\.handover' | tail -n 15 || true)"
echo "Recent events on target sidebar ($peer_sb):"
echo "$recent_events"

# CRITICAL ASSERTION:
# On native switch to a background-warmed session, the target sidebar must NOT execute
# any new render_full. It must absorb the switch and take the delta path (new_peer_full_renders == 0).
if [ "$new_peer_full_renders" -gt 0 ]; then
    echo ""
    echo "=========================================================================="
    echo "DETECTED (RED): First enter to warm session 'peer-warmed' triggered"
    echo "                $new_peer_full_renders full screen redraws on target sidebar!"
    echo "                Flicker condition is present."
    echo "=========================================================================="
    exit 1
fi
echo "PASS: First switch to peer-warmed executed with zero full renders ($new_peer_full_renders)!"

echo "=== [5/5] Testing Incremental Third Session (peer-warmed-2) and Round-Trip Switch ==="
tmuxc new-session -d -s peer-warmed-2 -x 120 -y 30 -c "$REPO_ROOT" 'sleep 300'
peer2_win="$(tmuxc display-message -p -t '=peer-warmed-2:' '#{window_id}')"
tmuxc set-option -wq -t "$peer2_win" @dotfiles_sidebar_managed 1
tmuxc run-shell "$LAUNCHER --ensure-sidebar-window '$peer2_win' 35"

peer2_sb="$(tmuxc list-panes -t "$peer2_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
[ -n "$peer2_sb" ] || { echo "FAIL: peer-warmed-2 sidebar missing"; exit 1; }
wait_until "peer-warmed-2 ready" "tmuxc show-options -wqv -t '$peer2_win' @dotfiles_sidebar_ready | grep -Fq 1"
wait_until "peer-warmed-2 visible" "[ -n \"\$(sidebar_row_for 'peer-warmed-2')\" ]"
sleep 0.5

# Snapshot before switch to peer-warmed-2
cp "$TRACE_FILE" "$RUN_DIR/trace-before-peer2.log"
peer2_full_before=$(grep -F "pane=$peer2_sb" "$RUN_DIR/trace-before-peer2.log" | grep -c "render.full.begin" 2>/dev/null || echo 0)

select_session_by_name "peer-warmed-2"
wait_until "client on peer-warmed-2" "[ \"\$(client_session)\" = 'peer-warmed-2' ]"
wait_until "peer2 sidebar ready after switch" sidebar_ready
sleep 0.3

cp "$TRACE_FILE" "$RUN_DIR/trace-after-peer2.log"
peer2_full_after=$(grep -F "pane=$peer2_sb" "$RUN_DIR/trace-after-peer2.log" | grep -c "render.full.begin" 2>/dev/null || echo 0)
new_peer2_renders=$((peer2_full_after - peer2_full_before))
echo "Target sidebar 2 ($peer2_sb) delta full renders: $new_peer2_renders"

if [ "$new_peer2_renders" -gt 0 ]; then
    echo "FAIL: Switch to incremental session peer-warmed-2 triggered $new_peer2_renders full renders!"
    exit 1
fi
echo "PASS: Switch to incremental session peer-warmed-2 executed with zero full renders!"

# Switch back to interactive-anchor
anchor_win="$(tmuxc display-message -p -t '=interactive-anchor:' '#{window_id}')"
anchor_sb="$(tmuxc list-panes -t "$anchor_win" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"

focus_sidebar
sleep 0.3
cp "$TRACE_FILE" "$RUN_DIR/trace-before-anchor.log"
anchor_full_before=$(grep -F "pane=$anchor_sb" "$RUN_DIR/trace-before-anchor.log" | grep "render.full.begin" | grep -vc "reason=periodic-refresh" 2>/dev/null || echo 0)

select_session_by_name "interactive-anchor"
wait_until "client back on interactive-anchor" "[ \"\$(client_session)\" = 'interactive-anchor' ]"
wait_until "anchor sidebar ready after return" sidebar_ready
sleep 0.3

cp "$TRACE_FILE" "$RUN_DIR/trace-after-anchor.log"
anchor_full_after=$(grep -F "pane=$anchor_sb" "$RUN_DIR/trace-after-anchor.log" | grep "render.full.begin" | grep -vc "reason=periodic-refresh" 2>/dev/null || echo 0)
new_anchor_renders=$((anchor_full_after - anchor_full_before))
echo "Anchor sidebar ($anchor_sb) delta transition full renders on return: $new_anchor_renders"

if [ "$new_anchor_renders" -gt 0 ]; then
    echo "FAIL: Return switch to interactive-anchor triggered $new_anchor_renders full renders!"
    exit 1
fi
echo "PASS: Return switch to interactive-anchor executed with zero full renders!"

echo ""
echo "=========================================================================="
echo "ALL MULTI-SESSION INCREMENTAL 0-FLICKER FAST-PATH TESTS PASSED (100% GREEN)!"
echo "=========================================================================="
exit 0
