#!/usr/bin/env bash
# v0.6.7 reproduction profile: attached-client flow from docs/reproduction.md.
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="profile-isolated-reproduction-$$-${RANDOM}"
MAIN_RUN_DIR="${TMPDIR:-/tmp}/tmux-sidebar-reproduction-$$"
RUN_DIR="$MAIN_RUN_DIR"
HISTORY_DIR="$RUN_DIR/history"
PROFILE_HOME="$MAIN_RUN_DIR/home"
TMUX_CONFIG="$REPO_ROOT/dotfiles/tmux.conf"
CLIENT_PID=""
PROFILE_SECONDS="${PROFILE_SECONDS:-3}"
PROFILE_KEY_POLL_INTERVAL="${PROFILE_KEY_POLL_INTERVAL:-0.01}"
PROFILE_ARCHIVE_POLL_INTERVAL="${PROFILE_ARCHIVE_POLL_INTERVAL:-0.01}"
PROFILE_TRACE="${PROFILE_TRACE:-0}"
PROFILE_DEBUG="${PROFILE_DEBUG:-0}"
PROFILE_PIPE_OBSERVER="${PROFILE_PIPE_OBSERVER:-false}"
PROFILE_PIPE_OBSERVER_BLOCKING="${PROFILE_PIPE_OBSERVER_BLOCKING:-true}"
PROFILE_ANIMATION_ENABLED="${PROFILE_ANIMATION_ENABLED:-true}"
PROFILE_PERIODIC_REFRESH_DELAY="${PROFILE_PERIODIC_REFRESH_DELAY:-5.2}"
PROFILE_STATE_REFRESH_SECONDS="${PROFILE_STATE_REFRESH_SECONDS:-5}"
PROFILE_SIGNAL_TIMER_ENABLED="${PROFILE_SIGNAL_TIMER_ENABLED:-false}"
PROFILE_EVENT_LOOP_ENABLED="${PROFILE_EVENT_LOOP_ENABLED:-false}"
PROFILE_METRICS="${PROFILE_METRICS:-false}"
RAW_FILE="${PROFILE_RAW_FILE:-}"
PROFILE_KEEP_RUN_DIR="${PROFILE_KEEP_RUN_DIR:-false}"
SEPARATION_RUN_ID="${SEPARATION_RUN_ID:-reproduction-$$}"
PROFILE_PHASE="startup"
TRACE_FILE="$RUN_DIR/launcher-trace.log"
PIPE_MARKER="$RUN_DIR/pipe-marker"
PIPE_RESULT="$RUN_DIR/pipe-result"
PIPE_OBSERVER="$REPO_ROOT/tests/profile-pipe-observer.pl"
PIPE_READER_PID=""

mkdir -p "$HISTORY_DIR" "$RUN_DIR/bin" "$PROFILE_HOME/.local/bin"
cp /bin/bash "$RUN_DIR/bin/codex"
ln -s "$LAUNCHER" "$PROFILE_HOME/.local/bin/tmux-session-launcher"

tmuxc() { HOME="$PROFILE_HOME" tmux -L "$SOCKET" -f "$TMUX_CONFIG" "$@"; }

cleanup()
{
    if [ -n "$PIPE_READER_PID" ]; then
        kill "$PIPE_READER_PID" >/dev/null 2>&1 || true
        wait "$PIPE_READER_PID" 2>/dev/null || true
    fi
    tmuxc kill-server >/dev/null 2>&1 || true
    if [ -n "$CLIENT_PID" ]; then
        kill "$CLIENT_PID" >/dev/null 2>&1 || true
        wait "$CLIENT_PID" 2>/dev/null || true
    fi
    [ "$PROFILE_KEEP_RUN_DIR" = true ] || rm -rf "$RUN_DIR"
}
trap cleanup EXIT INT TERM

if [ "$PROFILE_PIPE_OBSERVER" = true ] && [ "$PROFILE_PIPE_OBSERVER_BLOCKING" = true ]; then
    mkfifo "$PIPE_MARKER"
fi

now_ms() { printf '%s\n' "$(( $(date +%s%N) / 1000000 ))"; }

