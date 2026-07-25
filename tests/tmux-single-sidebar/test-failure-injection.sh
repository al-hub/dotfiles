#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
SOCKET="dotfiles-single-sidebar-fault-$$"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-sidebar-fault.XXXXXX")"
CLIENT_PID=""
TMUX=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")

cleanup()
{
    "${TMUX[@]}" kill-server >/dev/null 2>&1 || true
    [ -n "$CLIENT_PID" ] && kill "$CLIENT_PID" >/dev/null 2>&1 || true
    rm -rf "$RUN_DIR"
}
trap cleanup EXIT

"${TMUX[@]}" new-session -d -s fault-a -c "$REPO_ROOT" 'sleep 60'
"${TMUX[@]}" new-window -d -t '=fault-a:' -n second -c "$REPO_ROOT" 'sleep 60'
"${TMUX[@]}" split-window -d -t '=fault-a:0' -h -b -l 35 "$REPO_ROOT/scripts/tmux-session-launcher --sidebar"
for attempt in $(seq 1 50); do
    [ "$("${TMUX[@]}" list-panes -a -F '#{pane_title}' | awk '$0 == "dotfiles-session-sidebar" { count++ } END { print count + 0 }')" -eq 1 ] && break
    sleep 0.05
done

script -qefc "${TMUX[*]} attach-session -t fault-a" "$RUN_DIR/client.log" >/dev/null 2>&1 &
CLIENT_PID=$!
for attempt in $(seq 1 50); do
    [ "$("${TMUX[@]}" list-clients 2>/dev/null | wc -l | tr -d ' ')" -ge 1 ] && break
    sleep 0.05
done
sleep 0.3

"${TMUX[@]}" set-environment -g TMUX_SESSION_LAUNCHER_FAIL_STEP move
sidebar_before="$("${TMUX[@]}" list-panes -a -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
"${TMUX[@]}" select-window -t '=fault-a:1'
sleep 0.4
sidebar_after="$("${TMUX[@]}" list-panes -a -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
[ "$sidebar_before" = "$sidebar_after" ]
[ "$("${TMUX[@]}" list-panes -t '=fault-a:0' -F '#{pane_title}' | awk '$0 == "dotfiles-session-sidebar" { count++ } END { print count + 0 }')" -eq 1 ]
printf 'PASS: injected move failure preserves sidebar pane and source window\n'
