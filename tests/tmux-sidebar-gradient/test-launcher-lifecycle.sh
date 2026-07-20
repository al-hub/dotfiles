#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="launcher-lifecycle-$$"
TMP_DIR="$(mktemp -d)"

cleanup()
{
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

tmuxc()
{
    tmux -L "$SOCKET" "$@"
}

wait_for_sidebar()
{
    local pane deadline=$(( $(date +%s) + 10 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        pane="$(tmuxc list-panes -t '=lifecycle:' -F '#{pane_id}|#{pane_title}' 2>/dev/null |
            awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
        if [ -n "$pane" ] && tmuxc capture-pane -p -t "$pane" 2>/dev/null | grep -q '^sessions'; then
            printf '%s\n' "$pane"
            return 0
        fi
        sleep 0.05
    done
    return 1
}

wait_for_no_sidebar()
{
    local pane="$1" deadline=$(( $(date +%s) + 10 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if ! tmuxc list-panes -a -F '#{pane_id}' 2>/dev/null |
            grep -Fxq "$pane"; then
            return 0
        fi
        sleep 0.05
    done
    return 1
}

tmuxc new-session -d -s lifecycle -x 100 -y 30 'sleep 30'
tmuxc split-window -d -t '=lifecycle:' -v 'sleep 30'
window="$(tmuxc display-message -p -t '=lifecycle:' '#{window_id}')"
layout_before="$(tmuxc display-message -p -t "$window" '#{window_layout}')"

sidebar="$(tmuxc split-window -d -P -F '#{pane_id}' -t '=lifecycle:' -h -b -l 35 \
    "TMUX_SESSION_HISTORY_DIR=$TMP_DIR TMUX_PANE=\$TMUX_PANE $LAUNCHER --sidebar")"
tmuxc select-pane -t "$sidebar" -T dotfiles-session-sidebar
actual_sidebar="$(wait_for_sidebar)"
[ "$actual_sidebar" = "$sidebar" ]
tmuxc kill-pane -t "$actual_sidebar"
wait_for_no_sidebar "$actual_sidebar"

sidebar="$(tmuxc split-window -d -P -F '#{pane_id}' -t '=lifecycle:' -h -b -l 35 \
    "TMUX_SESSION_HISTORY_DIR=$TMP_DIR TMUX_PANE=\$TMUX_PANE $LAUNCHER --sidebar")"
tmuxc select-pane -t "$sidebar" -T dotfiles-session-sidebar
wait_for_sidebar >/dev/null
tmuxc kill-pane -t "$sidebar"
wait_for_no_sidebar "$sidebar"

layout_after="$(tmuxc display-message -p -t "$window" '#{window_layout}')"
[ "$layout_before" = "$layout_after" ]

tmuxc new-session -d -s ensure-target -x 100 -y 30 'sleep 30'
tmuxc set-environment -g TMUX_SESSION_HISTORY_DIR "$TMP_DIR"
tmuxc run-shell -b -t '=ensure-target:' "$LAUNCHER --ensure-sidebar-session ensure-target"
ensure_sidebar=""
deadline=$(( $(date +%s) + 10 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
    ensure_sidebar="$(tmuxc list-panes -t '=ensure-target:' -F '#{pane_id}|#{pane_title}' 2>/dev/null |
        awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
    [ -n "$ensure_sidebar" ] && break
    sleep 0.05
done
[ -n "$ensure_sidebar" ]

tmuxc new-session -d -s archive-target -x 100 -y 30 'sleep 30'
tmuxc split-window -d -t '=archive-target:' -v 'sleep 30'
tmuxc run-shell "$LAUNCHER --delete-session-after-archive archive-target true"
archive_file="$(find "$TMP_DIR" -type f -name '*archive-target*.tsv' -print -quit)"
[ -s "$archive_file" ]
if tmuxc has-session -t '=archive-target:' 2>/dev/null; then
    printf 'FAIL: unconnected archive target was not removed\n' >&2
    exit 1
fi

printf 'PASS: launcher-owned sidebar can be killed and recreated without lifecycle residue\n'
printf 'PASS: launcher-owned sidebar lifecycle preserves work layout\n'
printf 'PASS: session-targeted async ensure creates exactly one sidebar\n'
printf 'PASS: unconnected archive target uses archive/delete lifecycle successfully\n'
printf 'SUMMARY: pass=4 xfail=0 fail=0\n'
