#!/usr/bin/env bash
set -euo pipefail
SCENARIO_NAME=mouse-selection
export SCENARIO_NAME
export TMUX_SESSION_LAUNCHER_TRACE=1
export TMUX_SESSION_LAUNCHER_DEBUG=1
source "$(dirname -- "$BASH_SOURCE")/test-interactive-common.sh"

setup_interactive_test
create_session mouse-a
create_session mouse-b
focus_sidebar
wait_until "mouse sidebar ready" sidebar_ready
wait_until "mouse sidebar stable" wait_sidebar_stable

before_sidebar="$(sidebar_pane_id)"
row="$(sidebar_row_for mouse-b)"
[ -n "$row" ]
mouse_line=$((row - 1))
send_keys $'\033[<0;8;'"$mouse_line"$'M'
send_keys $'\033[<0;8;'"$mouse_line"$'m'
wait_until "mouse dispatch mouse-b" "wait_trace 'mouse.select.target session=mouse-b'"
wait_until "mouse selection mouse-b" "wait_session mouse-b"
wait_until "single sidebar after mouse selection" "wait_sidebar_count 1"
[ "$(sidebar_pane_id)" = "$before_sidebar" ]

row="$(sidebar_row_for mouse-a)"
mouse_line=$((row - 1))
send_keys $'\033[<0;8;'"$mouse_line"$'M'
send_keys $'\033[<0;8;'"$mouse_line"$'m'
wait_until "mouse dispatch mouse-a" "wait_trace 'mouse.select.target session=mouse-a'"
wait_until "mouse selection mouse-a" "wait_session mouse-a"
wait_until "sidebar focus after mouse selection" sidebar_active
echo "PASS: attached-PTY mouse session selection preserves the single sidebar"
