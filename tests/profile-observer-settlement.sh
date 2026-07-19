#!/usr/bin/env bash
# Compare capture-pane polling with a pipe-pane raw-stream observer.
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
PIPE_OBSERVER="$REPO_ROOT/tests/profile-pipe-observer.pl"
SOCKET="observer-settlement-$$"
RUN_DIR="${TMPDIR:-/tmp}/observer-settlement-$$"
HOME_DIR="$RUN_DIR/home"
CONFIG="$REPO_ROOT/dotfiles/tmux.conf"
CLIENT_PID=""
RUNS="${OBSERVER_RUNS:-3}"
POLL_INTERVAL="${OBSERVER_POLL_INTERVAL:-0.01}"
SEPARATION_RUN_ID="${SEPARATION_RUN_ID:-observer-$$}"

mkdir -p "$HOME_DIR"
tmuxc() { HOME="$HOME_DIR" tmux -L "$SOCKET" -f "$CONFIG" "$@"; }
now_ms() { printf '%s\n' "$(( $(date +%s%N) / 1000000 ))"; }

cleanup()
{
    tmuxc kill-server >/dev/null 2>&1 || true
    if [ -n "$CLIENT_PID" ]; then
        kill "$CLIENT_PID" >/dev/null 2>&1 || true
        wait "$CLIENT_PID" 2>/dev/null || true
    fi
    rm -rf "$RUN_DIR"
}
trap cleanup EXIT INT TERM

client_tty()
{
    tmuxc list-clients -F '#{client_tty}' 2>/dev/null | head -n 1
}

wait_for_client()
{
    local deadline=$(( $(now_ms) + 10000 ))
    while [ "$(now_ms)" -lt "$deadline" ]; do
        [ -n "$(client_tty)" ] && return 0
        sleep 0.02
    done
    return 1
}

wait_for_cursor()
{
    local pane="$1" target="$2" deadline=$(( $(now_ms) + 10000 ))
    while [ "$(now_ms)" -lt "$deadline" ]; do
        if tmuxc capture-pane -p -t "$pane" 2>/dev/null |
            grep -Eq "^>\\*? +$target"; then
            return 0
        fi
        sleep "$POLL_INTERVAL"
    done
    return 1
}

wait_for_marker()
{
    local deadline=$(( $(now_ms) + 10000 ))
    while [ "$(now_ms)" -lt "$deadline" ]; do
        [ -s "$RUN_DIR/pipe-marker" ] && return 0
        sleep 0.005
    done
    return 1
}

tmuxc new-session -d -x 100 -y 30 -s observer-a
tmuxc new-session -d -s observer-b
printf 'META\tseparation_run_id\t%s\n' "$SEPARATION_RUN_ID"
sidebar="$(tmuxc split-window -d -P -F '#{pane_id}' -t '=observer-a:' -h -b -l 35 \
    "TMUX_SESSION_HISTORY_DIR=$RUN_DIR/history $LAUNCHER --sidebar")"
tmuxc select-pane -t "$sidebar" -T dotfiles-session-sidebar
HOME="$HOME_DIR" LIBGL_ALWAYS_SOFTWARE=1 XMODIFIERS='' urxvt -pe "" -geometry 100x30 \
    -title observer-settlement -e tmux -L "$SOCKET" attach-session -t observer-a &
CLIENT_PID=$!
wait_for_client
wait_for_cursor "$sidebar" observer-a

for index in $(seq 1 "$RUNS"); do
    capture_start="$(now_ms)"
    tmuxc send-keys -t "$sidebar" j
    wait_for_cursor "$sidebar" observer-b
    capture_end="$(now_ms)"

    tmuxc send-keys -t "$sidebar" k
    wait_for_cursor "$sidebar" observer-a
    pipe_reset_end="$(now_ms)"
    : > "$RUN_DIR/pipe-marker"
    tmuxc pipe-pane -o -t "$sidebar" \
        "perl '$PIPE_OBSERVER' '$RUN_DIR/pipe-marker' 'observer-b'"
    pipe_start="$(now_ms)"
    tmuxc send-keys -t "$sidebar" j
    wait_for_marker
    pipe_end="$(now_ms)"
    tmuxc pipe-pane -t "$sidebar"
    tmuxc send-keys -t "$sidebar" k
    wait_for_cursor "$sidebar" observer-a

    printf 'OBSERVER\t%d\tcapture_ms\t%s\n' "$index" "$((capture_end - capture_start))"
    printf 'OBSERVER\t%d\tpipe_ms\t%s\n' "$index" "$((pipe_end - pipe_start))"
    printf 'OBSERVER\t%d\tpipe_reset_ms\t%s\n' "$index" "$((pipe_reset_end - capture_end))"
done

printf 'SUMMARY\truns\t%s\n' "$RUNS"