emit() { printf 'METRIC\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }

wait_for_client()
{
    local deadline=$(( $(now_ms) + 10000 ))
    while [ "$(now_ms)" -lt "$deadline" ]; do
        tmuxc list-clients -F '#{client_tty}' 2>/dev/null | grep -q . && return 0
        sleep 0.05
    done
    return 1
}

client_tty_for()
{
    tmuxc list-clients -F '#{client_tty}' 2>/dev/null | head -n 1
}

client_session()
{
    tmuxc list-clients -F '#{client_tty}|#{session_name}' 2>/dev/null |
        awk -F '|' -v tty="$client_tty" '$1 == tty { print $2; exit }'
}

wait_for_client_session()
{
    local expected="$1" deadline=$(( $(now_ms) + 30000 ))
    while [ "$(now_ms)" -lt "$deadline" ]; do
        [ "$(client_session)" = "$expected" ] && return 0
        sleep 0.05
    done
    return 1
}

wait_for_session()
{
    local expected="$1" deadline=$(( $(now_ms) + 30000 ))
    while [ "$(now_ms)" -lt "$deadline" ]; do
        [ "$(client_session)" = "$expected" ] && return 0
        sleep 0.05
    done
    return 1
}

wait_for_text()
{
    local pane="$1" pattern="$2" deadline=$(( $(now_ms) + 30000 ))
    while [ "$(now_ms)" -lt "$deadline" ]; do
        tmuxc capture-pane -p -t "$pane" 2>/dev/null | grep -Eq "$pattern" && return 0
        sleep "$PROFILE_KEY_POLL_INTERVAL"
    done
    return 1
}

wait_for_archive_file()
{
    local pattern="$1" deadline=$(( $(now_ms) + 30000 )) file size previous
    while [ "$(now_ms)" -lt "$deadline" ]; do
        file="$(find "$HISTORY_DIR" -type f -name "$pattern" -print -quit)"
        if [ -n "$file" ]; then
            size="$(wc -c < "$file")"
            if [ "${size:-0}" -gt 0 ]; then
                # The launcher writes a pending file and atomically renames it
                # to the final *.tsv path, so a non-empty final file is already
                # settled. Avoid a second polling sleep in the observer.
                printf '%s\n' "$file"
                return 0
            fi
        fi
        sleep "$PROFILE_ARCHIVE_POLL_INTERVAL"
    done
    return 1
}

sidebar_for()
{
    local session="$1" pane pane_session pane_title
    while IFS='|' read -r pane pane_session pane_title; do
        if [ "$pane_session" = "$session" ] && [ "$pane_title" = "dotfiles-session-sidebar" ]; then
            printf '%s\n' "$pane"
            return 0
        fi
    done < <(tmuxc list-panes -a -F '#{pane_id}|#{session_name}|#{pane_title}' 2>/dev/null)
    return 1
}

sidebar_count_for()
{
    local session="$1"
    tmuxc list-panes -a -F '#{session_name}|#{pane_title}' 2>/dev/null |
        awk -F '|' -v session="$session" '$1 == session && $2 == "dotfiles-session-sidebar" { count++ } END { print count+0 }'
}

wait_for_sidebar()
{
    local session="$1" pane deadline=$(( $(now_ms) + 30000 ))
    while [ "$(now_ms)" -lt "$deadline" ]; do
        if [ "$(sidebar_count_for "$session")" = 1 ]; then
            pane="$(sidebar_for "$session" || true)"
            [ -n "$pane" ] && { printf '%s\n' "$pane"; return 0; }
        fi
        sleep 0.05
    done
    echo "ERROR: expected exactly one sidebar for $session" >&2
    tmuxc list-panes -a -F '#{pane_id}|#{session_name}|#{pane_title}' >&2 || true
    return 1
}

dump_profile_state()
{
    local label="$1"
    printf 'PROFILE_STATE\t%s\n' "$label" >&2
    tmuxc list-clients -F '#{client_tty}|#{session_name}' >&2 2>/dev/null || true
    tmuxc list-sessions -F '#{session_name}|#{session_attached}' >&2 2>/dev/null || true
    tmuxc list-panes -a -F '#{session_name}|#{pane_id}|#{pane_title}|#{pane_current_command}' >&2 2>/dev/null || true
    if [ -f "$RUN_DIR/launcher-debug.log" ]; then
        tail -30 "$RUN_DIR/launcher-debug.log" >&2 || true
    fi
    if [ -f "$TRACE_FILE" ]; then
        tail -30 "$TRACE_FILE" >&2 || true
    fi
}

open_sidebar_direct()
{
    local session="$1" pane
    pane="$(tmuxc split-window -d -P -F '#{pane_id}' -t "=$session:" -h -b -l 35 "$LAUNCHER --sidebar")"
    tmuxc select-pane -t "$pane" -T dotfiles-session-sidebar
    pane="$(wait_for_sidebar "$session")"
    wait_for_text "$pane" '^sessions' || return 1
    printf '%s\n' "$pane"
}

open_sidebar_via_toggle()
{
    local session="$1" work pane
    work="$(tmuxc list-panes -t "=$session:" -F '#{pane_id}|#{pane_title}|#{pane_active}' |
        awk -F '|' '$2 != "dotfiles-session-sidebar" && $3 == 1 { print $1; exit }')"
    if [ -z "$work" ]; then
        work="$(tmuxc list-panes -t "=$session:" -F '#{pane_id}|#{pane_title}' |
            awk -F '|' '$2 != "dotfiles-session-sidebar" { print $1; exit }')"
    fi
    [ -n "$work" ] || {
        echo "ERROR: no work pane for sidebar toggle in $session" >&2
        return 1
    }
    # tmux's command API cannot inject a key into the attached client's prefix
    # parser. Invoke the same launcher command bound to Ctrl+a s; selection
    # and Enter below still use send-keys on the attached sidebar pane.
    tmuxc run-shell "$LAUNCHER --open-sidebar"
    pane="$(wait_for_sidebar "$session")"
    wait_for_text "$pane" '^sessions' || return 1
    printf 'REPRO_SIDEBAR_SETUP\t%s\ttoggle\t%s\n' "$session" "$work" >&2
    printf '%s\n' "$pane"
}

proc_ticks() { awk '{ print $14 + $15 + $16 + $17 }' "/proc/$1/stat"; }

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

wait_for_selection()
{
    local pane="$1" target="$2" deadline=$(( $(now_ms) + 30000 ))
    while [ "$(now_ms)" -lt "$deadline" ]; do
        if tmuxc capture-pane -p -t "$pane" 2>/dev/null | grep -Eq "^>\\*? +$target"; then
            return 0
        fi
        sleep "$PROFILE_KEY_POLL_INTERVAL"
    done
    return 1
}

wait_for_pipe_marker()
{
    local deadline=$(( $(now_ms) + 30000 ))
    key_observed_ms=""
    while [ "$(now_ms)" -lt "$deadline" ]; do
        if [ -s "$PIPE_MARKER" ]; then
            key_observed_ms="$(awk '{ printf "%.0f\n", $1 * 1000 }' "$PIPE_MARKER")"
            return 0
        fi
        sleep "$PROFILE_KEY_POLL_INTERVAL"
    done
    return 1
}

start_pipe_observer()
{
    local target="$1"
    if [ "$PROFILE_PIPE_OBSERVER_BLOCKING" = true ]; then
        rm -f "$PIPE_RESULT"
        cat "$PIPE_MARKER" > "$PIPE_RESULT" &
        PIPE_READER_PID=$!
    else
        : > "$PIPE_MARKER"
    fi
    tmuxc pipe-pane -o -t "$2" \
        "perl '$PIPE_OBSERVER' '$PIPE_MARKER' '$target'"
}

wait_for_blocking_pipe_marker()
{
    if [ "$PROFILE_PIPE_OBSERVER_BLOCKING" = true ]; then
        wait "$PIPE_READER_PID" || return 1
        PIPE_READER_PID=""
        [ -s "$PIPE_RESULT" ] || return 1
        key_observed_ms="$(awk '{ printf "%.0f\n", $1 * 1000 }' "$PIPE_RESULT")"
        return 0
    fi
    wait_for_pipe_marker
}

trace_selection_step()
{
    local label="$1" trace_line trace_id trace_begin trace_end
    if [ ! -s "$TRACE_FILE" ]; then
        printf 'TRACE_STEP\t%s\tNA\tNA\n' "$label"
        return 0
    fi
    trace_line="$(awk '
        /selection.update.begin/ {
            id=""; for (i=1; i<=NF; i++) if ($i ~ /^id=/) id=substr($i, 4)
            begin_id=id; begin_ts=$1
        }
        /selection.update.end/ {
            id=""; for (i=1; i<=NF; i++) if ($i ~ /^id=/) id=substr($i, 4)
            if (id != "" && id == begin_id) {
                last_id=id; last_begin=begin_ts; last_end=$1
            }
        }
        END { if (last_id != "") print last_id, last_begin, last_end }
    ' "$TRACE_FILE")"
    if [ -z "$trace_line" ]; then
        printf 'TRACE_STEP\t%s\tNA\tNA\n' "$label"
        return 0
    fi
    read -r trace_id trace_begin trace_end <<< "$trace_line"
    trace_ms="$(awk -v begin="$trace_begin" -v end="$trace_end" \
        'BEGIN { printf "%.3f", (end - begin) * 1000 }')"
    printf 'TRACE_STEP\t%s\t%s\t%s\n' "$label" "$trace_id" "$trace_ms"
}

