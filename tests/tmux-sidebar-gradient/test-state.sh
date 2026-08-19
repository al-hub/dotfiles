#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib.sh"
load_launcher_functions

declare -gA TEST_FINGERPRINT_BY_PANE=()

session_ai_fingerprint_for_pane()
{
    printf '%s\n' "${TEST_FINGERPRINT_BY_PANE[$1]:-}"
}

test_active_waiting_active_transition()
{
    set_single_ai_session test %1 codex
    TEST_FINGERPRINT_BY_PANE['%1']='fp-a'

    collect_sessions
    assert_eq active "${session_cli_state[0]}" 'initial CLI state'
    assert_eq true "${session_animate[0]}" 'initial animation state'

    collect_sessions
    assert_eq active "${session_cli_state[0]}" 'single stable sample CLI state'
    assert_eq true "${session_animate[0]}" 'single stable sample animation state'

    collect_sessions
    assert_eq waiting "${session_cli_state[0]}" 'stable fingerprint CLI state'
    assert_eq false "${session_animate[0]}" 'stable fingerprint animation state'

    TEST_FINGERPRINT_BY_PANE['%1']='fp-b'
    collect_sessions false test
    assert_eq active "${session_cli_state[0]}" 'changed fingerprint CLI state'
    assert_eq true "${session_animate[0]}" 'changed fingerprint animation state'
}

test_shell_only_session_is_idle()
{
    set_single_ai_session test %1 bash
    collect_sessions

    assert_eq idle "${session_cli_state[0]}" 'shell-only CLI state'
    assert_eq false "${session_animate[0]}" 'shell-only animation state'
}

run_test 'state transitions active to waiting and back to active' test_active_waiting_active_transition
run_test 'shell-only session does not animate' test_shell_only_session_is_idle
finish_tests
