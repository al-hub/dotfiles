#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
SOCKET="dotfiles-single-sidebar-multi-$$"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-sidebar-multi.XXXXXX")"
CLIENT_A_PID=""
CLIENT_B_PID=""
TMUX=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")

cleanup()
{
    "${TMUX[@]}" kill-server >/dev/null 2>&1 || true
    [ -n "$CLIENT_A_PID" ] && kill "$CLIENT_A_PID" >/dev/null 2>&1 || true
    [ -n "$CLIENT_B_PID" ] && kill "$CLIENT_B_PID" >/dev/null 2>&1 || true
    rm -rf "$RUN_DIR"
}
trap cleanup EXIT

"${TMUX[@]}" new-session -d -s multi-a -c "$REPO_ROOT" 'sleep 60'
"${TMUX[@]}" split-window -d -t '=multi-a:0' -h -b -l 35 "$REPO_ROOT/scripts/tmux-session-launcher --sidebar"
for attempt in $(seq 1 50); do
    [ "$("${TMUX[@]}" list-panes -a -F '#{pane_title}' | awk '$0 == "dotfiles-session-sidebar" { count++ } END { print count + 0 }')" -eq 1 ] && break
    sleep 0.05
done

script -qefc "${TMUX[*]} attach-session -t multi-a" "$RUN_DIR/client-a.log" >/dev/null 2>&1 &
CLIENT_A_PID=$!
for attempt in $(seq 1 50); do
    [ "$("${TMUX[@]}" list-clients 2>/dev/null | wc -l | tr -d ' ')" -ge 1 ] && break
    sleep 0.05
done
script -qefc "${TMUX[*]} attach-session -t multi-a" "$RUN_DIR/client-b.log" >/dev/null 2>&1 &
CLIENT_B_PID=$!
for attempt in $(seq 1 50); do
    [ "$("${TMUX[@]}" list-clients 2>/dev/null | wc -l | tr -d ' ')" -ge 2 ] && break
    sleep 0.05
done
sleep 0.2

sidebar_before="$("${TMUX[@]}" list-panes -a -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
owner_client="$(${TMUX[@]} list-clients -F '#{client_control_mode}|#{client_tty}' |
    awk -F '|' '$1 != 1 { print $2; exit }')"
[ -n "$owner_client" ]
"${TMUX[@]}" set-option -g @dotfiles_sidebar_owner_client "$owner_client"
"${TMUX[@]}" run-shell -b "$REPO_ROOT/scripts/tmux-session-launcher --open-sidebar"
sleep 0.3
sidebar_after="$("${TMUX[@]}" list-panes -a -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"

[ "$sidebar_before" = "$sidebar_after" ]
[ "$("${TMUX[@]}" list-clients 2>/dev/null | wc -l | tr -d ' ')" -ge 2 ]
printf 'PASS: non-owner client cannot toggle the shared sidebar\n'
