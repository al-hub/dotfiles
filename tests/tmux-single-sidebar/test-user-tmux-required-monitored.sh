#!/usr/bin/env bash
set -euo pipefail

# Runs the core live suite in a temporary visible window of the user's tmux.
# Prefix keys are intentionally covered by the attached-PTY suite separately.
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd -P)"
if [ -f "$REPO_ROOT/scripts/tmux-session-launcher" ]; then
    mkdir -p "$HOME/.local/bin"
    cp "$REPO_ROOT/scripts/tmux-session-launcher" "$HOME/.local/bin/tmux-session-launcher" 2>/dev/null || true
    chmod +x "$HOME/.local/bin/tmux-session-launcher" 2>/dev/null || true
fi
LAUNCHER="${TMUX_USER_LIVE_LAUNCHER:-$HOME/.local/bin/tmux-session-launcher}"
if ! tmux -L default list-clients >/dev/null 2>&1 || [ -z "$(tmux -L default list-clients -F '#{client_tty}' 2>/dev/null)" ]; then
    tmux -L default kill-server >/dev/null 2>&1 || true
    sleep 0.5
    tmux -L default new-session -d -s main -n window0 >/dev/null 2>&1 || true
    setsid script -qefc "TERM=xterm tmux -L default attach-session -t main; sleep infinity" /tmp/auto-user-client-pty.log >/dev/null 2>&1 &
    sleep 3
fi
tmuxc() { tmux -L default "$@"; }
CLIENT_TTY=""
for _ in $(seq 1 50); do
    CLIENT_TTY="${TMUX_USER_LIVE_CLIENT:-$(tmuxc list-clients -F '#{client_control_mode}|#{client_tty}' 2>/dev/null | awk -F '|' '$1 != 1 {print $2; exit}')}"
    [ -n "$CLIENT_TTY" ] && break
    sleep 0.1
