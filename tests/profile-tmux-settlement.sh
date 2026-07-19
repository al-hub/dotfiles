#!/usr/bin/env bash
# Isolate tmux client settlement from sidebar rendering and profile polling.
set -euo pipefail

SOCKET="tmux-settlement-$$"
RUN_DIR="${TMPDIR:-/tmp}/tmux-settlement-$$"
HOME_DIR="$RUN_DIR/home"
CONFIG="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)/dotfiles/tmux.conf"
CLIENT_PID=""
RUNS="${SETTLEMENT_RUNS:-3}"
SEPARATION_RUN_ID="${SEPARATION_RUN_ID:-settlement-$$}"

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

wait_for_client()
{
    local deadline=$(( $(now_ms) + 10000 ))
    while [ "$(now_ms)" -lt "$deadline" ]; do
        tmuxc list-clients -F '#{client_tty}' 2>/dev/null | grep -q . && return 0
        sleep 0.02
    done
    return 1
}

client_tty()
{
    tmuxc list-clients -F '#{client_tty}' 2>/dev/null | head -n 1
}

client_session()
{
    tmuxc list-clients -F '#{session_name}' 2>/dev/null | head -n 1
}

wait_for_session()
{
    local expected="$1" deadline=$(( $(now_ms) + 10000 ))
    while [ "$(now_ms)" -lt "$deadline" ]; do
        [ "$(client_session)" = "$expected" ] && return 0
        sleep 0.01
    done
    return 1
}

tmuxc new-session -d -x 100 -y 30 -s settlement-a
tmuxc new-session -d -s settlement-b
printf 'META\tseparation_run_id\t%s\n' "$SEPARATION_RUN_ID"
HOME="$HOME_DIR" LIBGL_ALWAYS_SOFTWARE=1 XMODIFIERS='' urxvt -pe "" -geometry 100x30 \
    -title tmux-settlement -e tmux -L "$SOCKET" attach-session -t settlement-a &
CLIENT_PID=$!
wait_for_client
tty="$(client_tty)"

for index in $(seq 1 "$RUNS"); do
    command_start="$(now_ms)"
    tmuxc switch-client -c "$tty" -t '=settlement-b'
    command_end="$(now_ms)"
    wait_start="$command_end"
    wait_for_session settlement-b
    settled_end="$(now_ms)"
    printf 'SETTLEMENT\t%d\tcommand_ms\t%s\n' "$index" "$((command_end - command_start))"
    printf 'SETTLEMENT\t%d\tclient_settlement_ms\t%s\n' "$index" "$((settled_end - wait_start))"

    tmuxc switch-client -c "$tty" -t '=settlement-a'
    wait_for_session settlement-a
done

printf 'SUMMARY\truns\t%s\n' "$RUNS"
