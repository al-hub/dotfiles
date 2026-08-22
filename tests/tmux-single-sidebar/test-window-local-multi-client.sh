#!/usr/bin/env bash
set -euo pipefail

# RED structural contract for multi-client and linked-window behavior.

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-window-local-multi-client-$$"
TMUX=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")
KEEP_RUN_DIR="${KEEP_RUN_DIR:-false}"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-window-local-multi-client.XXXXXX")"

cleanup() {
  "${TMUX[@]}" kill-server >/dev/null 2>&1 || true
  [ "$KEEP_RUN_DIR" = true ] || rm -rf "$RUN_DIR"
}
trap cleanup EXIT
tmuxc() { "${TMUX[@]}" "$@"; }
fail() {
  KEEP_RUN_DIR=true
  printf 'FAIL: %s\nartifacts=%s\n' "$*" "$RUN_DIR" >&2
  tmuxc list-clients -F '#{client_tty}|#{session_name}|#{window_id}' > "$RUN_DIR/clients.txt" 2>/dev/null || true
  tmuxc list-panes -a -F '#{session_name}|#{window_id}|#{pane_id}|#{pane_title}' > "$RUN_DIR/panes.txt" 2>/dev/null || true
  exit 1
}
count_sidebars() {
  tmuxc list-panes -a -F '#{pane_title}' |
    awk '$1 == "dotfiles-session-sidebar" { n++ } END { print n + 0 }'
}

tmuxc new-session -d -s client-a -c "$REPO_ROOT" 'sleep 300'
tmuxc new-session -d -s client-b -c "$REPO_ROOT" 'sleep 300'
tmuxc new-window -d -t '=client-a:' -n shared -c "$REPO_ROOT" 'sleep 300'
tmuxc link-window -s '=client-a:1' -t '=client-b:1'
tmuxc set-option -t '=client-a:' @dotfiles_sidebar_managed 1
tmuxc set-option -t '=client-b:' @dotfiles_sidebar_managed 1
tmuxc run-shell "$LAUNCHER --open-sidebar"

for attempt in $(seq 1 100); do
  [ "$(count_sidebars)" -ge 2 ] && break
  sleep 0.05
done
[ "$(count_sidebars)" -ge 2 ] || fail 'managed windows were not provisioned for both clients'

shared_window="$(tmuxc display-message -p -t '=client-a:1' '#{window_id}')"
shared_count="$(tmuxc list-panes -t "$shared_window" -F '#{pane_title}' |
  awk '$1 == "dotfiles-session-sidebar" { n++ } END { print n + 0 }')"
[ "$shared_count" = 1 ] || fail "linked window has $shared_count sidebars"

printf 'PASS: linked window owns one physical sidebar pane\n'
printf 'PASS: multi-client contract preserves tmux shared-window semantics\n'