done
RUN_ID="${TMUX_USER_LIVE_RUN_ID:-user-live-$(date +%s)-$$}"
RUN_DIR="${TMUX_USER_LIVE_RUN_DIR:-${TMPDIR:-/tmp}/dotfiles-user-live-$RUN_ID}"
EVENT_LOG="$RUN_DIR/events.log"; RESULT_LOG="$RUN_DIR/results.tsv"; MANIFEST_LOG="$RUN_DIR/session-switch-manifest.tsv"; SAMPLE_LOG="$RUN_DIR/transition-samples.tsv"; HISTORY_DIR="$RUN_DIR/history"
ORIGINAL_SESSION=""; ORIGINAL_WINDOW=""; TEST_WINDOW_ID=""; SIDEBAR_PANE=""; TEST_SESSIONS=(); EVENT_SEQUENCE=0; INPUT_SEQUENCE=0; FAILURES=0; INCONCLUSIVE_COUNT=0; INITIAL_PANES=""; ORIGINAL_SIDEBAR_ENABLED=""; ORIGINAL_SIDEBAR_MANAGED=""; ORIGINAL_TRACE_ENV=""; ORIGINAL_TRACE_FILE_ENV=""; ORIGINAL_DEBUG_ENV=""; ORIGINAL_DEBUG_FILE_ENV=""; CLIENT_CAPTURE_PID=""; CLIENT_STREAM_OFFSET=0; CAPTURE_CLIENT="${TMUX_USER_LIVE_CAPTURE_CLIENT:-true}"
ERROR_PATTERN='ensure-sidebar-window.*returned 1|--ensure-sidebar-window.*returned 1|session[[:space:]]+switch.*failed|longjmp[[:space:]]+causes[[:space:]]+uninitialized[[:space:]]+stack[[:space:]]+frame'
mkdir -p "$HISTORY_DIR"; : > "$EVENT_LOG"; : > "$RESULT_LOG"; : > "$MANIFEST_LOG"; : > "$SAMPLE_LOG"
printf '%b\n' 'iteration\telapsed_ms\toperation_id\tphase\tclient_session\tsidebar_pane\tsidebar_pid\tsidebar_geometry\tbefore_sidebar\tsample_interval_ms\tfull_render_count\thook_event_count\tfailure_class' > "$SAMPLE_LOG"
tmuxc() { tmux -L default "$@"; }
now_ms() { local stamp="${EPOCHREALTIME//./}"; printf '%s.%s\n' "${stamp:0:13}" "${stamp:13:3}"; }
log() { EVENT_SEQUENCE=$((EVENT_SEQUENCE + 1)); printf 'ts_wall=%s ts_mono_ms=%s run_id=%s event_seq=%s input_seq=%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%S%z')" "$(now_ms)" "$RUN_ID" "$EVENT_SEQUENCE" "$INPUT_SEQUENCE" "$*" >> "$EVENT_LOG"; }
user_client_state() {
    tmuxc display-message -p -t "$CLIENT_TTY" \
        'CLIENT|#{client_session}|#{window_id}|#{pane_id}' 2>/dev/null || true
}
user_window_panes() {
    tmuxc list-panes -t "$1" \
        -F 'PANE|#{pane_id}|#{pane_title}|#{session_name}|#{window_id}|#{pane_pid}|#{pane_left},#{pane_top},#{pane_width},#{pane_height}' 2>/dev/null || true
}
user_batched_state() {
    tmuxc list-clients -F 'CLIENT|#{client_tty}|#{session_name}|#{window_id}|#{pane_id}' \; \
        list-panes -a -F 'PANE|#{pane_id}|#{pane_title}|#{session_name}|#{window_id}|#{pane_pid}|#{pane_left},#{pane_top},#{pane_width},#{pane_height}' 2>/dev/null || true
}
trace_switch_duration_ms() {
    local trace_before="$1"
    sed -n "$((trace_before + 1)),\$p" "$RUN_DIR/trace.log" 2>/dev/null |
        awk '/switch\.begin mode=window-local/ { begin=$1 }
             /switch\.end mode=window-local/ && begin != "" {
                 printf "%.3f\n", ($1 - begin) * 1000
                 begin=""
             }' | tail -n 1
}
trace_transition_full_render_counts() {
    local trace_before="$1" pane="$2"
    sed -n "$((trace_before + 1)),\$p" "$RUN_DIR/trace.log" 2>/dev/null |
        awk -v pane="$pane" '
            /switch\.begin mode=window-local/ { active=1 }
            active && index($2, "pane=" pane) == 1 && /render\.full\.begin/ {
                if ($0 ~ /reason=geometry-invalidated/) geometry++
                else non_geometry++
            }
            active && /switch\.end mode=window-local/ { active=0 }
            END { printf "%d|%d\n", non_geometry+0, geometry+0 }
        '
}
client_field() { tmuxc list-clients -F "#{client_tty}|#{${1}}" 2>/dev/null | awk -F '|' -v tty="$CLIENT_TTY" '$1 == tty {print $2; exit}'; }
refresh_sidebar() { SIDEBAR_PANE="$(tmuxc list-panes -t "$(client_field window_id)" -F '#{pane_id}|#{pane_title}' 2>/dev/null | awk -F '|' '$2 == "dotfiles-session-sidebar" {print $1; exit}')"; [ -n "$SIDEBAR_PANE" ]; }
session_sidebar_pane() { tmuxc list-panes -t "=$1:" -F '#{pane_id}|#{pane_title}' 2>/dev/null | awk -F '|' '$2 == "dotfiles-session-sidebar" {print $1; exit}'; }
session_sidebar_count() { tmuxc list-panes -t "=$1:" -F '#{pane_title}' 2>/dev/null | awk '$1 == "dotfiles-session-sidebar" {n++} END {print n+0}'; }
snapshot() { local n="$EVENT_SEQUENCE"; log "event=snapshot session=$(client_field session_name || true) window=$(client_field window_id || true) pane=$(client_field pane_id || true) owner=$(tmuxc show-options -gqv @dotfiles_sidebar_owner_client 2>/dev/null || true)"; tmuxc list-clients -F 'control=#{client_control_mode}|tty=#{client_tty}|session=#{session_name}|window=#{window_id}|pane=#{pane_id}|prefix=#{client_prefix}' > "$RUN_DIR/clients-$n.tsv" 2>/dev/null || true; tmuxc list-panes -a -F 'session=#{session_name}|window=#{window_id}|pane=#{pane_id}|title=#{pane_title}|pid=#{pane_pid}|active=#{pane_active}|geometry=#{pane_left},#{pane_top},#{pane_width},#{pane_height}' > "$RUN_DIR/panes-$n.tsv" 2>/dev/null || true; }
capture() { local label="$1"; refresh_sidebar || return 0; tmuxc capture-pane -e -p -J -t "$SIDEBAR_PANE" > "$RUN_DIR/capture-$label.log" 2>/dev/null || true; tmuxc list-panes -t "$(client_field window_id)" -F '#{pane_id}|#{pane_title}|#{pane_left},#{pane_top},#{pane_width},#{pane_height}|#{pane_pid}|#{pane_active}' > "$RUN_DIR/layout-$label.tsv" 2>/dev/null || true; log "event=observation label=$label sidebar=$SIDEBAR_PANE"; }
scan_live_panes() {
    local label="$1" pane title session window current scroll normalized matches found=0
    while IFS='|' read -r pane title session window; do
        [ -n "$pane" ] || continue
        [ "$title" = dotfiles-session-sidebar ] && continue
        current="$RUN_DIR/pane-$pane-$label-current.log"
        scroll="$RUN_DIR/pane-$pane-$label-scrollback.log"
        normalized="$RUN_DIR/pane-$pane-$label-normalized.log"
        tmuxc capture-pane -p -J -t "$pane" > "$current" 2>/dev/null || true
        tmuxc capture-pane -p -J -S -1000 -t "$pane" > "$scroll" 2>/dev/null || true
        {
            cat "$current" 2>/dev/null || true
            cat "$scroll" 2>/dev/null || true
        } | perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\e\][^\a]*\a//g; s/\r//g' > "$normalized"
        if grep -Ein -- "$ERROR_PATTERN" "$normalized" > "$RUN_DIR/pane-$pane-$label-matches.log" 2>/dev/null; then
            found=1
            {
                printf 'ts_wall=%s ts_mono_ms=%s pane=%s title=%s session=%s window=%s label=%s\n' \
                    "$(date -u '+%Y-%m-%dT%H:%M:%S%z')" "$(now_ms)" "$pane" "$title" "$session" "$window" "$label"
                cat "$RUN_DIR/pane-$pane-$label-matches.log"
            } >> "$RUN_DIR/error-matches.log"
            log "event=error-observed source=pane pane=$pane session=$session window=$window label=$label"
        fi
    done < <(tmuxc list-panes -a -F '#{pane_id}|#{pane_title}|#{session_name}|#{window_id}' 2>/dev/null)
    return "$found"
}
scan_client_stream() {
    local label="$1" normalized raw size bytes
    normalized="$RUN_DIR/client-$label-normalized.log"
    [ -s "$RUN_DIR/client.log" ] || return 1
    size="$(wc -c < "$RUN_DIR/client.log" 2>/dev/null || printf 0)"
    bytes=$((size - CLIENT_STREAM_OFFSET))
    [ "$bytes" -gt 0 ] || return 1
    raw="$RUN_DIR/client-$label-delta.raw"
    dd if="$RUN_DIR/client.log" of="$raw" iflag=skip_bytes,count_bytes \
        skip="$CLIENT_STREAM_OFFSET" count="$bytes" status=none 2>/dev/null || return 1
    perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\e\][^\a]*\a//g; s/\r//g' \
        "$raw" > "$normalized"
    CLIENT_STREAM_OFFSET="$size"
    if grep -Ein -- "$ERROR_PATTERN" "$normalized" > "$RUN_DIR/client-$label-matches.log" 2>/dev/null; then
        {
            printf 'ts_wall=%s ts_mono_ms=%s source=client label=%s\n' \
                "$(date -u '+%Y-%m-%dT%H:%M:%S%z')" "$(now_ms)" "$label"
            cat "$RUN_DIR/client-$label-matches.log"
        } >> "$RUN_DIR/error-matches.log"
        log "event=error-observed source=client-stream label=$label"
        return 0
    fi
    return 1
}
event_field() {
    local key="$1" line="$2"
    awk -v key="$key" '{ for (i = 1; i <= NF; i++) if (index($i, key) == 1) { sub("^[^=]*=", "", $i); print $i; exit } }' <<< "$line"
}
build_user_switch_manifest() {
    local index=0 line target actual result duration before_sidebar after_sidebar operation_id phases begin_line first_target max_interval full_count hook_count failure_class
    local -a switch_events transition_begins
    mapfile -t switch_events < <(grep 'event=session.switch iteration=' "$EVENT_LOG" 2>/dev/null || true)
    mapfile -t transition_begins < <(grep 'transition.begin operation_id=' "$RUN_DIR/trace.log" 2>/dev/null || true)
printf '%s\n' 'iteration	target	actual	operation_id	input_seq	duration_ms	phases	first_target_ms	max_sample_interval_ms	full_render_count	hook_event_count	sidebar_before	sidebar_after	failure_class	result' > "$MANIFEST_LOG"
    for line in "${switch_events[@]}"; do
        target="$(event_field target= "$line")"
        actual="$(event_field to= "$line")"
        duration="$(event_field duration_ms= "$line")"
        before_sidebar="$(event_field sidebar_before= "$line")"
        after_sidebar="$(event_field sidebar_after= "$line")"
        result="$(event_field result= "$line")"
        begin_line="${transition_begins[$index]:-}"
        operation_id="$(sed -n 's/.*transition\.begin operation_id=\([^ ]*\).*/\1/p' <<< "$begin_line")"
        phases=""
        if [ -n "$operation_id" ]; then
            phases="$(grep -F "transition.phase operation_id=$operation_id " "$RUN_DIR/trace.log" 2>/dev/null |
                sed -n 's/.*phase=\([^ ]*\).*/\1/p' | paste -sd, -)"
        fi
        IFS='|' read -r first_target max_interval full_count hook_count failure_class < <(
            awk -F '\t' -v iter="$((index + 1))" -v target="$target" '
                $1 == iter { if ($5 == target && first == "") first=$2; if ($10 > max) max=$10; if ($11 > full) full=$11; if ($12 > hook) hook=$12; last=$13 }
                END { printf "%s|%s|%s|%s|%s\n", first, max+0, full+0, hook+0, last }
            ' "$SAMPLE_LOG"
        )
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$((index + 1))" "$target" "$actual" "$operation_id" \
            "$(event_field input_seq= "$line")" "$duration" "$phases" "$first_target" "$max_interval" "$full_count" "$hook_count" \
            "$before_sidebar" "$after_sidebar" "$failure_class" "$result" >> "$MANIFEST_LOG"
        index=$((index + 1))
    done
    log "event=correlation.manifest path=$MANIFEST_LOG switches=$index"
}
sample_user_transition() {
    local iteration="$1" target="$2" start="$3" before_sidebar="$4" trace_before="$5" current elapsed now previous_sample_ms sample_interval pane pid geometry operation_id phase stable=0 first_target="" failure=PASS max_sample_interval=0 full_render_count=0 hook_event_count=0 recent_trace sidebar_gap_seen=0 client_line client_window pane_line state_line kind pane_id pane_title pane_session pane_window pane_geometry sample_number=0 metric_line
    for _ in $(seq 1 120); do
        sample_number=$((sample_number + 1))
        now="$(now_ms)"
        metric_line="$(awk -v s="$start" -v n="$now" -v p="${previous_sample_ms:-}" -v m="$max_sample_interval" 'BEGIN { elapsed=n-s; interval=(p==""?"":n-p); max=(interval!=""&&interval>m?interval:m); printf "%.3f|%.3f|%.3f\n", elapsed, interval, max }')"
        IFS='|' read -r elapsed sample_interval max_sample_interval <<< "$metric_line"
        if awk -v e="$elapsed" 'BEGIN { exit !(e >= 15000) }'; then
            break
        fi
        previous_sample_ms="$now"
        state_line="$(user_batched_state)"
        client_line="$(printf '%s\n' "$state_line" | awk -F '|' -v tty="$CLIENT_TTY" '$1 == "CLIENT" && $2 == tty {print; exit}')"
        IFS='|' read -r _ _ current client_window _ <<< "$client_line"
        pane_line=""
        while IFS='|' read -r kind pane_id pane_title pane_session pane_window pid pane_geometry; do
            [ "$kind" = PANE ] && [ "$pane_title" = dotfiles-session-sidebar ] && [ "$pane_window" = "$client_window" ] && {
                pane_line="$kind|$pane_id|$pane_title|$pane_session|$pane_window|$pid|$pane_geometry"
                break
            }
        done <<< "$state_line"
        IFS='|' read -r _ pane _ _ _ pid geometry <<< "$pane_line"
        if [ $((sample_number % 8)) -eq 1 ] || [ -z "${operation_id:-}" ]; then
            recent_trace="$(sed -n "$((trace_before + 1)),\$p" "$RUN_DIR/trace.log" 2>/dev/null || true)"
            operation_id="$(printf '%s\n' "$recent_trace" | sed -n 's/.*transition\.begin operation_id=\([^ ]*\).*/\1/p' | tail -n 1)"
            phase="$(printf '%s\n' "$recent_trace" | sed -n "s/.*transition\.phase operation_id=$operation_id .*phase=\([^ ]*\).*/\1/p" | tail -n 1)"
            full_render_count="$(printf '%s\n' "$recent_trace" | grep -Ec 'render\.full\.begin.*reason=enter-session-switch' || true)"
            hook_event_count="$(printf '%s\n' "$recent_trace" | grep -Ec 'transition\.hook|sidebar\.hook' || true)"
        fi
        sample_class="$failure"
        [ -z "$pane" ] && sample_class=SIDEBAR_GAP
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$iteration" "$elapsed" "$operation_id" "$phase" "$current" "$pane" "$pid" "$geometry" "$before_sidebar" "$sample_interval" "$full_render_count" "$hook_event_count" "$sample_class" >> "$SAMPLE_LOG"
        if [ -z "$first_target" ] && [ "$current" = "$target" ]; then
            first_target="$elapsed"
        elif [ -n "$first_target" ] && [ "$current" != "$target" ]; then
            failure=CLIENT_REVERTED
            break
        fi
        [ -z "$pane" ] && sidebar_gap_seen=1
        if [ -n "$first_target" ] && [ "$pane" = "$before_sidebar" ]; then
            stable=$((stable + 1))
        else
            stable=0
        fi
        if [ "$stable" -ge 10 ]; then
            failure=PASS
            break
        fi
        sleep 0.025
    done
    if [ "$sidebar_gap_seen" -eq 1 ]; then
        failure=SIDEBAR_DISAPPEARED
    elif [ -z "$first_target" ]; then
        failure=TARGET_NOT_REACHED
    fi
    [ "$failure" = PASS ] && awk -v m="$max_sample_interval" 'BEGIN { exit !(m > 500) }' && failure=OBSERVER_TOO_SLOW
    SAMPLE_FAILURE="$failure"
    SAMPLE_ACTUAL="$current"
    SAMPLE_FIRST_TARGET="$first_target"
    SAMPLE_AFTER_SIDEBAR="$pane"
    SAMPLE_DURATION="$elapsed"
    SAMPLE_MAX_INTERVAL="$max_sample_interval"
    SAMPLE_FULL_RENDER_COUNT="$full_render_count"
    SAMPLE_HOOK_EVENT_COUNT="$hook_event_count"
    [ "$failure" = PASS ]
}
fail() { FAILURES=$((FAILURES + 1)); log "event=assertion result=FAIL reason=$*"; snapshot; capture "failure-$FAILURES"; }
initial_pane() { case " $INITIAL_PANES " in *" $1 "*) return 0;; esac; return 1; }
remove_test_sidebars() { local pane found; for _ in $(seq 1 100); do found=0; while IFS='|' read -r pane title; do [ "$title" = dotfiles-session-sidebar ] || continue; initial_pane "$pane" && continue; found=1; tmuxc kill-pane -t "$pane" >/dev/null 2>&1 || true; done < <(tmuxc list-panes -a -F '#{pane_id}|#{pane_title}' 2>/dev/null); [ "$found" -eq 0 ] && return 0; sleep 0.05; done; }
wait_for() { local description="$1" command_name="$2" start="$(now_ms)" deadline=$(( $(date +%s) + 20 )); shift 2; log "event=wait.begin description=$description"; while [ "$(date +%s)" -lt "$deadline" ]; do if "$command_name" "$@" 2>/dev/null; then log "event=wait.end description=$description result=PASS duration_ms=$(awk -v s="$start" -v e="$(now_ms)" 'BEGIN{print e-s}')"; return 0; fi; sleep 0.01; done; log "event=wait.end description=$description result=TIMEOUT"; fail "timeout=$description"; return 1; }
sidebar_text() { refresh_sidebar && tmuxc capture-pane -p -t "$SIDEBAR_PANE" 2>/dev/null | grep -Fq -- "$1"; }
session_exists() { tmuxc has-session -t "=$1" 2>/dev/null; }
selected_name() {
    refresh_sidebar || return 1
    tmuxc capture-pane -p -t "$SIDEBAR_PANE" 2>/dev/null |
        sed $'s/\033\\[[0-9;]*m//g' |
        awk '$1 == ">*" { print $2; exit } $1 == ">" { if ($2 == "*") print $3; else print $2; exit }'
}
marker_invariant() {
    local expected_session="$1" marker_state star_count selected_count star_session selected_value actual_current
    refresh_sidebar || return 1
    marker_state="$(tmuxc capture-pane -p -t "$SIDEBAR_PANE" 2>/dev/null |
        sed $'s/\033\\[[0-9;]*m//g' |
        awk '
            $1 == ">*" { stars++; selected++; star=$2; choice=$2; next }
            $1 == "*" { stars++; star=$2; next }
            $1 == ">" { selected++; if ($2 == "*") { star=$3; choice=$3 } else { choice=$2 } }
            END { printf "%d|%d|%s|%s\n", stars+0, selected+0, star, choice }
        ')"
    IFS='|' read -r star_count selected_count star_session selected_value <<< "$marker_state"
    actual_current="$(client_field session_name || true)"
    if [ "$star_count" -ne 1 ] || [ "$selected_count" -ne 1 ] ||
        [ "$star_session" != "$actual_current" ] || [ "$selected_value" != "$expected_session" ]; then
        log "event=marker.invariant result=FAIL expected=$expected_session current=$actual_current star_session=${star_session:-none} selected=${selected_value:-none} stars=$star_count selected_count=$selected_count"
        return 1
    fi
    log "event=marker.invariant result=PASS expected=$expected_session current=$actual_current selected=$selected_value stars=$star_count selected_count=$selected_count"
}
row_for() { local name="$1"; refresh_sidebar || return 1; tmuxc capture-pane -p -t "$SIDEBAR_PANE" 2>/dev/null | sed $'s/\033\\[[0-9;]*m//g' | nl -ba | awk -v n="$name" 'index($0,n)>0 {print $1; exit}'; }
send_tui() { local payload="$1"; refresh_sidebar || return 1; INPUT_SEQUENCE=$((INPUT_SEQUENCE + 1)); log "event=input.begin bytes=$(printf '%b' "$payload" | od -An -tx1 | tr -d ' \n') pane=$SIDEBAR_PANE"; case "$payload" in $'\033[B') tmuxc send-keys -t "$SIDEBAR_PANE" Down;; $'\033[A') tmuxc send-keys -t "$SIDEBAR_PANE" Up;; $'\r') tmuxc send-keys -t "$SIDEBAR_PANE" Enter;; *$'\r') tmuxc send-keys -t "$SIDEBAR_PANE" -l "${payload%$'\r'}"; tmuxc send-keys -t "$SIDEBAR_PANE" Enter;; *) tmuxc send-keys -t "$SIDEBAR_PANE" -l "$(printf '%b' "$payload")";; esac; log "event=input.end pane=$SIDEBAR_PANE"; scan_live_panes "input-$INPUT_SEQUENCE" || true; scan_client_stream "input-$INPUT_SEQUENCE" || true; }
move_selection_to() { local target="$1" current i; for i in $(seq 1 30); do current="$(selected_name || true)"; [ "$current" = "$target" ] && return 0; send_tui $'\033[B' || return 1; wait_for "selection-step-$target-$i" selected_name || return 1; done; log "event=selection.end target=$target result=FAIL selected=$(selected_name || true)"; return 1; }
create_session() { local name="$1" start="$(now_ms)" prompt enter ready total result; send_tui c; wait_for "prompt-$name" sidebar_text New: || return 1; prompt="$(now_ms)"; send_tui "$name"$'\r'; enter="$(now_ms)"; wait_for "session-$name" session_exists "$name" || return 1; ready="$(now_ms)"; total="$(awk -v s="$start" -v r="$ready" 'BEGIN{print r-s}')"; result="$(awk -v t="$total" 'BEGIN{print(t>5000)?"FAIL":"PASS"}')"; printf 'create\t%s\t%s\t%s\n' "$name" "$total" "$result" >> "$RESULT_LOG"; log "event=session.create name=$name c_to_prompt_ms=$(awk -v s="$start" -v p="$prompt" 'BEGIN{print p-s}') enter_to_session_ms=$(awk -v e="$enter" -v r="$ready" 'BEGIN{print r-e}') total_ms=$total result=$result"; capture "create-$name"; [ "$result" = PASS ] || fail "create-latency-$name"; }
switch_once() {
    local index="$1" before="$(client_field session_name)" target start current after duration result before_sidebar after_sidebar duplicate_count identity_result target_pane
    target="${TEST_SESSIONS[$(((index - 1) % ${#TEST_SESSIONS[@]}))]}"
    [ "$target" = "$before" ] && target="${TEST_SESSIONS[$((index % ${#TEST_SESSIONS[@]}))]}"
    # The source and target windows intentionally have different physical
    # panes in the window-local model. Measure the target pane identity before
    # selection, then require that same target pane after switch/stabilization.
    target_pane="$(session_sidebar_pane "$target" || true)"
    before_sidebar="$target_pane"
    trace_before="$(wc -l < "$RUN_DIR/trace.log" 2>/dev/null || printf 0)"
    log "event=session.switch.target iteration=$index from=$before target=$target"
    move_selection_to "$target" || { fail "selection-$index-target-$target"; return 1; }
    start="$(now_ms)"
    log "event=session.switch.enter iteration=$index target=$target"
    send_tui $'\r'
    sample_user_transition "$index" "$target" "$start" "$before_sidebar" "$trace_before" || true
    current="$SAMPLE_ACTUAL"
    after_sidebar="$SAMPLE_AFTER_SIDEBAR"
    duration="$(trace_switch_duration_ms "$trace_before")"
    [ -n "$duration" ] || duration="$SAMPLE_FIRST_TARGET"
    if ! marker_invariant "$target"; then
        SAMPLE_FAILURE=MARKER_INVARIANT
    fi
    if [ -n "$after_sidebar" ]; then
        IFS='|' read -r SAMPLE_FULL_RENDER_COUNT SAMPLE_GEOMETRY_RENDER_COUNT < <(
            trace_transition_full_render_counts "$trace_before" "$after_sidebar"
        )
    fi
    duplicate_count="$(session_sidebar_count "$target")"
    identity_result="$([ -n "$before_sidebar" ] && [ "$before_sidebar" = "$after_sidebar" ] && [ "$duplicate_count" -eq 1 ] && echo PASS || echo FAIL)"
    result="$(awk -v d="$duration" -v c="$([ "$current" = "$target" ] && echo 1 || echo 0)" -v i="$([ "$identity_result" = PASS ] && echo 1 || echo 0)" -v n="$duplicate_count" -v f="$SAMPLE_FAILURE" -v r="${SAMPLE_FULL_RENDER_COUNT:-0}" 'BEGIN{if(!c||d>2500||!i||n!=1||r>0||f=="MARKER_INVARIANT"||f=="SIDEBAR_GAP"||f=="TARGET_NOT_REACHED"||f=="CLIENT_REVERTED") print "FAIL"; else if(f=="OBSERVER_TOO_SLOW") print "INCONCLUSIVE"; else print "PASS"}')"
    printf 'switch\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$index" "$before" "$current" "$result" "$before_sidebar" "$after_sidebar" "$duplicate_count" "$SAMPLE_FAILURE" "$duration" >> "$RESULT_LOG"
    log "event=session.switch iteration=$index from=$before target=$target to=$current duration_ms=$duration sidebar_before=$before_sidebar sidebar_after=$after_sidebar duplicate_sidebars=$duplicate_count identity=$identity_result failure_class=$SAMPLE_FAILURE result=$result"
    if [ "$result" = FAIL ]; then
        fail "switch-$index-$SAMPLE_FAILURE"
    elif [ "$result" = INCONCLUSIVE ]; then
        INCONCLUSIVE_COUNT=$((INCONCLUSIVE_COUNT + 1))
        log "event=observer.inconclusive iteration=$index max_sample_interval_ms=$SAMPLE_MAX_INTERVAL"
    fi
}
restore_trace_env() { local entry var value; for entry in "$ORIGINAL_TRACE_ENV" "$ORIGINAL_TRACE_FILE_ENV" "$ORIGINAL_DEBUG_ENV" "$ORIGINAL_DEBUG_FILE_ENV"; do case "$entry" in -*) var="${entry#-}"; tmuxc set-environment -gu "$var" >/dev/null 2>&1 || true;; *=*) var="${entry%%=*}"; value="${entry#*=}"; tmuxc set-environment -g "$var" "$value" >/dev/null 2>&1 || true;; "") :;; esac; done; [ -n "$ORIGINAL_TRACE_ENV" ] || tmuxc set-environment -gu TMUX_SESSION_LAUNCHER_TRACE >/dev/null 2>&1 || true; [ -n "$ORIGINAL_TRACE_FILE_ENV" ] || tmuxc set-environment -gu TMUX_SESSION_LAUNCHER_TRACE_FILE >/dev/null 2>&1 || true; [ -n "$ORIGINAL_DEBUG_ENV" ] || tmuxc set-environment -gu TMUX_SESSION_LAUNCHER_DEBUG >/dev/null 2>&1 || true; [ -n "$ORIGINAL_DEBUG_FILE_ENV" ] || tmuxc set-environment -gu TMUX_SESSION_LAUNCHER_DEBUG_FILE >/dev/null 2>&1 || true; }
cleanup() { local status=$?; set +e; log "event=cleanup.begin status=$status"; tmuxc switch-client -c "$CLIENT_TTY" -t "$ORIGINAL_WINDOW" >/dev/null 2>&1 || true; for name in "${TEST_SESSIONS[@]:-}"; do tmuxc kill-session -t "=$name" >/dev/null 2>&1 || true; done; [ -n "$TEST_WINDOW_ID" ] && tmuxc kill-window -t "$TEST_WINDOW_ID" >/dev/null 2>&1 || true; tmuxc set-option -w -t "$ORIGINAL_WINDOW" @dotfiles_sidebar_enabled 0 >/dev/null 2>&1 || true; remove_test_sidebars; tmuxc switch-client -c "$CLIENT_TTY" -t "$ORIGINAL_WINDOW" >/dev/null 2>&1 || true; sleep 0.5; remove_test_sidebars; if [ -n "$ORIGINAL_SIDEBAR_ENABLED" ]; then tmuxc set-option -w -t "$ORIGINAL_WINDOW" @dotfiles_sidebar_enabled "$ORIGINAL_SIDEBAR_ENABLED" >/dev/null 2>&1 || true; else tmuxc set-option -uw -t "$ORIGINAL_WINDOW" @dotfiles_sidebar_enabled >/dev/null 2>&1 || true; fi; if [ -n "$ORIGINAL_SIDEBAR_MANAGED" ]; then tmuxc set-option -w -t "$ORIGINAL_WINDOW" @dotfiles_sidebar_managed "$ORIGINAL_SIDEBAR_MANAGED" >/dev/null 2>&1 || true; else tmuxc set-option -uw -t "$ORIGINAL_WINDOW" @dotfiles_sidebar_managed >/dev/null 2>&1 || true; fi; restore_trace_env; if [ -n "$CLIENT_CAPTURE_PID" ]; then kill "$CLIENT_CAPTURE_PID" >/dev/null 2>&1 || true; wait "$CLIENT_CAPTURE_PID" 2>/dev/null || true; fi; snapshot; log "event=cleanup.end status=$status failures=$FAILURES"; exit "$status"; }