trace_duration_ms()
{
    local start_pattern="$1" end_pattern="$2" result
    [ -s "$TRACE_FILE" ] || return 0
    result="$(awk -v start_pattern="$start_pattern" -v end_pattern="$end_pattern" '
        $0 ~ start_pattern { start = $1 }
        $0 ~ end_pattern && start != "" { result = ($1 - start) * 1000; start = "" }
        END { if (result != "") printf "%.3f", result }
    ' "$TRACE_FILE")"
    [ -n "$result" ] && printf '%s\n' "$result"
    return 0
}

trace_sum_duration_ms()
{
    local start_pattern="$1" end_pattern="$2" boundary_start="${3:-}" boundary_end="${4:-}" result
    [ -s "$TRACE_FILE" ] || return 0
    result="$(awk -v start_pattern="$start_pattern" -v end_pattern="$end_pattern" \
        -v boundary_start="$boundary_start" -v boundary_end="$boundary_end" '
        function session_key(    i, token) {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^session=/) return $i
            }
            return ""
        }
        boundary_start != "" && $0 ~ boundary_start { window_start = $1; window_end = "" }
        boundary_end != "" && $0 ~ boundary_end && window_start != "" { window_end = $1 }
        $0 ~ start_pattern {
            key = session_key()
            if (key != "" &&
                (boundary_start == "" ||
                    ($1 >= window_start && (window_end == "" || $1 <= window_end)))) {
                start[key] = $1
            }
        }
        $0 ~ end_pattern {
            key = session_key()
            if (key != "" && key in start &&
                (boundary_start == "" ||
                    ($1 >= window_start && (window_end == "" || $1 <= window_end)))) {
                total += ($1 - start[key]) * 1000
                delete start[key]
            }
        }
        END { if (total != "") printf "%.3f", total }
    ' "$TRACE_FILE")"
    [ -n "$result" ] && printf '%s\n' "$result"
    return 0
}

emit_internal_trace_metric()
{
    local name="$1" start_pattern="$2" end_pattern="$3" value
    value="$(trace_duration_ms "$start_pattern" "$end_pattern")"
    if [ -n "$value" ]; then
        printf 'INTERNAL\t%s\t%s\tms\n' "$name" "$value"
    fi
    return 0
}

capture_reproduction_state()
{
    local pane="$1" target="$2" label="$3" output plain esc cursor
    output="$RUN_DIR/$label-ansi.txt"
    tmuxc capture-pane -e -p -t "$pane" > "$output"
    esc="$( (grep -o $'\033' "$output" 2>/dev/null || true) | wc -l | tr -d ' ')"
    plain="$RUN_DIR/$label-plain.txt"
    sed $'s/\033\[[0-9;?]*[ -\/]*[@-~]//g' "$output" > "$plain"
    cursor="$(grep -Ec "^>\\*? +$target" "$plain" || true)"
    printf 'REPRO_ESC_COUNT\t%s\t%s\n' "$label" "$esc"
    printf 'REPRO_CURSOR_TARGET\t%s\t%s\n' "$label" "$cursor"
    [ "$cursor" -eq 1 ]
}

capture_cursor_frame()
{
    local pane="$1" expected="$2" label="$3" output plain esc cursor_count target_count
    output="$RUN_DIR/$label-ansi.txt"
    if ! tmuxc capture-pane -e -p -t "$pane" > "$output" 2>/dev/null; then
        printf 'REPRO_CURSOR_FRAME\t%s\t%s\t%s\t%s\t%s\n' \
            "$label" "$expected" 0 0 0
        return 0
    fi
    esc="$( (grep -o $'\033' "$output" 2>/dev/null || true) | wc -l | tr -d ' ')"
    plain="$RUN_DIR/$label-plain.txt"
    sed $'s/\033\[[0-9;?]*[ -\/]*[@-~]//g' "$output" > "$plain"
    cursor_count="$(grep -Ec '^>\*? ' "$plain" || true)"
    target_count="$(grep -Ec "^>\\*? +$expected" "$plain" || true)"
    printf 'REPRO_CURSOR_FRAME\t%s\t%s\t%s\t%s\t%s\n' \
        "$label" "$expected" "$cursor_count" "$target_count" "$esc"
}

