#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib.sh"
load_launcher_functions

reset_calls()
{
    TEST_TMUX_CALL_COUNT=()
    : > "$TEST_TMUX_CALL_LOG"
}

call_count()
{
    grep -c "^$1$" "$TEST_TMUX_CALL_LOG" 2>/dev/null || true
}

test_render_is_tmux_free()
{
    set_single_ai_session test %1 bash
    collect_sessions
    reset_calls
    render_row 0 >/dev/null
    render_animated_name_cells >/dev/null

    assert_eq 0 "$(call_count display-message)" 'render geometry calls'
    assert_eq 0 "$(call_count list-panes)" 'render topology calls'
    assert_eq 0 "$(call_count capture-pane)" 'render capture calls'
    assert_eq 0 "$(call_count pgrep)" 'render process calls'
}

test_collect_uses_one_client_snapshot()
{
    set_single_ai_session test %1 bash
    reset_calls
    collect_sessions

    assert_eq 1 "$(call_count list-clients)" 'client snapshot calls'
    # The snapshot still samples current session and geometry; it no longer
    # performs one display-message activity query per session.
    assert_eq 4 "$(call_count display-message)" 'activity display calls'
    assert_eq 0 "$(call_count pgrep)" 'passive pane process probes'
}

run_test 'render hot path does not call external probes' test_render_is_tmux_free
run_test 'session collection uses one client snapshot' test_collect_uses_one_client_snapshot
finish_tests