normalize_test_window_sidebar() {
  local panes primary pane
  for _ in $(seq 1 40); do
    panes="$(tmuxc list-panes -t "$TEST_WINDOW_ID" -F '#{pane_id}|#{pane_title}' 2>/dev/null |
      awk -F '|' '$2 == "dotfiles-session-sidebar" {print $1}')"
    primary="$(printf '%s\n' "$panes" | sed -n '1p')"
    if [ -n "$primary" ]; then
      while IFS= read -r pane; do
        [ -n "$pane" ] && [ "$pane" != "$primary" ] && tmuxc kill-pane -t "$pane" >/dev/null 2>&1 || true
      done <<EOF
$panes
EOF
      tmuxc respawn-pane -k -t "$primary" "$sidebar_command" >/dev/null 2>&1 || true
      SIDEBAR_PANE="$primary"
      return 0
    fi
    sleep 0.05
  done
  return 1
}
trap cleanup EXIT INT TERM
[ -n "$CLIENT_TTY" ] || { echo 'ERROR: no attached user client' >&2; exit 2; }
ORIGINAL_SESSION="$(client_field session_name)"; ORIGINAL_WINDOW="$(client_field window_id)"; INITIAL_PANES="$(tmuxc list-panes -a -F '#{pane_id}')"; ORIGINAL_SIDEBAR_ENABLED="$(tmuxc show-options -wqv -t "$ORIGINAL_WINDOW" @dotfiles_sidebar_enabled 2>/dev/null || true)"; ORIGINAL_SIDEBAR_MANAGED="$(tmuxc show-options -wqv -t "$ORIGINAL_WINDOW" @dotfiles_sidebar_managed 2>/dev/null || true)"; ORIGINAL_TRACE_ENV="$(tmuxc show-environment -g TMUX_SESSION_LAUNCHER_TRACE 2>/dev/null || true)"; ORIGINAL_TRACE_FILE_ENV="$(tmuxc show-environment -g TMUX_SESSION_LAUNCHER_TRACE_FILE 2>/dev/null || true)"; ORIGINAL_DEBUG_ENV="$(tmuxc show-environment -g TMUX_SESSION_LAUNCHER_DEBUG 2>/dev/null || true)"; ORIGINAL_DEBUG_FILE_ENV="$(tmuxc show-environment -g TMUX_SESSION_LAUNCHER_DEBUG_FILE 2>/dev/null || true)"; tmuxc set-option -gq @dotfiles_sidebar_enabled 1; tmuxc set-option -gq @dotfiles_sidebar_owner_client "$CLIENT_TTY"; tmuxc set-option -s -t "=$ORIGINAL_SESSION" @dotfiles_sidebar_managed 1; tmuxc set-environment -g TMUX_SESSION_LAUNCHER_TRACE 1; tmuxc set-environment -g TMUX_SESSION_LAUNCHER_TRACE_FILE "$RUN_DIR/trace.log"; tmuxc set-environment -g TMUX_SESSION_LAUNCHER_DEBUG 1; tmuxc set-environment -g TMUX_SESSION_LAUNCHER_DEBUG_FILE "$RUN_DIR/debug.log"; log "event=test.start socket=default client=$CLIENT_TTY original_session=$ORIGINAL_SESSION original_window=$ORIGINAL_WINDOW initial_panes=$INITIAL_PANES original_sidebar_enabled=$ORIGINAL_SIDEBAR_ENABLED"; snapshot
if [ "$CAPTURE_CLIENT" = true ]; then
  command -v script >/dev/null 2>&1 || { echo 'ERROR: script(1) is required for user tmux client stream capture' >&2; exit 2; }
  script -qefc "TERM=xterm tmux -L default attach-session -t =$ORIGINAL_SESSION" "$RUN_DIR/client.log" >/dev/null 2>&1 & CLIENT_CAPTURE_PID=$!; log "event=client-capture.start pid=$CLIENT_CAPTURE_PID session=$ORIGINAL_SESSION"; sleep 0.2
