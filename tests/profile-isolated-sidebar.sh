#!/usr/bin/env bash
# Reproducible attached-client baseline for the repository launcher.
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="profile-isolated-$$"
RUN_DIR="${TMPDIR:-/tmp}/tmux-sidebar-profile-$$"
HISTORY_DIR="$RUN_DIR/history"
RAW_FILE="${PROFILE_RAW_FILE:-}"
CLIENT_PID=""
PROFILE_SECONDS="${PROFILE_SECONDS:-3}"

usage()
{
    printf 'Usage: %s [--raw-file PATH]\n' "$0"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --raw-file)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            RAW_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

mkdir -p "$HISTORY_DIR" "$RUN_DIR/bin"
cp /bin/bash "$RUN_DIR/bin/codex"

tmuxc()
{
    tmux -L "$SOCKET" "$@"
}

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

wait_for_session()
{
    local expected="$1" deadline=$(( $(now_ms) + 30000 ))
    while [ "$(now_ms)" -lt "$deadline" ]; do
        [ "$(tmuxc list-clients -F '#{session_name}' 2>/dev/null | head -n 1)" = "$expected" ] && return 0
        sleep 0.05
    done
    return 1
}

wait_for_session_exists()
{
    local expected="$1" deadline=$(( $(now_ms) + 30000 ))
    while [ "$(now_ms)" -lt "$deadline" ]; do
        tmuxc has-session -t "=$expected" 2>/dev/null && return 0
        sleep 0.05
    done
    return 1
}

wait_for_pane_text()
{
    local pane="$1" pattern="$2" deadline=$(( $(now_ms) + 30000 ))
    while [ "$(now_ms)" -lt "$deadline" ]; do
        tmuxc capture-pane -p -t "$pane" 2>/dev/null | grep -Eq "$pattern" && return 0
        sleep 0.05
    done
    return 1
}

sidebar_for()
{
    tmuxc list-panes -t "=$1:" -F '#{pane_id}|#{pane_title}' 2>/dev/null |
        awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }'
}

wait_for_sidebar()
{
    local session="$1" pane deadline=$(( $(now_ms) + 30000 ))
    while [ "$(now_ms)" -lt "$deadline" ]; do
        pane="$(sidebar_for "$session")"
        if [ -n "$pane" ]; then
            printf '%s\n' "$pane"
            return 0
        fi
        sleep 0.05
    done
    return 1
}

open_sidebar_direct()
{
    local session="$1" pane
    pane="$(tmuxc split-window -d -P -F '#{pane_id}' -t "=$session:" \
        -h -b -l 35 "$LAUNCHER --sidebar")"
    tmuxc select-pane -t "$pane" -T dotfiles-session-sidebar
    wait_for_pane_text "$pane" '^sessions' || return 1
    printf '%s\n' "$pane"
}

toggle_sidebar_via_work_pane()
{
    local session="$1" work
    work="$(tmuxc list-panes -t "=$session:" -F '#{pane_id}|#{pane_title}' |
        awk -F '|' '$2 != "dotfiles-session-sidebar" { print $1; exit }')"
    [ -n "$work" ] || return 1
    tmuxc send-keys -l -t "$work" "$LAUNCHER --open-sidebar"
    tmuxc send-keys -t "$work" Enter
}

wait_for_sidebar_absent()
{
    local session="$1" deadline=$(( $(now_ms) + 30000 ))
    while [ "$(now_ms)" -lt "$deadline" ]; do
        [ -z "$(sidebar_for "$session")" ] && return 0
        sleep 0.05
    done
    return 1
}

wait_for_grid()
{
    local pane="$1" output="$2" deadline=$(( $(now_ms) + 30000 )) count width
    while [ "$(now_ms)" -lt "$deadline" ]; do
        tmuxc capture-pane -p -J -t "$pane" > "$output"
        width="$(awk '{ if (length > max) max=length } END { print max+0 }' "$output")"
        count="$(grep -Ec '^>\*? ' "$output" || true)"
        [ "$width" -gt 0 ] && [ "$count" -eq 1 ] && return 0
        sleep 0.05
    done
    return 1
}

proc_ticks()
{
    awk '{ print $14 + $15 + $16 + $17 }' "/proc/$1/stat"
}

