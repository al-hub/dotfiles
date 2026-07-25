#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
SOCKET="dotfiles-single-sidebar-layout-metadata-$$"
TMUX=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")

cleanup()
{
    "${TMUX[@]}" kill-server >/dev/null 2>&1 || true
}
trap cleanup EXIT

"${TMUX[@]}" new-session -d -s metadata-source -c "$REPO_ROOT" 'sleep 60'
"${TMUX[@]}" new-session -d -s metadata-target -c "$REPO_ROOT" 'sleep 60'
"${TMUX[@]}" split-window -d -t '=metadata-target:' -h -c "$REPO_ROOT" 'sleep 60'
"${TMUX[@]}" split-window -d -t '=metadata-target:0.1' -v -c "$REPO_ROOT" 'sleep 60'
"${TMUX[@]}" split-window -d -t '=metadata-source:' -h -b -l 35 "$REPO_ROOT/scripts/tmux-session-launcher --sidebar"
for attempt in $(seq 1 50); do
    [ "$("${TMUX[@]}" list-panes -a -F '#{pane_title}' | awk '$0 == "dotfiles-session-sidebar" { count++ } END { print count + 0 }')" -eq 1 ] && break
    sleep 0.05
done

"${TMUX[@]}" run-shell -b "$REPO_ROOT/scripts/tmux-session-launcher --ensure-sidebar-session metadata-target"
sleep 0.5

[ "$("${TMUX[@]}" list-panes -a -F '#{session_name}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')" = metadata-source ]
[ "$("${TMUX[@]}" list-panes -t '=metadata-target:' -F '#{pane_title}' | awk '$0 == "dotfiles-session-sidebar" { count++ } END { print count + 0 }')" -eq 0 ]
printf 'PASS: multi-pane target without sidebar metadata rolls back the move\n'
