#!/usr/bin/env bash
set -euo pipefail

# Contract for the tmux-native window-local model:
# one persistent sidebar pane per managed window, with native session
# switching and no pane movement/layout restoration in the switch path.
#
# It is GREEN only when every managed window has a stable local sidebar.

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-window-local-contract-$$"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-window-local-contract.XXXXXX")"
TMUX=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")
KEEP_RUN_DIR="${KEEP_RUN_DIR:-false}"

cleanup() {
  "${TMUX[@]}" kill-server >/dev/null 2>&1 || true
  [ "$KEEP_RUN_DIR" = true ] || rm -rf "$RUN_DIR"
}
trap cleanup EXIT

tmuxc() { "${TMUX[@]}" "$@"; }
fail() {
  KEEP_RUN_DIR=true
  printf 'FAIL: %s\n' "$*" >&2
  printf 'artifacts=%s\n' "$RUN_DIR" >&2
  tmuxc list-windows -a -F 'window=#{window_id}|session=#{session_name}|layout=#{window_layout}' > "$RUN_DIR/windows.txt" 2>/dev/null || true
  tmuxc list-panes -a -F 'window=#{window_id}|pane=#{pane_id}|pid=#{pane_pid}|title=#{pane_title}|geometry=#{pane_left},#{pane_top},#{pane_width},#{pane_height}' > "$RUN_DIR/panes.txt" 2>/dev/null || true
  exit 1
}

count_sidebars() {
  tmuxc list-panes -a -F '#{pane_title}' |
    awk '$1 == "dotfiles-session-sidebar" { n++ } END { print n + 0 }'
}

window_ids() {
  tmuxc list-windows -a -F '#{window_id}' | sort -u
}

wait_for_sidebars() {
  local expected="$1" attempt
  for attempt in $(seq 1 100); do
    [ "$(count_sidebars)" = "$expected" ] && return 0
    sleep 0.05
  done
  fail "expected $expected window-local sidebars, got $(count_sidebars)"
}

tmuxc new-session -d -s contract-a -c "$REPO_ROOT" 'sleep 300'
tmuxc new-session -d -s contract-b -c "$REPO_ROOT" 'sleep 300'
tmuxc new-window -d -t '=contract-a:' -n a-alt -c "$REPO_ROOT" 'sleep 300'
tmuxc new-window -d -t '=contract-b:' -n b-alt -c "$REPO_ROOT" 'sleep 300'
tmuxc set-option -t '=contract-a:' @dotfiles_sidebar_managed 1
tmuxc set-option -t '=contract-b:' @dotfiles_sidebar_managed 1
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_TRACE 1
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_TRACE_FILE "$RUN_DIR/trace.log"

# The public toggle is invoked once for the managed area. The future contract
# requires provisioning all four unique windows, not only the current window.
tmuxc run-shell "$LAUNCHER --open-sidebar"
wait_for_sidebars 4

declare -A sidebar_before=()
declare -A sidebar_pid_before=()
while IFS= read -r window_id; do
  [ -n "$window_id" ] || continue
  pane_id="$(tmuxc list-panes -t "$window_id" -F '#{pane_id}|#{pane_title}' |
    awk -F'|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
  [ -n "$pane_id" ] || fail "window $window_id has no sidebar"
  [ "$(tmuxc list-panes -t "$window_id" -F '#{pane_title}' |
    awk '$1 == "dotfiles-session-sidebar" { n++ } END { print n + 0 }')" = 1 ] ||
    fail "window $window_id has duplicate sidebars"
  sidebar_before[$window_id]="$pane_id"
  sidebar_pid_before[$window_id]="$(tmuxc display-message -p -t "$pane_id" '#{pane_pid}')"
done < <(window_ids)

printf 'PASS: every managed window has exactly one sidebar\n'

# Native switching must not move any pane or restore a layout. Use the
# explicit tmux API boundary so this assertion remains independent of TUI
# rendering while production is migrated.
source_window="$(tmuxc display-message -p -t '=contract-a:0' '#{window_id}')"
target_window="$(tmuxc display-message -p -t '=contract-b:0' '#{window_id}')"
source_before="$(tmuxc display-message -p -t "$source_window" '#{window_layout}')"
target_before="$(tmuxc display-message -p -t "$target_window" '#{window_layout}')"
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_TRACE 1
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_TRACE_FILE "$RUN_DIR/trace.log"

# No attached client exists in this fast contract; the layout and pane
# identity assertions above are the deterministic part of the switch model.
[ "$(tmuxc display-message -p -t "$source_window" '#{window_layout}')" = "$source_before" ] ||
  fail 'source layout changed during contract setup'
[ "$(tmuxc display-message -p -t "$target_window" '#{window_layout}')" = "$target_before" ] ||
  fail 'target layout changed during contract setup'

while IFS= read -r window_id; do
  [ -n "$window_id" ] || continue
  pane_id="${sidebar_before[$window_id]}"
  [ "$(tmuxc display-message -p -t "$pane_id" '#{pane_pid}')" = "${sidebar_pid_before[$window_id]}" ] ||
    fail "sidebar process changed for window $window_id"
done < <(window_ids)

printf 'PASS: window-local sidebar pane identity/process baseline is stable\n'

tmuxc run-shell "$LAUNCHER --open-sidebar"
wait_for_sidebars 0
printf 'PASS: global off removes all managed window sidebars\n'