run_standard_reproduction()
{
    local saved_socket="$SOCKET" saved_run_dir="$RUN_DIR" saved_history_dir="$HISTORY_DIR"
    local saved_trace_file="$TRACE_FILE"
    local saved_client_tty="${client_tty:-}"
    local saved_client_pid="$CLIENT_PID" standard_socket="profile-isolated-standard-$$-${RANDOM}"
    local standard_run_dir="$MAIN_RUN_DIR/standard" standard_history_dir="$MAIN_RUN_DIR/standard-history"
    local standard_client_tty standard_sidebar standard_target_sidebar standard_start standard_switch

    SOCKET="$standard_socket"
    RUN_DIR="$standard_run_dir"
    HISTORY_DIR="$standard_history_dir"
    TRACE_FILE="$RUN_DIR/launcher-trace.log"
    CLIENT_PID=""
    mkdir -p "$RUN_DIR" "$HISTORY_DIR"

    tmuxc new-session -d -x 100 -y 30 -s repro-anchor
    tmuxc new-session -d -s repro-background
    tmuxc new-session -d -s repro-target
    tmuxc set-environment -g TMUX_SESSION_HISTORY_DIR "$HISTORY_DIR"
    tmuxc set-environment -g TMUX_SESSION_LAUNCHER_DEBUG 0
    tmuxc set-environment -g TMUX_SESSION_LAUNCHER_DEBUG "$PROFILE_DEBUG"
    tmuxc set-environment -g TMUX_SESSION_LAUNCHER_DEBUG_FILE "$RUN_DIR/launcher-debug.log"
    tmuxc set-environment -g TMUX_SESSION_LAUNCHER_TRACE "$PROFILE_TRACE"
    tmuxc set-environment -g TMUX_SESSION_LAUNCHER_TRACE_FILE "$TRACE_FILE"
    tmuxc set-environment -g TMUX_SESSION_SIDEBAR_STATE_REFRESH_SECONDS "$PROFILE_STATE_REFRESH_SECONDS"
    tmuxc set-environment -g TMUX_SESSION_SIDEBAR_SIGNAL_TIMER_ENABLED "$PROFILE_SIGNAL_TIMER_ENABLED"
    tmuxc set-environment -g TMUX_SESSION_SIDEBAR_EVENT_LOOP_ENABLED "$PROFILE_EVENT_LOOP_ENABLED"
    tmuxc set-environment -g TMUX_SESSION_SIDEBAR_ANIMATION_ENABLED "$PROFILE_ANIMATION_ENABLED"

    HOME="$PROFILE_HOME" LIBGL_ALWAYS_SOFTWARE=1 XMODIFIERS='' urxvt -pe "" -geometry 100x30 \
        -title tmux-sidebar-standard -e tmux -L "$SOCKET" attach-session -t repro-anchor &
    CLIENT_PID=$!
    wait_for_client || { echo 'ERROR: standard attached client did not start' >&2; return 1; }
    standard_client_tty="$(client_tty_for)"
    [ -n "$standard_client_tty" ] || { echo 'ERROR: standard client tty missing' >&2; return 1; }
    client_tty="$standard_client_tty"
    [ "$(tmuxc list-clients 2>/dev/null | wc -l | tr -d ' ')" = 1 ] || {
        echo 'ERROR: standard client count mismatch' >&2
        return 1
    }
    printf 'REPRO_STANDARD_CLIENT_TTY\t%s\n' "$standard_client_tty"

    tmuxc switch-client -c "$standard_client_tty" -t '=repro-background'
    wait_for_client_session repro-background || {
        echo 'ERROR: standard background client session mismatch' >&2
        return 1
    }
    standard_start="$(now_ms)"
    sleep 7
    printf 'REPRO_STANDARD_BACKGROUND_STABLE_MS\t%s\n' "$(( $(now_ms) - standard_start ))"
    standard_sidebar="$(open_sidebar_via_toggle repro-background)"
    capture_cursor_frame "$standard_sidebar" repro-target standard-before-j

    # The physical selection and Enter actions are inside the standard phase.
    tmuxc send-keys -t "$standard_sidebar" j
    wait_for_selection "$standard_sidebar" repro-target || {
        echo 'ERROR: standard j did not select repro-target' >&2
        return 1
    }
    capture_cursor_frame "$standard_sidebar" repro-target standard-after-j
    standard_switch="$(now_ms)"
    tmuxc send-keys -t "$standard_sidebar" Enter
    capture_cursor_frame "$standard_sidebar" repro-background standard-immediate-after-enter
    wait_for_client_session repro-target || {
        echo 'ERROR: standard target client session mismatch' >&2
        return 1
    }
    printf 'REPRO_STANDARD_SWITCH_MS\t%s\n' "$(( $(now_ms) - standard_switch ))"
    sleep 2
    standard_target_sidebar="$(wait_for_sidebar repro-target)"
    capture_reproduction_state "$standard_target_sidebar" repro-target standard-settled || {
        echo 'ERROR: standard target cursor alignment failed' >&2
        return 1
    }
    [ "$(client_session)" = repro-target ] || {
        echo 'ERROR: standard target client changed before capture' >&2
        return 1
    }
    printf 'REPRO_STANDARD_ALIGNMENT\t%s\tPASS\n' "$standard_target_sidebar"

    tmuxc kill-server >/dev/null 2>&1 || true
    kill "$CLIENT_PID" >/dev/null 2>&1 || true
    wait "$CLIENT_PID" 2>/dev/null || true
    CLIENT_PID=""
    [ "$PROFILE_KEEP_RUN_DIR" = true ] || rm -rf "$standard_run_dir" "$standard_history_dir"
    SOCKET="$saved_socket"
    RUN_DIR="$saved_run_dir"
    HISTORY_DIR="$saved_history_dir"
    TRACE_FILE="$saved_trace_file"
    CLIENT_PID="$saved_client_pid"
    client_tty="$saved_client_tty"
}

echo "Starting reproduction sidebar profile (socket: $SOCKET)"
run_standard_reproduction
tmuxc new-session -d -x 100 -y 30 -s baseline-1
tmuxc set-environment -g TMUX_SESSION_HISTORY_DIR "$HISTORY_DIR"
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_DEBUG 0
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_DEBUG "$PROFILE_DEBUG"
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_DEBUG_FILE "$RUN_DIR/launcher-debug.log"
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_TRACE "$PROFILE_TRACE"
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_TRACE_FILE "$TRACE_FILE"
if [ "$PROFILE_METRICS" = true ]; then
    METRICS_FILE="$RUN_DIR/launcher-metrics.log"
else
    METRICS_FILE=""
fi
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_METRICS_FILE "$METRICS_FILE"
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_METRICS_RUN_ID "$SEPARATION_RUN_ID"
tmuxc set-environment -g TMUX_SESSION_SIDEBAR_STATE_REFRESH_SECONDS "$PROFILE_STATE_REFRESH_SECONDS"
tmuxc set-environment -g TMUX_SESSION_SIDEBAR_SIGNAL_TIMER_ENABLED "$PROFILE_SIGNAL_TIMER_ENABLED"
tmuxc set-environment -g TMUX_SESSION_SIDEBAR_EVENT_LOOP_ENABLED "$PROFILE_EVENT_LOOP_ENABLED"
tmuxc set-environment -g TMUX_SESSION_SIDEBAR_ANIMATION_ENABLED "$PROFILE_ANIMATION_ENABLED"
for i in $(seq 2 8); do tmuxc new-session -d -s "baseline-$i"; done

HOME="$PROFILE_HOME" LIBGL_ALWAYS_SOFTWARE=1 XMODIFIERS='' urxvt -pe "" -geometry 100x30 \
    -title tmux-sidebar-reproduction -e tmux -L "$SOCKET" attach-session -t baseline-1 &
