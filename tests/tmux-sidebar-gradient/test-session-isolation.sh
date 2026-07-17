#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib.sh"
load_launcher_functions

declare -A TEST_FINGERPRINT_BY_PANE=()

session_ai_fingerprint_for_pane()
{
    printf '%s\n' "${TEST_FINGERPRINT_BY_PANE[$1]:-}"
}

test_sessions_animate_independently()
{
    TEST_CURRENT_SESSION='first'
    current_session='first'
    TEST_SESSIONS_SNAPSHOT=$'first\t100\nsecond\t200'
    TEST_PANES_SNAPSHOT=$'first\t%1\twork\tcodex\nsecond\t%2\twork\tclaude'
    TEST_FINGERPRINT_BY_PANE['%1']='first-a'
    TEST_FINGERPRINT_BY_PANE['%2']='second-a'

    collect_sessions
    assert_eq true "${session_animate[0]}" 'first initial animation'
    assert_eq true "${session_animate[1]}" 'second initial animation'

    TEST_FINGERPRINT_BY_PANE['%1']='first-b'
    collect_sessions false first
    assert_eq true "${session_animate[0]}" 'first changed animation'
    assert_eq true "${session_animate[1]}" 'second single stable animation'

    collect_sessions
    assert_eq true "${session_animate[0]}" 'first single stable animation'
    assert_eq false "${session_animate[1]}" 'second stable animation'
    assert_eq active "${session_cli_state[0]}" 'first changed state'
    assert_eq waiting "${session_cli_state[1]}" 'second stable state'

    TEST_FINGERPRINT_BY_PANE['%2']='second-b'
    collect_sessions false second
    assert_eq false "${session_animate[0]}" 'first stable animation'
    assert_eq true "${session_animate[1]}" 'second changed animation'
}

run_test 'multiple sessions keep independent gradient state' test_sessions_animate_independently
finish_tests