measure_process()
{
    local pid="$1" seconds="$2" start_ticks end_ticks start_ms end_ms rss peak_rss=0 attempt
    start_ticks="$(proc_ticks "$pid")"
    start_ms="$(now_ms)"
    for attempt in $(seq 1 $((seconds * 10))); do
        : "$attempt"
        rss="$(awk '/^VmRSS:/ { print $2 }' "/proc/$pid/status")"
        [ "${rss:-0}" -gt "$peak_rss" ] && peak_rss="$rss"
        sleep 0.1
    done
    end_ticks="$(proc_ticks "$pid")"
    end_ms="$(now_ms)"
    awk -v ticks="$((end_ticks - start_ticks))" -v hz="$(getconf CLK_TCK)" \
        -v elapsed="$((end_ms - start_ms))" -v rss="$peak_rss" \
        'BEGIN { cpu=ticks * 100000 / hz / elapsed; if (cpu < 0.005) cpu=0; printf "%.2f,%d", cpu, rss }'
}

emit()
{
    printf 'METRIC\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
}

echo "Starting controlled sidebar baseline (socket: $SOCKET)"
tmuxc new-session -d -x 100 -y 30 -s baseline-1
tmuxc set-environment -g TMUX_SESSION_HISTORY_DIR "$HISTORY_DIR"
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_DEBUG 0
for i in $(seq 2 8); do
    tmuxc new-session -d -s "baseline-$i"
done

LIBGL_ALWAYS_SOFTWARE=1 XMODIFIERS='' urxvt -pe "" -geometry 100x30 \
    -title tmux-sidebar-baseline -e tmux -L "$SOCKET" attach-session -t baseline-1 &
CLIENT_PID=$!
wait_for_client || { echo "ERROR: attached urxvt client did not start" >&2; exit 1; }

sidebar="$(open_sidebar_direct baseline-1)"
[ -n "$sidebar" ] || { echo "ERROR: sidebar did not open" >&2; exit 1; }
sidebar_pid="$(tmuxc display-message -p -t "$sidebar" '#{pane_pid}')"

idle="$(measure_process "$sidebar_pid" "$PROFILE_SECONDS")"
emit idle_cpu_percent "${idle%,*}" percent PASS
emit idle_peak_rss_kb "${idle#*,}" KiB PASS

work_pane="$(tmuxc list-panes -t '=baseline-2:' -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 != "dotfiles-session-sidebar" { print $1; exit }')"
tmuxc send-keys -t "$work_pane" "$RUN_DIR/bin/codex -c 'while :; do printf tick; sleep 0.1; done'" Enter
sleep 6
active="$(measure_process "$sidebar_pid" "$PROFILE_SECONDS")"
emit active_cpu_percent "${active%,*}" percent PASS
emit active_peak_rss_kb "${active#*,}" KiB PASS
tmuxc send-keys -t "$work_pane" C-c

react_start="$(now_ms)"
tmuxc send-keys -t "$sidebar" j
if wait_for_pane_text "$sidebar" '^>  baseline-2'; then
    reactivity_ms=$(( $(now_ms) - react_start ))
    emit key_reactivity_ms "$reactivity_ms" ms PASS
else
    emit key_reactivity_ms 5000 ms FAIL
    exit 1
fi

switch_start="$(now_ms)"
tmuxc send-keys -t "$sidebar" Enter
if wait_for_session baseline-2; then
    switch_ms=$(( $(now_ms) - switch_start ))
    emit session_switch_ms "$switch_ms" ms PASS
else
    emit session_switch_ms 5000 ms FAIL
    exit 1
fi

archive_session=baseline-archive
tmuxc new-session -d -s "$archive_session" -c "$REPO_ROOT"
tmuxc split-window -d -t "=$archive_session:" -v -c "$REPO_ROOT/tests"
expected_panes="$(tmuxc list-panes -t "=$archive_session:" | wc -l)"
expected_windows="$(tmuxc list-windows -t "=$archive_session:" | wc -l)"
archive_start="$(now_ms)"
tmuxc run-shell "$LAUNCHER --delete-session-after-archive $archive_session true"
archive_ms=$(( $(now_ms) - archive_start ))
archive_file="$(find "$HISTORY_DIR" -type f -name '*baseline-archive*.tsv' -print -quit)"
if [ -n "$archive_file" ] && ! tmuxc has-session -t "=$archive_session" 2>/dev/null; then
    emit archive_ms "$archive_ms" ms PASS
    emit archive_bytes "$(wc -c < "$archive_file")" bytes PASS
else
    emit archive_ms "$archive_ms" ms FAIL
    exit 1
