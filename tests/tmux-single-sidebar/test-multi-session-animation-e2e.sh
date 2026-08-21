#!/usr/bin/env bash
# E2E unit/integration test for asynchronous multi-session animation & activity tracking
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Use the established gradient test harness for full tmux mock fidelity
source "$REPO_ROOT/tests/tmux-sidebar-gradient/lib.sh"
unset TEST_CAPTURE

echo "=== Running Multi-Session Animation & Activity Tracking E2E Tests ==="

load_launcher_functions

test_multisession_async_animation() {
    export TMUX_SESSION_LAUNCHER_DEBUG=1
    ai_pid=""
    # Spawn background mock AI process named opencode
    (exec -a opencode sleep 30) &
    ai_pid=$!
    trap 'if [ -n "${ai_pid:-}" ]; then kill -9 "$ai_pid" 2>/dev/null || true; fi' EXIT

    # 1. Setup two sessions: sess-ai (with running AI command) and sess-user (current/selected)
    TEST_CURRENT_SESSION="sess-user"
    TEST_CLIENT_SESSIONS_SNAPSHOT="sess-user"
    
    # Sessions: sess-ai created at 100, sess-user created at 200
    TEST_SESSIONS_SNAPSHOT="$(printf 'sess-ai\t100\t0\nsess-user\t200\t0')"
    
    # Panes:
    # sess-ai has pane %101 running "opencode", initial activity signature 1000:50:5:10
    # sess-user has pane %201 running "zsh", initial activity signature 2000:10:1:1
    TEST_PANES_SNAPSHOT="$(printf 'sess-ai\t%%101\twork\topencode\t1000:50:5:10\t%s\nsess-user\t%%201\twork\tzsh\t2000:10:1:1\t%s' "$ai_pid" "$$")"

    selected_session="sess-user"
    current_session="sess-user"

    # First full collection to initialize topology and discover AI pane
    collect_sessions true ""

    # Verify sess-ai is index 0 and active, sess-user is index 1
    local idx_ai=0 idx_user=1
    if [ "${session_names[0]}" = "sess-user" ]; then
        idx_ai=1
        idx_user=0
    fi

    echo "Found AI session at index $idx_ai (name=${session_names[$idx_ai]}), User session at index $idx_user (name=${session_names[$idx_user]})"
    
    [ "${session_cli_state[$idx_ai]}" = "active" ] || {
        echo "FAIL: Expected sess-ai to be active after initial scan, got state=${session_cli_state[$idx_ai]}"
        exit 1
    }
    [ "${session_animate[$idx_ai]}" = "true" ] || {
        echo "FAIL: Expected sess-ai to have animate=true, got animate=${session_animate[$idx_ai]}"
        exit 1
    }
    echo "PASS: Initial scan successfully identifies AI process and enables animation"

    # 2. Simulate incremental refresh where ONLY sess-user is requested_scan_session,
    # but sess-ai emits new output activity (signature updates to 1100:60:6:12)
    TEST_PANES_SNAPSHOT="$(printf 'sess-ai\t%%101\twork\topencode\t1100:60:6:12\t%s\nsess-user\t%%201\twork\tzsh\t2000:10:1:1\t%s' "$ai_pid" "$$")"

    # Incremental refresh targeting selected session
    collect_sessions false "$selected_session"

    [ "${session_cli_state[$idx_ai]}" = "active" ] || {
        echo "FAIL: Expected unselected sess-ai to remain active during incremental scan, got state=${session_cli_state[$idx_ai]}"
        exit 1
    }
    [ "${session_animate[$idx_ai]}" = "true" ] || {
        echo "FAIL: Expected unselected sess-ai to continue animating asynchronously, got animate=${session_animate[$idx_ai]}"
        exit 1
    }
    echo "PASS: Non-selected session continues animating asynchronously when activity updates"

    # 3. Simulate quiescent output on sess-ai (activity signature stays 1100:60:6:12)
    # After 2 stable cycles, it should transition to waiting and stop animating
    collect_sessions false "$selected_session"
    collect_sessions false "$selected_session"

    [ "${session_cli_state[$idx_ai]}" = "waiting" ] || {
        echo "FAIL: Expected quiescent sess-ai to settle to waiting, got state=${session_cli_state[$idx_ai]}"
        exit 1
    }
    [ "${session_animate[$idx_ai]}" = "false" ] || {
        echo "FAIL: Expected quiescent sess-ai to stop animating (animate=false), got animate=${session_animate[$idx_ai]}"
        exit 1
    }
    echo "PASS: Quiescent unselected session settles to waiting and stops animation"

    # 4. Simulate new output burst on sess-ai (signature updates to 1200:70:7:14)
    TEST_PANES_SNAPSHOT="$(printf 'sess-ai\t%%101\twork\topencode\t1200:70:7:14\t%s\nsess-user\t%%201\twork\tzsh\t2000:10:1:1\t%s' "$ai_pid" "$$")"

    collect_sessions false "$selected_session"

    [ "${session_cli_state[$idx_ai]}" = "active" ] || {
        echo "FAIL: Expected output burst to reactivate sess-ai, got state=${session_cli_state[$idx_ai]}"
        exit 1
    }
    [ "${session_animate[$idx_ai]}" = "true" ] || {
        echo "FAIL: Expected output burst to resume animation, got animate=${session_animate[$idx_ai]}"
        exit 1
    }
    echo "PASS: Output burst on unselected session immediately resumes animation"
}

test_multisession_async_animation

echo "=== All Multi-Session Animation E2E Tests Passed ==="