CLIENT_PID=$!
wait_for_client || { echo 'ERROR: attached client did not start' >&2; exit 1; }
client_tty="$(client_tty_for)"
[ -n "$client_tty" ] || { echo 'ERROR: client tty not found' >&2; exit 1; }
client_count="$(tmuxc list-clients 2>/dev/null | wc -l | tr -d ' ')"
[ "$client_count" = 1 ] || { echo "ERROR: expected one client, got $client_count" >&2; exit 1; }
printf 'REPRO_CLIENT_TTY\t%s\n' "$client_tty"
printf 'META\tseparation_run_id\t%s\nMETA\tterm\t%s\nMETA\tshell\t%s\nMETA\tlocale\t%s\nMETA\tdisplay\t%s\nMETA\ttmux_config\t%s\nMETA\ttrace\t%s\nMETA\tmetrics\t%s\nMETA\tpipe_observer\t%s\nMETA\tanimation\t%s\n' \
    "$SEPARATION_RUN_ID" "${TERM:-}" "${SHELL:-}" "${LC_ALL:-${LANG:-}}" "${DISPLAY:-}" "$TMUX_CONFIG" "$PROFILE_TRACE" "$PROFILE_METRICS" "$PROFILE_PIPE_OBSERVER" "$PROFILE_ANIMATION_ENABLED"
printf 'META\tstate_refresh_seconds\t%s\n' "$PROFILE_STATE_REFRESH_SECONDS"
printf 'META\tsignal_timer_enabled\t%s\n' "$PROFILE_SIGNAL_TIMER_ENABLED"
printf 'META\tevent_loop_enabled\t%s\n' "$PROFILE_EVENT_LOOP_ENABLED"
printf 'META\tactive_fixture\tselected-session\n'
printf 'META\tdebug\t%s\n' "$PROFILE_DEBUG"

sidebar="$(open_sidebar_via_toggle baseline-1)"
sidebar_pid="$(tmuxc display-message -p -t "$sidebar" '#{pane_pid}')"
idle="$(measure_process "$sidebar_pid" "$PROFILE_SECONDS")"
emit idle_cpu_percent "${idle%,*}" percent PASS
emit idle_peak_rss_kb "${idle#*,}" KiB PASS

# Measure active animation in the session that owns the sidebar.  The previous
# fixture ran the workload in baseline-2 while the sidebar stayed in
# baseline-1, so it did not exercise the selected-session animation path.
work_pane="$(tmuxc list-panes -t '=baseline-1:' -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 != "dotfiles-session-sidebar" { print $1; exit }')"
tmuxc send-keys -t "$work_pane" "$RUN_DIR/bin/codex -c 'while :; do printf tick; sleep 0.1; done'" Enter
sleep 6
active="$(measure_process "$sidebar_pid" "$PROFILE_SECONDS")"
emit active_cpu_percent "${active%,*}" percent PASS
emit active_peak_rss_kb "${active#*,}" KiB PASS
tmuxc send-keys -t "$work_pane" C-c
sleep 1

if [ "$PROFILE_PIPE_OBSERVER" = true ]; then
    start_pipe_observer baseline-2 "$sidebar"
fi
key_start="$(now_ms)"
tmuxc send-keys -t "$sidebar" j
if [ "$PROFILE_PIPE_OBSERVER" = true ]; then
    wait_for_blocking_pipe_marker || { tmuxc pipe-pane -t "$sidebar"; emit key_reactivity_ms 5000 ms FAIL; exit 1; }
    tmuxc pipe-pane -t "$sidebar"
else
    wait_for_selection "$sidebar" baseline-2 || { emit key_reactivity_ms 5000 ms FAIL; exit 1; }
fi
emit key_reactivity_ms "$(( $(now_ms) - key_start ))" ms PASS

# Exact reproduction.md flow: explicit client targeting, 7s stabilization,
# physical Enter, 2s target stabilization, target sidebar re-discovery.
tmuxc switch-client -c "$client_tty" -t '=baseline-2'
wait_for_client_session baseline-2 || { echo 'ERROR: background client session mismatch' >&2; exit 1; }
tmuxc switch-client -c "$client_tty" -t '=baseline-1'
stable_start="$(now_ms)"
wait_for_client_session baseline-1 || { echo 'ERROR: source client session mismatch' >&2; exit 1; }
sleep 7
source_stable_ms=$(( $(now_ms) - stable_start ))
printf 'REPRO_SOURCE_STABLE_MS\t%s\n' "$source_stable_ms"
source_sidebar="$(wait_for_sidebar baseline-1)"
printf 'REPRO_SOURCE_CLIENT_SESSION\t%s\tPASS\n' "$(client_session)"
printf 'REPRO_SOURCE_SIDEBAR_COUNT\t%s\t%s\n' "$(sidebar_count_for baseline-1)" \
    "$([ "$(sidebar_count_for baseline-1)" = 1 ] && echo PASS || echo FAIL)"
source_pane_pid="$(tmuxc display-message -p -t "$source_sidebar" '#{pane_pid}')"
printf 'REPRO_SOURCE_PANE\t%s\t%s\n' "$source_sidebar" "$source_pane_pid"
capture_cursor_frame "$source_sidebar" baseline-2 before-enter
switch_start="$(now_ms)"
tmuxc send-keys -t "$source_sidebar" Enter
capture_cursor_frame "$source_sidebar" baseline-1 immediate-after-enter
wait_for_session baseline-2 || { emit session_switch_ms 5000 ms FAIL; exit 1; }
switch_ms=$(( $(now_ms) - switch_start ))
target_stable_start="$(now_ms)"
sleep 2
target_stable_ms=$(( $(now_ms) - target_stable_start ))
target_sidebar="$(wait_for_sidebar baseline-2)"
emit session_switch_ms "$switch_ms" ms PASS
printf 'REPRO_SOURCE_SIDEBAR\t%s\nREPRO_TARGET_SIDEBAR\t%s\n' "$source_sidebar" "$target_sidebar"
printf 'REPRO_TARGET_CLIENT_SESSION\t%s\tPASS\n' "$(client_session)"
printf 'REPRO_TARGET_SIDEBAR_COUNT\t%s\t%s\n' "$(sidebar_count_for baseline-2)" \
    "$([ "$(sidebar_count_for baseline-2)" = 1 ] && echo PASS || echo FAIL)"
target_pane_pid="$(tmuxc display-message -p -t "$target_sidebar" '#{pane_pid}')"
printf 'REPRO_TARGET_PANE\t%s\t%s\n' "$target_sidebar" "$target_pane_pid"
capture_cursor_frame "$target_sidebar" baseline-2 settled-before-ansi-check
capture_reproduction_state "$target_sidebar" baseline-2 switch-target || {
    echo 'ERROR: reproduction cursor/active session invariant failed' >&2
    exit 1
}
[ "$(client_session)" = baseline-2 ] || {
    echo 'ERROR: target client session changed before capture' >&2
    exit 1
}
printf 'REPRO_CAPTURE_CLIENT_SESSION\t%s\t%s\n' "$(client_session)" \
    "$([ "$(client_session)" = baseline-2 ] && echo PASS || echo FAIL)"
