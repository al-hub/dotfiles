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

    collect_sessions
    set_single_ai_session test %2 codex
    collect_sessions

    assert_eq active "${session_cli_state[0]}" 'new pane generation state'
    assert_eq true "${session_animate[0]}" 'new pane generation animation'
}

# These encode the agreed improvement targets without changing production behavior yet.
run_xfail 'one unchanged sample should not immediately stop gradient' desired_one_stable_sample_keeps_running
run_xfail 'spinner changes in captured body should normalize away' desired_spinner_in_body_is_normalized
run_xfail 'new pane generation should discard previous fingerprint' desired_new_pane_generation_starts_active
finish_tests
