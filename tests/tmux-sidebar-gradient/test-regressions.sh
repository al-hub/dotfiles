#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib.sh"
load_launcher_functions

declare -A TEST_FINGERPRINT_BY_PANE=()
TEST_CHILD_AI=false

eval "$(declare -f session_ai_fingerprint_for_pane | sed '1s/session_ai_fingerprint_for_pane/production_fingerprint_for_pane/')"

session_ai_fingerprint_for_pane()
{
    printf '%s\n' "${TEST_FINGERPRINT_BY_PANE[$1]:-}"
}

pane_has_ai_cli_process()
{
    [ "$TEST_CHILD_AI" = true ]
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

desired_stable_busy_session_skips_full_snapshot()
{
    set_single_ai_session test %1 sleep
    collect_sessions
    selected_session=test
    last_state_refresh_epoch=0
    : > "$TEST_TMUX_CALL_LOG"

    refresh_sidebar_state_if_due || true

    if grep -qx 'list-sessions' "$TEST_TMUX_CALL_LOG"; then
        printf '  stable busy session unexpectedly triggered full snapshot\n' >&2
        return 1
    fi
    [ "$last_state_refresh_epoch" -gt 0 ] || {
        printf '  stable busy session did not advance refresh timestamp\n' >&2
        return 1
    }
}

desired_command_transition_reopens_state_scan()
{
    set_single_ai_session test %1 sleep
    collect_sessions
    selected_session=test
    last_state_refresh_epoch=0

    set_single_ai_session test %1 codex
    TEST_FINGERPRINT_BY_PANE['%1']='new-ai-output'
    : > "$TEST_TMUX_CALL_LOG"
    refresh_sidebar_state_if_due || true

    grep -qx 'list-sessions' "$TEST_TMUX_CALL_LOG" || {
        printf '  command transition did not reopen full snapshot\n' >&2
        return 1
    }
    assert_eq active "${session_cli_state[0]}" \
        'command transition should detect AI state'
}

desired_shell_child_ai_reopens_state_scan()
{
    set_single_ai_session test %1 bash
    TEST_CHILD_AI=false
    collect_sessions
    selected_session=test
    last_state_refresh_epoch=0

    TEST_CHILD_AI=true
    TEST_FINGERPRINT_BY_PANE['%1']='shell-child-ai-output'
    refresh_sidebar_state_if_due || true

    assert_eq active "${session_cli_state[0]}" \
        'shell child AI should be detected despite stable pane command'
}

desired_shell_without_child_skips_state_snapshot()
{
    set_single_ai_session test %1 bash
    TEST_CHILD_AI=false
    collect_sessions
    selected_session=test
    last_state_refresh_epoch=0
    : > "$TEST_TMUX_CALL_LOG"

    refresh_sidebar_state_if_due || true

    if grep -qx 'list-sessions' "$TEST_TMUX_CALL_LOG"; then
        printf '  shell without AI child unexpectedly triggered full snapshot\n' >&2
        return 1
    fi
}

desired_unchanged_session_reuses_status_and_seed_cache()
{
    set_single_ai_session test %1 sleep 100
    collect_sessions
    first_status="${session_status[0]}"
    first_seed="${session_animation_seed[0]}"

    collect_sessions

    assert_eq "$first_status" "${session_status[0]}" \
        'unchanged session should reuse status cache'
    assert_eq "$first_seed" "${session_animation_seed[0]}" \
        'unchanged session should reuse animation seed cache'
    assert_eq 100 "${cached_session_animation_seed_created[test]}" \
        'seed cache should retain session generation'
}

desired_target_refresh_preserves_other_session_panes()
{
    TEST_CURRENT_SESSION=one
    TEST_SESSIONS_SNAPSHOT=$'one\t100\t0\ntwo\t101\t0'
    TEST_PANES_SNAPSHOT=$'one\t%1\twork\tsleep\t0\t101\ntwo\t%2\twork\tsleep\t0\t102'
    collect_sessions
    other_snapshot="${cached_session_panes_snapshot[two]}"
    other_command_signature="${cached_session_command_signature[two]}"

    TEST_PANES_SNAPSHOT=$'one\t%3\twork\tcodex\t0\t103\ntwo\t%2\twork\tsleep\t0\t102'
    collect_sessions false one

    assert_eq "$other_snapshot" "${cached_session_panes_snapshot[two]}" \
        'target refresh should preserve other session pane snapshot'
    assert_eq "$other_command_signature" "${cached_session_command_signature[two]}" \
        'target refresh should preserve other session command signature'
    assert_eq '%3' "${session_ai_direct_pane_id[one]:-}" \
        'target refresh should replace target pane metadata'
}

desired_target_refresh_replaces_only_cached_row()
{
    TEST_CURRENT_SESSION=one
    TEST_SESSIONS_SNAPSHOT=$'one\t100\t0\ntwo\t101\t0'
    TEST_PANES_SNAPSHOT=$'one\t%1\twork\tsleep\t0\t101\ntwo\t%2\twork\tsleep\t0\t102'
    collect_sessions
    session_status[1]=row-cache-sentinel

    collect_sessions false one

    assert_eq row-cache-sentinel "${session_status[1]}" \
        'stable target refresh should preserve non-target row'

    TEST_SESSIONS_SNAPSHOT=$'two\t101\t0\none\t100\t0'
    collect_sessions false one

    assert_eq two "${session_names[0]}" \
        'session order change should rebuild row order'
    assert_eq one "${session_names[1]}" \
        'session order change should retain all rows'
}

desired_session_sidebar_ensure_uses_cached_snapshot()
{
    TEST_CURRENT_SESSION=one
    TEST_SESSIONS_SNAPSHOT=$'one\t100\t0\ntwo\t101\t0'
    TEST_PANES_SNAPSHOT=$'one\t%1\twork\tsleep\t0\t101\ntwo\t%2\tdotfiles-session-sidebar\tbash\t0\t102'
    collect_sessions
    : > "$TEST_TMUX_CALL_LOG"

    ensure_session_sidebar two

    assert_eq true "$ensure_session_sidebar_cache_hit" \
        'sidebar ensure should use cached pane snapshot'
    if grep -qx 'list-panes' "$TEST_TMUX_CALL_LOG"; then
        printf '  cached sidebar ensure unexpectedly queried tmux list-panes\n' >&2
        return 1
    fi
}

# These regression tests verify the stable transition threshold, spinner normalization, and pane generation resets.
run_test 'one unchanged sample should not immediately stop gradient' desired_one_stable_sample_keeps_running
run_test 'spinner changes in captured body should normalize away' desired_spinner_in_body_is_normalized
run_test 'new pane generation should discard previous fingerprint' desired_new_pane_generation_starts_active
run_test 'sidebar click/focus change should not trigger gradient' desired_sidebar_click_does_not_trigger_gradient
run_test 'terminal resize should not trigger gradient' desired_resize_does_not_trigger_gradient
run_test 'client session switch should not trigger gradient' desired_client_session_switch_does_not_trigger_gradient
run_test 'client session switch aligns sidebar cursor' desired_client_session_switch_aligns_cursor
run_test 'stable busy session skips full snapshot' desired_stable_busy_session_skips_full_snapshot
run_test 'pane command transition reopens state scan' desired_command_transition_reopens_state_scan
run_test 'shell child AI reopens state scan' desired_shell_child_ai_reopens_state_scan
run_test 'shell without child AI skips state snapshot' desired_shell_without_child_skips_state_snapshot
run_test 'unchanged session reuses status and seed cache' desired_unchanged_session_reuses_status_and_seed_cache
run_test 'target refresh preserves other session pane metadata' desired_target_refresh_preserves_other_session_panes
run_test 'target refresh replaces only cached row' desired_target_refresh_replaces_only_cached_row
finish_tests