printf 'REPRO_TARGET_STABLE_MS\t%s\n' "$target_stable_ms"

archive_session=baseline-archive
tmuxc new-session -d -s "$archive_session" -c "$REPO_ROOT"
tmuxc split-window -d -t "=$archive_session:" -v -c "$REPO_ROOT/tests"
expected_panes="$(tmuxc list-panes -t "=$archive_session:" | wc -l)"
expected_windows="$(tmuxc list-windows -t "=$archive_session:" | wc -l)"
archive_start="$(now_ms)"
tmuxc run-shell -b "$LAUNCHER --delete-session-after-archive $archive_session true"
archive_dispatch_ms=$(( $(now_ms) - archive_start ))
archive_file="$(wait_for_archive_file '*baseline-archive-*w.tsv' || true)"
archive_file_ready_ms=$(( $(now_ms) - archive_start ))
archive_ms=$(( $(now_ms) - archive_start ))
[ -n "$archive_file" ] && ! tmuxc has-session -t "=$archive_session" 2>/dev/null || { emit archive_ms "$archive_ms" ms FAIL; exit 1; }
printf 'PHASE\tarchive_dispatch_ms\t%s\n' "$archive_dispatch_ms"
printf 'PHASE\tarchive_file_ready_ms\t%s\n' "$archive_file_ready_ms"
printf 'PHASE\tarchive_observer_wait_ms\t%s\n' "$((archive_file_ready_ms - archive_dispatch_ms))"
emit archive_ms "$archive_ms" ms PASS
emit archive_bytes "$(wc -c < "$archive_file")" bytes PASS
emit_internal_trace_metric archive_launcher_ms 'archive.delete-wrapper.begin' 'archive.delete-wrapper.end'

PROFILE_PHASE="restore-sidebar-discovery"
if ! sidebar="$(wait_for_sidebar baseline-2)"; then
    dump_profile_state "$PROFILE_PHASE"
    echo 'ERROR: restore source sidebar was not available' >&2
    exit 1
fi
restore_start="$(now_ms)"
PROFILE_PHASE="restore-history"
tmuxc send-keys -t "$sidebar" o
wait_for_text "$sidebar" '^open:' || { echo 'ERROR: restore history view did not open' >&2; emit restore_ms 5000 ms FAIL; exit 1; }
restore_history_ms=$(( $(now_ms) - restore_start ))
tmuxc send-keys -t "$sidebar" Space
wait_for_text "$sidebar" '^>x ' || { echo 'ERROR: restore archive selection did not appear' >&2; emit restore_ms 5000 ms FAIL; exit 1; }
tmuxc send-keys -t "$sidebar" Enter
PROFILE_PHASE="restore-session-settlement"
restore_dispatch_ms=$(( $(now_ms) - restore_start ))
if ! wait_for_session baseline-archive; then
    dump_profile_state "$PROFILE_PHASE"
    echo 'ERROR: restore target session did not appear' >&2
    emit restore_ms 5000 ms FAIL
    exit 1
fi
restore_session_ms=$(( $(now_ms) - restore_start ))
actual_panes="$(tmuxc list-panes -t '=baseline-archive:' -F '#{pane_title}' | awk '$0 != "dotfiles-session-sidebar" { count++ } END { print count+0 }')"
actual_windows="$(tmuxc list-windows -t '=baseline-archive:' | wc -l)"
[ "$actual_panes" = "$expected_panes" ] && [ "$actual_windows" = "$expected_windows" ] || { emit restore_ms 5000 ms FAIL; exit 1; }
restore_target_work_pane="$(tmuxc list-panes -t '=baseline-archive:' -F '#{pane_id}|#{pane_title}' |
    awk -F '|' '$2 != "dotfiles-session-sidebar" { print $1; exit }')"
restore_complete_ms=$(( $(now_ms) - restore_start ))
restore_sidebar_ready_start="$(now_ms)"
PROFILE_PHASE="restore-sidebar-readiness"
if ! restore_sidebar="$(wait_for_sidebar baseline-archive)"; then
    dump_profile_state "$PROFILE_PHASE"
    echo 'ERROR: restored sidebar did not become ready' >&2
    emit restore_sidebar_ready_ms 30000 ms FAIL
    exit 1
fi
restore_sidebar_ready_ms=$(( $(now_ms) - restore_sidebar_ready_start ))
printf 'PHASE\trestore_sidebar_ready_ms\t%s\n' "$restore_sidebar_ready_ms"
printf 'PHASE\trestore_sidebar_pane\t%s\n' "$restore_sidebar"
printf 'PHASE\trestore_history_ms\t%s\n' "$restore_history_ms"
printf 'PHASE\trestore_dispatch_ms\t%s\n' "$restore_dispatch_ms"
printf 'PHASE\trestore_session_ms\t%s\n' "$restore_session_ms"
printf 'PHASE\trestore_client_settlement_ms\t%s\n' "$((restore_session_ms - restore_dispatch_ms))"
emit restore_ms "$restore_complete_ms" ms PASS
emit restore_integrity 100 percent PASS
emit_internal_trace_metric restore_launcher_ms 'restore.history.begin' 'restore.sidebar.dispatch|restore.sidebar.ensure.end'
emit_internal_trace_metric restore_dispatch_to_sidebar_create_ms \
    "restore.sidebar.dispatch.*pane=$restore_target_work_pane" \
    "sidebar.open.end.*pane=$restore_sidebar"
emit_internal_trace_metric restore_dispatch_to_process_start_ms \
    "restore.sidebar.dispatch.*pane=$restore_target_work_pane" \
    "sidebar.process.begin.*pane=$restore_sidebar"

layout_session=baseline-lifecycle
tmuxc new-session -d -s "$layout_session" -c "$REPO_ROOT"
tmuxc split-window -d -t "=$layout_session:" -v -c "$REPO_ROOT/tests"
layout_window="$(tmuxc display-message -p -t "=$layout_session:" '#{window_id}')"
layout_before="$(tmuxc display-message -p -t "$layout_window" '#{window_layout}')"
tmuxc set-option -wq -t "$layout_window" @dotfiles-session-work-layout "$layout_before"
for ignored in 1 2 3; do
    work="$(tmuxc list-panes -t "=$layout_session:" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 != "dotfiles-session-sidebar" { print $1; exit }')"
    pane="$(tmuxc split-window -d -P -F '#{pane_id}' -t "$work" -h -b -l 35 'sleep 30')"
    tmuxc select-pane -t "$pane" -T dotfiles-session-sidebar
    tmuxc kill-pane -t "$pane"