fi

sidebar="$(sidebar_for baseline-2)"
restore_start="$(now_ms)"
tmuxc send-keys -t "$sidebar" o
wait_for_pane_text "$sidebar" '^open:' || { emit restore_ms 5000 ms FAIL; exit 1; }
tmuxc send-keys -t "$sidebar" Space
wait_for_pane_text "$sidebar" '^>x ' || { emit restore_ms 5000 ms FAIL; exit 1; }
tmuxc send-keys -t "$sidebar" Enter
if wait_for_session baseline-archive; then
    restore_ms=$(( $(now_ms) - restore_start ))
    actual_panes="$(tmuxc list-panes -t '=baseline-archive:' -F '#{pane_title}' | awk '$0 != "dotfiles-session-sidebar" { count++ } END { print count+0 }')"
    actual_windows="$(tmuxc list-windows -t '=baseline-archive:' | wc -l)"
    if [ "$actual_panes" = "$expected_panes" ] && [ "$actual_windows" = "$expected_windows" ]; then
        emit restore_ms "$restore_ms" ms PASS
        emit restore_integrity 100 percent PASS
    else
        echo "ERROR: restored panes $actual_panes/$expected_panes, windows $actual_windows/$expected_windows" >&2
        emit restore_ms "$restore_ms" ms FAIL
        emit restore_integrity 0 percent FAIL
        exit 1
    fi
else
    emit restore_ms 5000 ms FAIL
    exit 1
fi

tmuxc switch-client -t '=baseline-2'
wait_for_session baseline-2
sidebar="$(sidebar_for baseline-2)"
toggle_sidebar_via_work_pane baseline-2
wait_for_sidebar_absent baseline-2 || { echo "ERROR: sidebar did not close" >&2; exit 1; }
layout_before="$(tmuxc display-message -p -t '=baseline-2:' '#{window_layout}')"
layout_status=PASS
for ignored in 1 2 3; do
    : "$ignored"
    toggle_sidebar_via_work_pane baseline-2
    sidebar="$(wait_for_sidebar baseline-2 || true)"
    [ -n "$sidebar" ] && wait_for_pane_text "$sidebar" '^sessions' || true
    [ -n "$sidebar" ] || { layout_status=FAIL; break; }
    toggle_sidebar_via_work_pane baseline-2
    wait_for_sidebar_absent baseline-2 || { layout_status=FAIL; break; }
done
layout_after="$(tmuxc display-message -p -t '=baseline-2:' '#{window_layout}')"
[ "$layout_before" = "$layout_after" ] || layout_status=FAIL
emit layout_preserved "$([ "$layout_status" = PASS ] && echo 100 || echo 0)" percent "$layout_status"

sidebar="$(open_sidebar_direct baseline-2)"
tmuxc resize-pane -t "$sidebar" -x 15
sleep 0.2
tmuxc resize-pane -t "$sidebar" -x 35
wait_for_pane_text "$sidebar" '^sessions' || { emit grid_max_columns 0 columns FAIL; exit 1; }
pane_width="$(tmuxc display-message -p -t "$sidebar" '#{pane_width}')"
capture="$RUN_DIR/sidebar.txt"
wait_for_grid "$sidebar" "$capture" || { emit grid_max_columns 0 columns FAIL; exit 1; }
max_width="$(awk '{ if (length > max) max=length } END { print max+0 }' "$capture")"
cursor_count="$(grep -Ec '^>\*? ' "$capture" || true)"
grid_status=PASS
[ "$max_width" -le "$pane_width" ] || grid_status=FAIL
[ "$cursor_count" -eq 1 ] || grid_status=FAIL
emit grid_max_columns "$max_width" columns "$grid_status"
emit grid_pane_columns "$pane_width" columns "$grid_status"
emit cursor_count "$cursor_count" count "$grid_status"

commit="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
dirty=false
[ -n "$(git -C "$REPO_ROOT" status --short)" ] && dirty=true
printf 'META\tcommit\t%s\nMETA\tdirty\t%s\nMETA\ttmux\t%s\nMETA\tgeometry\t100x30\n' \
    "$commit" "$dirty" "$(tmux -V)"

if [ -n "$RAW_FILE" ]; then
    # The caller captures stdout; this option records provenance only.
    printf 'META\traw_file\t%s\n' "$RAW_FILE"
fi

[ "$layout_status" = PASS ] && [ "$grid_status" = PASS ]
