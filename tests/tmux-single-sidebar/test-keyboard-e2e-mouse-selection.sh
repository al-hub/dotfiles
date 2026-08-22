#!/usr/bin/env bash
set -euo pipefail
SCENARIO_NAME=mouse-selection
export SCENARIO_NAME
export TMUX_SESSION_LAUNCHER_TRACE=1
export TMUX_SESSION_LAUNCHER_DEBUG=1
source "$(dirname -- "$BASH_SOURCE")/test-interactive-common.sh"

setup_interactive_test
# Keep creation out of this measurement: the scenario under test is the
# attached-PTY mouse press/release and session switch. Provision the two
# managed targets before sending mouse bytes so creation hooks cannot race the
# observation boundary.
tmuxc new-session -d -s mouse-a -c "$REPO_ROOT" 'sleep 300'
tmuxc new-session -d -s mouse-b -c "$REPO_ROOT" 'sleep 300'
for mouse_session in mouse-a mouse-b; do
  mouse_window="$(tmuxc display-message -p -t "=$mouse_session:" '#{window_id}')"
  tmuxc set-option -w -t "$mouse_window" @dotfiles_sidebar_managed 1
  tmuxc run-shell -b "$LAUNCHER --ensure-sidebar-window $mouse_window"
done
wait_until "mouse target sidebars" "[ \"\$(count_sidebars)\" -ge 3 ]"
focus_sidebar
wait_until "mouse sidebar ready" sidebar_ready
wait_until "mouse sidebar stable" wait_sidebar_stable
wait_until "mouse-b listed in sidebar" "[ -n \"\$(sidebar_row_for mouse-b)\" ]"

mouse_sidebar="$(sidebar_pane_id)"
[ -n "$mouse_sidebar" ] || {
  printf 'FAIL: mouse sidebar pane is absent\n' >&2
  tmuxc list-clients -F '#{client_tty}|#{session_name}|#{window_id}|#{pane_id}' >&2 || true
  tmuxc list-panes -a -F '#{session_name}|#{window_id}|#{pane_id}|#{pane_title}|#{pane_active}' >&2 || true
  exit 1
}
tmuxc select-pane -t "$mouse_sidebar"
wait_until "mouse sidebar focus" sidebar_active

before_sidebar="$mouse_sidebar"
wait_until "mouse-b visible row" "[ -n \"\$(sidebar_row_for mouse-b)\" ]"
row="$(sidebar_row_for mouse-b)"
[ -n "$row" ]
# capture-pane row numbers are already the terminal's one-based screen line;
# tmux converts the SGR coordinate to pane-relative mouse_y before passing it
# to the launcher, which performs the single normalization step.
mouse_line="$row"
printf 'INFO: mouse.send target=mouse-b pane=%s line=%s x=8\n' "$before_sidebar" "$mouse_line" >&2
send_keys $'\033[<0;8;'"$mouse_line"$'M'
send_keys $'\033[<0;8;'"$mouse_line"$'m'
wait_until "mouse dispatch mouse-b" "wait_trace_regex 'mouse.select.target.*session=mouse-b'"
wait_until "mouse selection mouse-b" "wait_session mouse-b"
wait_until "managed sidebar count after mouse-b" "[ \"\$(count_sidebars)\" -ge 3 ]"
mouse_b_sidebar="$(sidebar_pane_id)"
[ -n "$mouse_b_sidebar" ]

wait_until "mouse-a visible row" "[ -n \"\$(sidebar_row_for mouse-a)\" ]"
row="$(sidebar_row_for mouse-a)"
mouse_line="$row"
printf 'INFO: mouse.send target=mouse-a pane=%s line=%s x=8\n' "$(sidebar_pane_id)" "$mouse_line" >&2
send_keys $'\033[<0;8;'"$mouse_line"$'M'
send_keys $'\033[<0;8;'"$mouse_line"$'m'
wait_until "mouse dispatch mouse-a" "wait_trace_regex 'mouse.select.target.*session=mouse-a'"
wait_until "mouse selection mouse-a" "wait_session mouse-a"
wait_until "sidebar focus after mouse selection" sidebar_active
mouse_a_sidebar="$(sidebar_pane_id)"
[ -n "$mouse_a_sidebar" ]
echo "PASS: attached-PTY mouse session selection preserves managed window-local sidebars"