done
layout_after="$(tmuxc display-message -p -t "$layout_window" '#{window_layout}')"
[ "$layout_before" = "$layout_after" ] || { emit layout_preserved 0 percent FAIL; exit 1; }
emit layout_preserved 100 percent PASS

auto_status=PASS
for auto_index in $(seq 1 10); do
    auto_name="$(printf 'nav-%02d' "$auto_index")"
    tmuxc new-session -d -s "$auto_name" -c "$REPO_ROOT" 'sleep 90'
done
tmuxc switch-client -c "$client_tty" -t '=nav-01'
wait_for_client_session nav-01 || { echo 'ERROR: navigation client session mismatch' >&2; auto_status=FAIL; }
sleep 7
auto_sidebar="$(open_sidebar_via_toggle nav-01)"
auto_start="$(now_ms)"
wait_for_selection "$auto_sidebar" nav-01 || auto_status=FAIL

nav_move()
{
    local direction="$1" target="$2" label="$3" start observed send_start send_end
    if [ "$PROFILE_PIPE_OBSERVER" = true ]; then
        start_pipe_observer "$target" "$auto_sidebar"
    fi
    start="$(now_ms)"
    send_start="$start"
    tmuxc send-keys -t "$auto_sidebar" "$direction"
    send_end="$(now_ms)"
    printf 'SEND_STEP\t%s\t%s\n' "$label" "$((send_end - send_start))"
    if [ "$PROFILE_PIPE_OBSERVER" = true ]; then
        wait_for_blocking_pipe_marker || auto_status=FAIL
        tmuxc pipe-pane -t "$auto_sidebar"
    else
        wait_for_selection "$auto_sidebar" "$target" || auto_status=FAIL
    fi
    observed="$(now_ms)"
    printf 'AUTO_STEP\t%s\t%s\t%s\t%s\n' "$label" "$target" "$((observed - start))" "$((observed - auto_start))"
    trace_selection_step "$label"
    if [ "$PROFILE_PIPE_OBSERVER" = true ] && [ -n "${key_observed_ms:-}" ]; then
        printf 'PIPE_STEP\t%s\t%s\n' "$label" "$((key_observed_ms - start))"
    fi
}

for auto_index in $(seq 2 10); do nav_move j "nav-$(printf '%02d' "$auto_index")" down; done
for auto_index in $(seq 9 -1 1); do nav_move k "nav-$(printf '%02d' "$auto_index")" up; done

burst_start="$(now_ms)"
for ignored in 1 2 3 4 5; do tmuxc send-keys -t "$auto_sidebar" j; done
wait_for_selection "$auto_sidebar" nav-06 || auto_status=FAIL
printf 'AUTO_SCENARIO\tfast_burst_j_5\tnav-06\t%s\n' "$(( $(now_ms) - burst_start ))"

sleep "$PROFILE_PERIODIC_REFRESH_DELAY"
nav_move j nav-07 periodic_refresh_collision

final_capture="$RUN_DIR/navigation-final-ansi.txt"
final_plain="$RUN_DIR/navigation-final-plain.txt"
captured=false
for ignored in $(seq 1 30); do
    candidate="$(sidebar_for nav-01 || true)"
    if [ -n "$candidate" ] &&
        tmuxc capture-pane -e -p -t "$candidate" > "$final_capture" 2>/dev/null; then
        sed $'s/\033\[[0-9;?]*[ -\/]*[@-~]//g' "$final_capture" > "$final_plain"
        final_cursor_count="$(grep -Ec '^>\*? ' "$final_plain" || true)"
        if [ "$final_cursor_count" -eq 1 ]; then
            auto_sidebar="$candidate"
            captured=true
            break
        fi
    fi
    sleep 0.1
done
if [ "$captured" = true ]; then
    final_esc_count="$( (grep -o $'\033' "$final_capture" 2>/dev/null || true) |
        wc -l | tr -d ' ' )"
    printf 'REPRO_ESC_COUNT\tnavigation-final\t%s\n' "$final_esc_count"
    final_target="$(awk '/^>\\*? / { print $2; exit }' "$final_plain")"
    printf 'REPRO_CURSOR_TARGET\tnavigation-final\t%s\n' \
        "$([ -n "$final_target" ] && echo 1 || echo 0)"
    [ -n "$final_target" ] || auto_status=FAIL
else
    echo 'ERROR: navigation cursor did not stabilize' >&2
    final_cursor_count=0
    auto_status=FAIL
fi

observer_status=PASS
for reset_target in nav-06 nav-05 nav-04 nav-03 nav-02 nav-01; do
    tmuxc send-keys -t "$auto_sidebar" k
    wait_for_selection "$auto_sidebar" "$reset_target" || observer_status=FAIL
done
observer_capture_start="$(now_ms)"
tmuxc send-keys -t "$auto_sidebar" j
wait_for_selection "$auto_sidebar" nav-02 || observer_status=FAIL
observer_capture_end="$(now_ms)"
tmuxc send-keys -t "$auto_sidebar" k
wait_for_selection "$auto_sidebar" nav-01 || observer_status=FAIL

start_pipe_observer nav-02 "$auto_sidebar"
observer_pipe_start="$(now_ms)"
tmuxc send-keys -t "$auto_sidebar" j
if ! wait_for_blocking_pipe_marker; then
    observer_status=FAIL
    observer_pipe_end="$(now_ms)"
else
    observer_pipe_end="$(now_ms)"
fi
tmuxc pipe-pane -t "$auto_sidebar"
tmuxc send-keys -t "$auto_sidebar" k
wait_for_selection "$auto_sidebar" nav-01 || observer_status=FAIL
printf 'PHASE\tobserver_capture_same_lifecycle_ms\t%s\n' \
    "$((observer_capture_end - observer_capture_start))"
printf 'PHASE\tobserver_pipe_same_lifecycle_ms\t%s\n' \
    "$((observer_pipe_end - observer_pipe_start))"
printf 'PHASE\tobserver_same_lifecycle_status\t%s\n' "$observer_status"
[ "$observer_status" = PASS ] || auto_status=FAIL
emit_internal_trace_metric restore_title_to_first_render_ms \
    "sidebar.pane-title.end.*pane=$restore_sidebar" \
    "sidebar.first-render.end.*pane=$restore_sidebar"
