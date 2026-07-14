#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib.sh"
load_launcher_functions

fingerprint_for()
{
    TEST_CAPTURE="$1"
    session_ai_fingerprint_for_pane '%1'
}

test_last_line_is_ignored()
{
    first="$(fingerprint_for $'header\nbody\nspinner 1')"
    second="$(fingerprint_for $'header\nbody\nspinner 2')"

    assert_eq "$first" "$second" 'last line normalization'
}

test_body_change_updates_fingerprint()
{
    first="$(fingerprint_for $'header\nbody one\nprompt')"
    second="$(fingerprint_for $'header\nbody two\nprompt')"

    assert_ne "$first" "$second" 'body fingerprint change'
}

test_blank_lines_do_not_change_fingerprint()
{
    first="$(fingerprint_for $'header\n\nbody\nprompt')"
    second="$(fingerprint_for $'header\nbody\n\n\nprompt')"

    assert_eq "$first" "$second" 'blank line normalization'
}

run_test 'fingerprint ignores volatile final line' test_last_line_is_ignored
run_test 'fingerprint changes with captured body' test_body_change_updates_fingerprint
run_test 'fingerprint ignores blank lines' test_blank_lines_do_not_change_fingerprint
finish_tests
