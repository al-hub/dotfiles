#!/usr/bin/env bash

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"

TEST_PASSES=0
TEST_FAILURES=0
TEST_XFAILS=0

pass()
{
    printf 'PASS: %s\n' "$1"
    TEST_PASSES=$((TEST_PASSES + 1))
}

fail()
{
    printf 'FAIL: %s\n' "$1" >&2
    TEST_FAILURES=$((TEST_FAILURES + 1))
}

run_test()
{
    name="$1"
    shift

    if ("$@"); then
        pass "$name"
    else
        fail "$name"
    fi
}

run_xfail()
{
    name="$1"
    shift

    if ("$@"); then
        fail "XPASS: $name"
    else
        printf 'XFAIL: %s\n' "$name"
        TEST_XFAILS=$((TEST_XFAILS + 1))
    fi
}

assert_eq()
{
    expected="$1"
    actual="$2"
    message="${3:-values differ}"

    if [ "$expected" != "$actual" ]; then
        printf '  %s: expected <%s>, got <%s>\n' "$message" "$expected" "$actual" >&2
        return 1
    fi
}

assert_ne()
{
    left="$1"
    right="$2"
    message="${3:-values unexpectedly match}"

    if [ "$left" = "$right" ]; then
        printf '  %s: both values are <%s>\n' "$message" "$left" >&2
        return 1
    fi
}

assert_contains()
{
    haystack="$1"
    needle="$2"
    message="${3:-text does not contain expected value}"

    case "$haystack" in
        *"$needle"*) return 0 ;;
    esac

    printf '  %s: missing <%s>\n' "$message" "$needle" >&2
    return 1
}

assert_not_contains()
{
    haystack="$1"
    needle="$2"
    message="${3:-text contains unexpected value}"

    case "$haystack" in
        *"$needle"*)
            printf '  %s: found <%s>\n' "$message" "$needle" >&2
            return 1
            ;;
    esac
}

finish_tests()
{
    printf 'SUMMARY: pass=%s xfail=%s fail=%s\n' "$TEST_PASSES" "$TEST_XFAILS" "$TEST_FAILURES"
    [ "$TEST_FAILURES" -eq 0 ]
}

TEST_CURRENT_SESSION="test"
TEST_CURRENT_PATH="$REPO_ROOT"
TEST_SESSIONS_SNAPSHOT=""
TEST_PANES_SNAPSHOT=""
TEST_CAPTURE=""
TEST_PANE_WIDTH=80
TEST_PANE_HEIGHT=24
TEST_CLIENT_SESSIONS_SNAPSHOT="test"
declare -A TEST_TMUX_CALL_COUNT=()
TEST_TMUX_CALL_LOG="${TMPDIR:-/tmp}/dotfiles-sidebar-test-$$.log"
rm -f "$TEST_TMUX_CALL_LOG"

