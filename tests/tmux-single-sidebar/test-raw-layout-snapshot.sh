#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-sidebar-layout.XXXXXX")"
SOCKET="dotfiles-single-sidebar-layout-$$"
TMUX=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")

cleanup()
{
    "${TMUX[@]}" kill-server >/dev/null 2>&1 || true
    rm -rf "$RUN_DIR"
}
trap cleanup EXIT

"${TMUX[@]}" new-session -d -s raw-layout -c "$REPO_ROOT" 'sleep 60'
"${TMUX[@]}" set-environment -g TMUX_SESSION_HISTORY_DIR "$RUN_DIR/history"
"${TMUX[@]}" split-window -d -t '=raw-layout:' -h -b -l 35 "$REPO_ROOT/scripts/tmux-session-launcher --sidebar"
for attempt in $(seq 1 50); do
    [ "$("${TMUX[@]}" list-panes -a -F '#{pane_title}' | awk '$0 == "dotfiles-session-sidebar" { count++ } END { print count + 0 }')" -eq 1 ] && break
    sleep 0.05
done
work_pane="$("${TMUX[@]}" list-panes -t '=raw-layout:' -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 != "dotfiles-session-sidebar" { print $1; exit }')"
"${TMUX[@]}" split-window -d -t "$work_pane" -h -c "$REPO_ROOT" 'sleep 60'
"${TMUX[@]}" run-shell -b "$REPO_ROOT/scripts/tmux-session-launcher --delete-session-after-archive raw-layout true"
for attempt in $(seq 1 100); do
    "${TMUX[@]}" has-session -t '=raw-layout:' >/dev/null 2>&1 || break
    sleep 0.05
done
archive_path="$(find "$RUN_DIR/history" -type f -name '*.tsv' -print -quit 2>/dev/null || true)"
[ -f "$archive_path" ]
[ "$(awk -F '\t' '$1 == "version" { print $2; exit }' "$archive_path")" = 3 ]
window_line="$(awk -F '\t' '$1 == "window" { print; exit }' "$archive_path")"
layout="$(printf '%s\n' "$window_line" | awk -F '\t' '{ print $5 }')"
pane_records="$(awk '$1 == "window" { seen=1; next } seen && $1 == "pane" { count++ } seen && $1 == "endwindow" { print count + 0; exit }' "$archive_path")"
v2_pane_fields="$(awk -F '\t' '$1 == "pane" { print NF; exit }' "$archive_path")"
layout_records="$(printf '%s\n' "$layout" | awk '{ count=0; while (match($0, /[0-9]+x[0-9]+,[0-9]+,[0-9]+,[0-9]+/)) { count++; $0=substr($0, RSTART+RLENGTH) } print count }')"
[ -n "$layout" ]
[ "$pane_records" -gt 1 ]
[ "$v2_pane_fields" -ge 10 ]
[ "$layout_records" -ge "$pane_records" ]
printf 'PASS: raw split archive stores a non-empty layout with work-pane topology\n'