emit_internal_trace_metric restore_process_to_title_ms \
    "sidebar.process.begin.*pane=$restore_sidebar" \
    "sidebar.pane-title.end.*pane=$restore_sidebar"
emit_internal_trace_metric restore_title_to_collect_end_ms \
    "sidebar.pane-title.end.*pane=$restore_sidebar" \
    "sidebar.collect.end.*pane=$restore_sidebar"
emit_internal_trace_metric restore_collect_to_first_render_ms \
    "sidebar.collect.end.*pane=$restore_sidebar" \
    "sidebar.first-render.end.*pane=$restore_sidebar"
emit_internal_trace_metric restore_collect_sessions_setup_ms \
    "pane=$restore_sidebar collect.sessions.begin" \
    "pane=$restore_sidebar collect.list-sessions.end"
emit_internal_trace_metric restore_collect_list_panes_ms \
    "pane=$restore_sidebar collect.list-sessions.end" \
    "pane=$restore_sidebar collect.list-panes.end"
emit_internal_trace_metric restore_collect_parse_panes_ms \
    "pane=$restore_sidebar collect.list-panes.end" \
    "pane=$restore_sidebar collect.parse-panes.end"
emit_internal_trace_metric restore_collect_parse_sessions_ms \
    "pane=$restore_sidebar collect.parse-sessions.begin" \
    "pane=$restore_sidebar collect.parse-sessions.end"
emit_internal_trace_metric restore_last_session_status_ms \
    "pane=$restore_sidebar collect.session.status.begin" \
    "pane=$restore_sidebar collect.session.status.end"
emit_internal_trace_metric restore_last_animation_seed_ms \
    "pane=$restore_sidebar collect.session.animation-seed.begin" \
    "pane=$restore_sidebar collect.session.animation-seed.end"
restore_session_status_total_ms="$(trace_sum_duration_ms \
    "pane=$restore_sidebar collect.session.status.begin" \
    "pane=$restore_sidebar collect.session.status.end" \
    "pane=$restore_sidebar collect.parse-sessions.begin" \
    "pane=$restore_sidebar collect.parse-sessions.end")"
if [ -n "$restore_session_status_total_ms" ]; then
    printf 'INTERNAL\trestore_session_status_total_ms\t%s\tms\n' \
        "$restore_session_status_total_ms"
fi
restore_animation_seed_total_ms="$(trace_sum_duration_ms \
    "pane=$restore_sidebar collect.session.animation-seed.begin" \
    "pane=$restore_sidebar collect.session.animation-seed.end" \
    "pane=$restore_sidebar collect.parse-sessions.begin" \
    "pane=$restore_sidebar collect.parse-sessions.end")"
if [ -n "$restore_animation_seed_total_ms" ]; then
    printf 'INTERNAL\trestore_animation_seed_total_ms\t%s\tms\n' \
        "$restore_animation_seed_total_ms"
fi
emit_internal_trace_metric restore_ai_state_total_ms \
    "pane=$restore_sidebar ai.state.begin" \
    "pane=$restore_sidebar ai.state.end"
emit_internal_trace_metric restore_ai_fingerprint_ms \
    "pane=$restore_sidebar ai.fingerprint.begin" \
    "pane=$restore_sidebar ai.fingerprint.end"
emit_internal_trace_metric restore_ai_state_to_collect_end_ms \
    "pane=$restore_sidebar ai.state.end" \
    "pane=$restore_sidebar collect.parse-sessions.end"

resize_session=repro-resize
tmuxc new-session -d -s "$resize_session" -c "$REPO_ROOT" 'sleep 90'
resize_sidebar="$(open_sidebar_direct "$resize_session")" || auto_status=FAIL
tmuxc resize-pane -t "$resize_sidebar" -x 20 || auto_status=FAIL
sleep 0.2
tmuxc resize-pane -t "$resize_sidebar" -x 35 || auto_status=FAIL
resize_width="$(tmuxc display-message -p -t "$resize_sidebar" '#{pane_width}' 2>/dev/null || printf '0')"
[ "$resize_width" = 35 ] || auto_status=FAIL
resize_capture="$RUN_DIR/resize-sidebar.txt"
resize_cursor_count=0
for ignored in $(seq 1 30); do
    if tmuxc capture-pane -p -J -t "$resize_sidebar" > "$resize_capture" 2>/dev/null; then
        resize_cursor_count="$(grep -Ec '^>\*? ' "$resize_capture" || true)"
        [ "$resize_cursor_count" -eq 1 ] && break
    fi
    sleep 0.1
done
resize_max_width="$(awk '{ if (length > max) max=length } END { print max+0 }' "$resize_capture")"
resize_grid_status=PASS
[ "$resize_max_width" -le "$resize_width" ] || resize_grid_status=FAIL
[ "$resize_cursor_count" -eq 1 ] || resize_grid_status=FAIL
[ "$resize_grid_status" = PASS ] || auto_status=FAIL
if [ "$resize_grid_status" != PASS ]; then
    echo 'ERROR: resize grid invariant failed' >&2
    tmuxc capture-pane -p -J -t "$resize_sidebar" >&2 || true
fi
emit grid_max_columns "$resize_max_width" columns "$resize_grid_status"
emit grid_pane_columns "$resize_width" columns "$resize_grid_status"
emit cursor_count "$resize_cursor_count" count "$resize_grid_status"
printf 'AUTO_SCENARIO\tresize_20_to_35\t%s\t%s\n' "$resize_session" "$auto_status"
printf 'AUTO_SUMMARY\tcursor_count\t%s\n' "$final_cursor_count"
printf 'AUTO_SUMMARY\tstatus\t%s\n' "$auto_status"

if [ "$PROFILE_METRICS" = true ] && [ -s "$METRICS_FILE" ]; then
    while IFS= read -r metrics_line; do
        printf 'LOG\t%s\n' "$metrics_line"
    done < "$METRICS_FILE"
fi

commit="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
dirty=false
[ -n "$(git -C "$REPO_ROOT" status --short)" ] && dirty=true
printf 'META\tcommit\t%s\nMETA\tdirty\t%s\nMETA\ttmux\t%s\nMETA\tgeometry\t100x30\n' \
    "$commit" "$dirty" "$(tmux -V)"
[ -z "$RAW_FILE" ] || printf 'META\traw_file\t%s\n' "$RAW_FILE"
[ "$PROFILE_KEEP_RUN_DIR" = true ] && printf 'META\trun_dir\t%s\n' "$RUN_DIR"

[ "$auto_status" = PASS ]