# Unit tests replace tmux with deterministic snapshots before loading launcher functions.
tmux()
{
    command_name="${1:-}"
    printf '%s\n' "$command_name" >> "$TEST_TMUX_CALL_LOG"
    TEST_TMUX_CALL_COUNT["$command_name"]=$(( ${TEST_TMUX_CALL_COUNT[$command_name]:-0} + 1 ))
    shift || true

    case "$command_name" in
        display-message)
            format="${*: -1}"
            case "$format" in
                '#S') printf '%s\n' "$TEST_CURRENT_SESSION" ;;
                '#{pane_current_path}') printf '%s\n' "$TEST_CURRENT_PATH" ;;
                '#{session_activity}') printf '%s\n' "${EPOCHSECONDS:-0}" ;;
                '#{pane_pid}') return 1 ;;
                '#{pane_width}') printf '%s\n' "${TEST_PANE_WIDTH:-80}" ;;
                '#{pane_height}') printf '%s\n' "${TEST_PANE_HEIGHT:-24}" ;;
                *) return 1 ;;
            esac
            ;;
        list-sessions)
            printf '%s\n' "$TEST_SESSIONS_SNAPSHOT"
            ;;
        list-clients)
            printf '%s\n' "$TEST_CLIENT_SESSIONS_SNAPSHOT"
            ;;
        list-panes)
            format="${*: -1}"
            pane_target=""
            for ((arg_index = 1; arg_index <= $#; arg_index++)); do
                if [ "${!arg_index}" = "-t" ]; then
                    next_index=$((arg_index + 1))
                    pane_target="${!next_index}"
                    break
                fi
            done
            pane_target="${pane_target#=}"
            pane_target="${pane_target%%:}"
            pane_snapshot="$TEST_PANES_SNAPSHOT"
            if [ -n "$pane_target" ]; then
                pane_snapshot="$(awk -F '\t' -v target="$pane_target" '$1 == target' <<< "$TEST_PANES_SNAPSHOT")"
            fi
            if [ "$format" = '#{pane_id}|#{pane_current_command}' ]; then
                while IFS="$(printf '\t')" read -r pane_session pane_id pane_title pane_command rest; do
                    [ -n "$pane_id" ] || continue
                    printf '%s|%s\n' "$pane_id" "$pane_command"
                done <<EOF
$pane_snapshot
EOF
            else
                printf '%s\n' "$pane_snapshot"
            fi
            ;;
        capture-pane)
            printf '%s\n' "$TEST_CAPTURE"
            ;;
        *)
            return 1
            ;;
    esac
}

sidebar_tmux_cmd()
{
    tmux "$@"
}

load_launcher_functions()
{
    # Source all domain and presenter lib modules first
    local lib_dir="$REPO_ROOT/scripts/lib"
    local lib_file
    for lib_file in "$lib_dir"/sidebar_*.sh; do
        [ -r "$lib_file" ] && source "$lib_file"
    done

    # The launcher has no library mode, so tests omit only its final main invocation.
    # shellcheck disable=SC1090
    source <(sed '/^main "\$@"$/d' "$LAUNCHER")

    # Declarations made by source inside this helper are local to the helper in Bash.
    # Recreate the launcher's arrays globally so its functions retain their real types.
    declare -ga session_names=()
    declare -ga session_created=()
    declare -ga session_status=()
    declare -ga session_cli_state=()
    declare -gA session_ai_fingerprint=()
    declare -gA cached_session_cli_state=()
    declare -gA cached_session_ai_fingerprint=()
    declare -gA cached_session_status=()
    declare -gA cached_session_status_created=()
    declare -gA cached_session_status_activity_age=()
    declare -gA cached_session_status_busy_command=()
    declare -gA cached_session_animation_seed=()
    declare -gA cached_session_animation_seed_created=()
    declare -gA cached_session_row_index=()
    declare -gA session_activity_age_cache=()
    declare -gA session_has_busy_command=()
    declare -gA session_ai_probe_pane_ids=()
    declare -gA session_ai_direct_pane_id=()
    declare -gA cached_session_panes_snapshot=()
    declare -gA cached_session_command_signature=()
    declare -gA cached_pane_activity=()
    declare -gA cached_pane_pid=()
    declare -gA cached_pane_command=()
    declare -gA session_ai_stable_count=()
    declare -gA previous_session_animate=()
    declare -ga session_animate=()
    declare -ga session_animation_seed=()
    declare -ga session_animation_refresh_indexes=()
    declare -ga history_files=()
    declare -ga history_titles=()
    declare -ga history_checked=()
}

set_single_ai_session()
{
    session_name="${1:-test}"
    pane_id="${2:-%1}"
    command_name="${3:-codex}"
    created="${4:-100}"

    TEST_CURRENT_SESSION="$session_name"
    TEST_SESSIONS_SNAPSHOT="$(printf '%s\t%s' "$session_name" "$created")"
    TEST_PANES_SNAPSHOT="$(printf '%s\t%s\twork\t%s\t0:0:0:0\t' "$session_name" "$pane_id" "$command_name")"
}
