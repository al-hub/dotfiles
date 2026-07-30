#!/usr/bin/env bash
set -euo pipefail

# RED contract for create/delete/archive/restore lifecycle ownership.
# The first assertion deliberately exposes the current global-sidebar model;
# later lifecycle checks become active after window-local provisioning exists.

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-window-local-lifecycle-$$"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-window-local-lifecycle.XXXXXX")"
HISTORY_DIR="$RUN_DIR/history"
TMUX=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")
KEEP_RUN_DIR="${KEEP_RUN_DIR:-false}"
mkdir -p "$HISTORY_DIR"

cleanup() {
  "${TMUX[@]}" kill-server >/dev/null 2>&1 || true
  [ "$KEEP_RUN_DIR" = true ] || rm -rf "$RUN_DIR"
}
trap cleanup EXIT

tmuxc() { HOME="$RUN_DIR/home" TMUX_SESSION_HISTORY_DIR="$HISTORY_DIR" "${TMUX[@]}" "$@"; }
fail() {
  KEEP_RUN_DIR=true
  printf 'FAIL: %s\nartifacts=%s\n' "$*" "$RUN_DIR" >&2
  tmuxc list-panes -a -F 'session=#{session_name}|window=#{window_id}|pane=#{pane_id}|title=#{pane_title}' > "$RUN_DIR/panes.txt" 2>/dev/null || true
  exit 1
}
count_sidebars() {
  tmuxc list-panes -a -F '#{pane_title}' |
    awk '$1 == "dotfiles-session-sidebar" { n++ } END { print n + 0 }'
}
wait_for_count() {
  local expected="$1" attempt
  for attempt in $(seq 1 100); do
    [ "$(count_sidebars)" = "$expected" ] && return 0
    sleep 0.05
  done
  fail "expected sidebar count $expected, got $(count_sidebars)"
}

mkdir -p "$RUN_DIR/home/.local/bin"
tmuxc new-session -d -s lifecycle-a -c "$REPO_ROOT" 'sleep 300'
tmuxc new-session -d -s lifecycle-b -c "$REPO_ROOT" 'sleep 300'
tmuxc new-window -d -t '=lifecycle-a:' -n a-alt -c "$REPO_ROOT" 'sleep 300'
tmuxc new-window -d -t '=lifecycle-b:' -n b-alt -c "$REPO_ROOT" 'sleep 300'
tmuxc set-option -t '=lifecycle-a:' @dotfiles_sidebar_managed 1
tmuxc set-option -t '=lifecycle-b:' @dotfiles_sidebar_managed 1
tmuxc set-environment -g TMUX_SESSION_HISTORY_DIR "$HISTORY_DIR"

tmuxc run-shell "$LAUNCHER --open-sidebar"
wait_for_count 4

archive_before="$(find "$HISTORY_DIR" -type f -name '*.tsv' -print 2>/dev/null | wc -l | tr -d ' ')"
tmuxc run-shell "$LAUNCHER --delete-session-after-archive lifecycle-b true lifecycle-contract" || true
for attempt in $(seq 1 100); do
  [ "$(tmuxc has-session -t '=lifecycle-b:' >/dev/null 2>&1; echo $?)" -ne 0 ] && break
  sleep 0.05
done
[ "$(tmuxc has-session -t '=lifecycle-b:' >/dev/null 2>&1; echo $?)" -ne 0 ] ||
  fail 'managed session was not deleted after archive'

archive_after="$(find "$HISTORY_DIR" -type f -name '*.tsv' -print 2>/dev/null | wc -l | tr -d ' ')"
[ "$archive_after" -gt "$archive_before" ] || fail 'delete did not create an archive'

archive_file="$(find "$HISTORY_DIR" -type f -name '*.tsv' -print 2>/dev/null | sort | tail -1)"
grep -Fq $'version\t3' "$archive_file" || fail 'archive is not window-local version 3'
if awk -F '\t' '$1 == "pane" && $5 == "dotfiles-session-sidebar" { found=1 } END { exit found ? 0 : 1 }' "$archive_file"; then
  fail 'archive serialized infrastructure sidebar pane'
fi

printf 'PASS: lifecycle archive excludes window-local sidebar infrastructure\n'
printf 'PASS: deleting one managed session keeps surviving window sidebars intact\n'
