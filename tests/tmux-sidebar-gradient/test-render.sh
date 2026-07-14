#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib.sh"
load_launcher_functions

test_gradient_changes_by_frame()
{
    SIDEBAR_ANIMATION_ENABLED=true
    animation_frame=0
    frame_zero="$(print_session_name 'alpha' 8 true 0)"
    animation_frame=1
    frame_one="$(print_session_name 'alpha' 8 true 0)"

    assert_ne "$frame_zero" "$frame_one" 'gradient frame output'
    assert_contains "$frame_zero" $'\033[38;5;' 'gradient ANSI prefix'
    assert_contains "$frame_zero" $'\033[0m' 'gradient ANSI reset'
}

test_waiting_name_has_no_gradient()
{
    SIDEBAR_ANIMATION_ENABLED=true
    animation_frame=0
    output="$(print_session_name 'alpha' 8 false 0)"

    assert_eq 'alpha   ' "$output" 'plain padded session name'
    assert_not_contains "$output" $'\033[' 'plain name ANSI sequence'
}

test_animation_can_be_disabled_globally()
{
    SIDEBAR_ANIMATION_ENABLED=false
    animation_frame=0
    output="$(print_session_name 'alpha' 5 true 0)"

    assert_eq 'alpha' "$output" 'globally disabled gradient'
    assert_not_contains "$output" $'\033[' 'disabled gradient ANSI sequence'
}

run_test 'renderer changes ANSI colors between frames' test_gradient_changes_by_frame
run_test 'renderer omits gradient for waiting state' test_waiting_name_has_no_gradient
run_test 'renderer respects global animation disable' test_animation_can_be_disabled_globally
finish_tests
