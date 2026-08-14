#!/usr/bin/env bash
# Unit test for tmux port & adapter isolation in scripts/lib/sidebar_port_tmux.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/sidebar_port_tmux.sh"

MOCK_MANAGED_SESSION=""

sidebar_tmux_cmd() {
    local cmd="$1"
    shift
    case "$cmd" in
        display-message)
            local fmt=""
            while [ $# -gt 0 ]; do
                if [ "$1" = "-p" ]; then
                    fmt="$2"
                    shift 2
                else
                    shift
                fi
            done
            if [ "$fmt" = "#S" ]; then
                echo "mock_session_1"
                return 0
            elif [ "$fmt" = "#{pane_current_path}" ]; then
                echo "/tmp/mock_path"
                return 0
            fi
            ;;
        switch-client)
            echo "SWITCH_SUCCESS"
            return 0
            ;;
        has-session)
            local target=""
            while [ $# -gt 0 ]; do
                if [ "$1" = "-t" ]; then
                    target="$2"
                    shift 2
                else
                    shift
                fi
            done
            if [ "$target" = "=existing_session:" ]; then
                return 0
            fi
            return 1
            ;;
        set-option)
            local session_target="$2"
            local opt_name="$3"
            local val="$4"
            if [ "$val" = "1" ]; then
                MOCK_MANAGED_SESSION="$session_target"
            fi
            return 0
            ;;
        show-option)
            local session_target=""
            while [ $# -gt 0 ]; do
                if [ "$1" = "-t" ]; then
                    session_target="$2"
                    shift 2
                else
                    shift
                fi
            done
            if [ "$session_target" = "$MOCK_MANAGED_SESSION" ]; then
                echo "1"
            else
                echo "0"
            fi
            return 0
            ;;
    esac
    return 1
}

# 1. Test get_current_session
res="$(sidebar_port_get_current_session)"
[ "$res" = "mock_session_1" ] || { echo "FAIL: get_current_session expected 'mock_session_1', got '$res'"; exit 1; }

# 2. Test get_current_path
path_res="$(sidebar_port_get_current_path)"
[ "$path_res" = "/tmp/mock_path" ] || { echo "FAIL: get_current_path expected '/tmp/mock_path', got '$path_res'"; exit 1; }

# 3. Test switch_client
switch_res="$(sidebar_port_switch_client "/dev/pts/1" "target_session")"
[ "$switch_res" = "SWITCH_SUCCESS" ] || { echo "FAIL: switch_client with tty failed"; exit 1; }

switch_no_tty="$(sidebar_port_switch_client "" "target_session")"
[ "$switch_no_tty" = "SWITCH_SUCCESS" ] || { echo "FAIL: switch_client without tty failed"; exit 1; }

! sidebar_port_switch_client "/dev/pts/1" "" || { echo "FAIL: switch_client expected failure with empty target"; exit 1; }

# 4. Test session_exists
sidebar_port_session_exists "existing_session" || { echo "FAIL: session_exists expected true for existing_session"; exit 1; }
! sidebar_port_session_exists "nonexistent_session" || { echo "FAIL: session_exists expected false for nonexistent_session"; exit 1; }
! sidebar_port_session_exists "" || { echo "FAIL: session_exists expected false for empty session"; exit 1; }

# 5 & 6. Test mark_session_managed & session_is_managed
! sidebar_port_session_is_managed "=managed_sess:" || { echo "FAIL: session_is_managed expected false before mark"; exit 1; }
sidebar_port_mark_session_managed "managed_sess"
sidebar_port_session_is_managed "managed_sess" || { echo "FAIL: session_is_managed expected true after mark"; exit 1; }

echo "PASS: tmux port unit tests"