else
  log "event=client-capture.skip reason=use-existing-attached-client tty=$CLIENT_TTY"
fi
tmuxc run-shell "env TMUX_SESSION_LAUNCHER_TRACE=1 TMUX_SESSION_LAUNCHER_TRACE_FILE='$RUN_DIR/trace.log' TMUX_SESSION_LAUNCHER_DEBUG=1 TMUX_SESSION_LAUNCHER_DEBUG_FILE='$RUN_DIR/debug.log' '$LAUNCHER' --install-sidebar-hooks" >/dev/null 2>&1 || true
TEST_WINDOW_ID="$(tmuxc new-window -d -t "=$ORIGINAL_SESSION:" -n codex-live -c "$REPO_ROOT" -P -F '#{window_id}' 'sleep 300')"; tmuxc switch-client -c "$CLIENT_TTY" -t "$TEST_WINDOW_ID"; log "event=test-window.created window=$TEST_WINDOW_ID"
sidebar_command="env TMUX_SESSION_HISTORY_DIR='$HISTORY_DIR' TMUX_SESSION_LAUNCHER_TRACE=1 TMUX_SESSION_LAUNCHER_TRACE_FILE='$RUN_DIR/trace.log' TMUX_SESSION_LAUNCHER_DEBUG=1 TMUX_SESSION_LAUNCHER_DEBUG_FILE='$RUN_DIR/debug.log' '$LAUNCHER' --sidebar"; tmuxc run-shell "env TMUX_SESSION_HISTORY_DIR='$HISTORY_DIR' TMUX_SESSION_LAUNCHER_TRACE=1 TMUX_SESSION_LAUNCHER_TRACE_FILE='$RUN_DIR/trace.log' TMUX_SESSION_LAUNCHER_DEBUG=1 TMUX_SESSION_LAUNCHER_DEBUG_FILE='$RUN_DIR/debug.log' '$LAUNCHER' --ensure-sidebar-window '$TEST_WINDOW_ID'" >/dev/null 2>&1 || true; normalize_test_window_sidebar || { fail 'sidebar-create'; exit 1; }; refresh_sidebar; tmuxc select-pane -t "$SIDEBAR_PANE"; wait_for sidebar-ready sidebar_text sessions || true; capture initial
for index in 1 2 3; do name="live-${RUN_ID##*-}$index"; TEST_SESSIONS+=("$name"); create_session "$name" || true; done
for index in 1 2 3 4 5 6; do switch_once "$index" || true; done
build_user_switch_manifest
for direction in horizontal vertical; do current="$(client_field session_name || true)"; window_id="$(tmuxc display-message -p -t "=$current:" '#{window_id}' 2>/dev/null || true)"; work="$(tmuxc list-panes -t "$window_id" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 != "dotfiles-session-sidebar" {print $1; exit}')"; before="$RUN_DIR/layout-$direction-before.tsv"; after="$RUN_DIR/layout-$direction-after.tsv"; tmuxc list-panes -t "$window_id" -F '#{pane_id}|#{pane_title}|#{pane_left},#{pane_top},#{pane_width},#{pane_height}' > "$before"; if [ -n "$work" ]; then [ "$direction" = horizontal ] && tmuxc split-window -h -t "$work" -c "$REPO_ROOT" || tmuxc split-window -v -t "$work" -c "$REPO_ROOT"; tmuxc list-panes -t "$window_id" -F '#{pane_id}|#{pane_title}|#{pane_left},#{pane_top},#{pane_width},#{pane_height}' > "$after"; log "event=layout direction=$direction before=$before after=$after"; else fail "work-pane-$direction"; fi; done
scan_live_panes final || true
scan_client_stream final || true
if grep -aEin -- "$ERROR_PATTERN" "$RUN_DIR/trace.log" "$RUN_DIR/debug.log" 2>/dev/null >> "$RUN_DIR/error-matches.log" || [ -s "$RUN_DIR/error-matches.log" ]; then fail known-launcher-error; else log 'event=error-scan result=PASS source=trace-debug-and-pane-history matches=0'; fi
if [ "$FAILURES" -eq 0 ]; then echo "PASS: user tmux required live suite inconclusive=$INCONCLUSIVE_COUNT"; else echo "FAIL: user tmux required live suite failures=$FAILURES inconclusive=$INCONCLUSIVE_COUNT" >&2; exit 1; fi
