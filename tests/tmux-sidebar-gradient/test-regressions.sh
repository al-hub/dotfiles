#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib.sh"
load_launcher_functions

declare -A TEST_FINGERPRINT_BY_PANE=()

eval "$(declare -f session_ai_fingerprint_for_pane | sed '1s/session_ai_fingerprint_for_pane/production_fingerprint_for_pane/')"

session_ai_fingerprint_for_pane()
{
    printf '%s\n' "${TEST_FINGERPRINT_BY_PANE[$1]:-}"
}

desired_one_stable_sample_keeps_running()
{
    set_single_ai_session test %1 codex
    TEST_FINGERPRINT_BY_PANE['%1']='stable'

    collect_sessions
    collect_sessions

    assert_eq active "${session_cli_state[0]}" 'single stable sample state'
    assert_eq true "${session_animate[0]}" 'single stable sample animation'
}

desired_spinner_in_body_is_normalized()
{
    TEST_CAPTURE=$'header\nspinner 1\nfooter'
    first="$(production_fingerprint_for_pane '%1')"
    TEST_CAPTURE=$'header\nspinner 2\nfooter'
    second="$(production_fingerprint_for_pane '%1')"

    assert_eq "$first" "$second" 'spinner-normalized fingerprint'
}

desired_new_pane_generation_starts_active()
{
    set_single_ai_session test %1 codex
    TEST_FINGERPRINT_BY_PANE['%1']='same-output'
    TEST_FINGERPRINT_BY_PANE['%2']='same-output'

    collect_sessions false test
    set_single_ai_session test %2 codex
    collect_sessions

    assert_eq active "${session_cli_state[0]}" 'new pane generation state'
    assert_eq true "${session_animate[0]}" 'new pane generation animation'
}

desired_sidebar_click_does_not_trigger_gradient()
{
    set_single_ai_session test %1 codex
    TEST_FINGERPRINT_BY_PANE['%1']='2958009541:1142'

    collect_sessions
    collect_sessions
    collect_sessions
    assert_eq waiting "${session_cli_state[0]}" 'should be waiting'

    # Simulate sidebar click/session switch.
    # In tmux, switching the active session/client or clicking redrawing changes the pane focus,
    # which alters the capture-pane output (e.g. cursor block style, whitespace, or focus indicators).
    # This results in a completely different numerical checksum.
    # We simulate the session switch by changing the active session to 'other' and then back to 'test'.
    TEST_CURRENT_SESSION='other'
    collect_sessions

    TEST_CURRENT_SESSION='test'
    TEST_FINGERPRINT_BY_PANE['%1']='384729103:1142'
    collect_sessions

    assert_eq waiting "${session_cli_state[0]}" 'should remain waiting on focus change'
    assert_eq false "${session_animate[0]}" 'should not animate on focus change'
}

desired_resize_does_not_trigger_gradient()
{
    set_single_ai_session test %1 codex
    TEST_FINGERPRINT_BY_PANE['%1']='2958009541:1142'

    collect_sessions
    collect_sessions
    collect_sessions
    assert_eq waiting "${session_cli_state[0]}" 'should be waiting'

    # Simulate terminal/pane resize.
    TEST_PANE_WIDTH=100
    TEST_PANE_HEIGHT=30
    TEST_FINGERPRINT_BY_PANE['%1']='384729103:1142'
    collect_sessions

    assert_eq waiting "${session_cli_state[0]}" 'should remain waiting on resize'
    assert_eq false "${session_animate[0]}" 'should not animate on resize'

    # Subsequent cycle (bypass inactive, actual fingerprint should be matching baseline)
    collect_sessions
    assert_eq waiting "${session_cli_state[0]}" 'should remain waiting on subsequent cycle'
    assert_eq false "${session_animate[0]}" 'should not animate on subsequent cycle'
}

desired_client_session_switch_does_not_trigger_gradient()
{
    set_single_ai_session test %1 codex
    TEST_FINGERPRINT_BY_PANE['%1']='2958009541:1142'

    collect_sessions
    collect_sessions
    collect_sessions
    assert_eq waiting "${session_cli_state[0]}" 'should be waiting'

    # Simulate client switching session.
    TEST_CURRENT_SESSION='other'
    TEST_CLIENT_SESSIONS_SNAPSHOT='other'
    TEST_FINGERPRINT_BY_PANE['%1']='384729103:1142'
    collect_sessions

    assert_eq waiting "${session_cli_state[0]}" 'should remain waiting on client session switch'
    assert_eq false "${session_animate[0]}" 'should not animate on client session switch'
    assert_eq true "$full_render_required" 'client session switch should request full render'

    # Subsequent cycle (bypass inactive, actual fingerprint should be matching baseline)
    collect_sessions
    assert_eq waiting "${session_cli_state[0]}" 'should remain waiting on subsequent cycle'
    assert_eq false "${session_animate[0]}" 'should not animate on subsequent cycle'
}

desired_client_session_switch_aligns_cursor()
{
    set_single_ai_session test %1 codex
    TEST_CURRENT_SESSION='test'
    TEST_CLIENT_SESSIONS_SNAPSHOT='other'
    selected_session='other'

    collect_sessions

    TEST_CLIENT_SESSIONS_SNAPSHOT='test'
    collect_sessions

    assert_eq test "$selected_session" 'cursor should align with attached session'
}

# These regression tests verify the stable transition threshold, spinner normalization, and pane generation resets.
run_test 'one unchanged sample should not immediately stop gradient' desired_one_stable_sample_keeps_running
run_test 'spinner changes in captured body should normalize away' desired_spinner_in_body_is_normalized
run_test 'new pane generation should discard previous fingerprint' desired_new_pane_generation_starts_active
run_test 'sidebar click/focus change should not trigger gradient' desired_sidebar_click_does_not_trigger_gradient
run_test 'terminal resize should not trigger gradient' desired_resize_does_not_trigger_gradient
run_test 'client session switch should not trigger gradient' desired_client_session_switch_does_not_trigger_gradient
run_test 'client session switch aligns sidebar cursor' desired_client_session_switch_aligns_cursor
finish_tests
