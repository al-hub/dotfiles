#!/usr/bin/env bash
# Sequential top-to-bottom navigation scenario for the v0.6.7 sidebar.
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="sidebar-navigation-$$"
RUN_DIR="${TMPDIR:-/tmp}/tmux-sidebar-navigation-$$"
HISTORY_DIR="$RUN_DIR/history"
CLIENT_PID=""
POLL_INTERVAL="${NAVIGATION_POLL_INTERVAL:-0.01}"

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

mkdir -p "$HISTORY_DIR"

tmuxc()
{
    tmux -L "$SOCKET" "$@"
}

now_ms()
{
    printf '%s\n' "$(( $(date +%s%N) / 1000000 ))"
}

wait_for_client()
{
    local deadline=$(( $(now_ms) + 10000 ))
    while [ "$(now_ms)" -lt "$deadline" ]; do
        tmuxc list-clients -F '#{client_tty}' 2>/dev/null | grep -q . && return 0
        sleep 0.05
    done
    return 1
}

wait_for_text()
{
    local pane="$1" pattern="$2" deadline=$(( $(now_ms) + 30000 )) capture=''
    while [ "$(now_ms)" -lt "$deadline" ]; do
        capture="$(tmuxc capture-pane -p -t "$pane" 2>/dev/null || true)"
        printf '%s\n' "$capture" | grep -Eq "$pattern" && return 0
        sleep "$POLL_INTERVAL"
    done
    printf 'DEBUG: wait pattern=%s\n%s\n' "$pattern" "$capture" >&2
    return 1
}

sidebar_for()
{
    tmuxc list-panes -a -F '#{pane_id}|#{pane_title}' 2>/dev/null |
        awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }'
}

emit_step()
{
    printf 'STEP\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
}

tmuxc new-session -d -s nav-01 -x 100 -y 30 -c "$REPO_ROOT" 'sleep 60'
for index in $(seq -w 2 10); do
    tmuxc new-session -d -s "nav-$index" -c "$REPO_ROOT" 'sleep 60'
done

LIBGL_ALWAYS_SOFTWARE=1 XMODIFIERS='' urxvt -pe '' -geometry 100x30 \
    -title tmux-sidebar-navigation -e tmux -L "$SOCKET" attach-session -t nav-01 &
CLIENT_PID=$!
wait_for_client

sidebar="$(tmuxc split-window -d -P -F '#{pane_id}' -t '=nav-01:' -h -b -l 35 \
    "TMUX_SESSION_HISTORY_DIR=$HISTORY_DIR $LAUNCHER --sidebar")"
tmuxc select-pane -t "$sidebar" -T dotfiles-session-sidebar
wait_for_text "$sidebar" '^>\*? +nav-01'

printf 'META\tgeometry\t100x30\n'
printf 'META\tsessions\t10\n'
printf 'META\tstart_session\tnav-01\n'
printf 'META\tpoll_interval_ms\t%s\n' "$POLL_INTERVAL"

scenario_start="$(now_ms)"
previous_ms="$scenario_start"
for index in $(seq -w 2 10); do
    step_start="$(now_ms)"
    tmuxc send-keys -t "$sidebar" j
    wait_for_text "$sidebar" "^>\*? +nav-$index"
    observed="$(now_ms)"
    step_ms=$((observed - step_start))
    cumulative_ms=$((observed - scenario_start))
    gap_ms=$((observed - previous_ms))
    emit_step "$((10#$index - 1))" "nav-$index" "$step_ms" "$cumulative_ms/$gap_ms"
    previous_ms="$observed"
done

final_grid="$(tmuxc capture-pane -p -t "$sidebar")"
cursor_count="$(printf '%s\n' "$final_grid" | grep -Ec '^> ?\*? ' || true)"
final_ok=FAIL
[ "$cursor_count" -eq 1 ] &&
    printf '%s\n' "$final_grid" | grep -Eq '^>  nav-10' && final_ok=PASS

printf 'SUMMARY\tfinal_cursor\t%s\n' "$cursor_count"
printf 'SUMMARY\tfinal_target\tnav-10\t%s\n' "$final_ok"
