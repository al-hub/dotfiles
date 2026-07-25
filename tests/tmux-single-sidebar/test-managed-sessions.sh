#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
SOCKET="dotfiles-single-sidebar-managed-$$"
TMUX=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")

cleanup()
{
    "${TMUX[@]}" kill-server >/dev/null 2>&1 || true
}
trap cleanup EXIT

"${TMUX[@]}" new-session -d -s managed-a -c "$REPO_ROOT" 'sleep 60'
"${TMUX[@]}" new-session -d -s external-a -c "$REPO_ROOT" 'sleep 60'
"${TMUX[@]}" split-window -d -t '=managed-a:' -h -b -l 35 "$REPO_ROOT/scripts/tmux-session-launcher --sidebar"
sleep 0.5
"${TMUX[@]}" run-shell -b "$REPO_ROOT/scripts/tmux-session-launcher --delete-all-sessions-after-archive false"

for attempt in $(seq 1 50); do
    "${TMUX[@]}" has-session -t '=managed-a:' >/dev/null 2>&1 || break
    sleep 0.05
done
! "${TMUX[@]}" has-session -t '=managed-a:' >/dev/null 2>&1
"${TMUX[@]}" has-session -t '=external-a:' >/dev/null 2>&1
printf 'PASS: d All removes managed sessions and preserves external sessions\n'
