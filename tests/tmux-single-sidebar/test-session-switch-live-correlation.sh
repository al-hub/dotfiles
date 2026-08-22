#!/usr/bin/env bash
set -euo pipefail

# Real attached-PTY session-switch correlation. This is deliberately separate
# from the broad keyboard workflow: the first failed Enter stops the scenario
# so its source/target/phase/pane state is not overwritten by later input.

SCENARIO_NAME=live-session-switch-correlation
export SCENARIO_NAME
export TMUX_INTERACTIVE_CREATE_PEER=false
export TMUX_SESSION_LAUNCHER_TRACE=1
export TMUX_SESSION_LAUNCHER_DEBUG=1
source "$(dirname -- "$BASH_SOURCE")/test-interactive-common.sh"
KEEP_RUN_DIR=true

EXPECTED=10
MANIFEST_FILE="$RUN_DIR/session-switch-manifest.tsv"
SAMPLES_FILE="$RUN_DIR/transition-samples.tsv"
EVENTS_FILE="$RUN_DIR/transition-events.tsv"
TOPOLOGY_FILE="$RUN_DIR/topology.tsv"
TOPOLOGY="${TMUX_SESSION_SWITCH_TOPOLOGY:-single}"
ERROR_PATTERN='session[[:space:]]+switch.*failed|returned 1|switch.abort|transition.rollback'

file_bytes() { [ -f "$1" ] && wc -c < "$1" | tr -d ' ' || echo 0; }
file_lines() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }
now_ms() { timestamp_mono_ms; }

sidebar_state()
{
    local pane
    pane="$(sidebar_pane_id 2>/dev/null || true)"
    [ -n "$pane" ] || {
        printf 'pane=absent|pid=|geometry=\n'
        return 0
    }
    printf 'pane=%s|pid=%s|geometry=%s\n' \
        "$pane" \
        "$(tmuxc display-message -p -t "$pane" '#{pane_pid}' 2>/dev/null || true)" \
        "$(tmuxc display-message -p -t "$pane" '#{pane_left},#{pane_top},#{pane_width},#{pane_height}' 2>/dev/null || true)"
}

sidebar_state_for_session()
{
    local session="$1" window pane
    window="$(tmuxc display-message -p -t "=$session:" '#{window_id}' 2>/dev/null || true)"
    pane="$(tmuxc list-panes -t "$window" -F '#{pane_id}|#{pane_title}' 2>/dev/null |
        awk -F '|' '$2 == "dotfiles-session-sidebar" {print $1; exit}')"
    [ -n "$pane" ] || {
        printf 'pane=absent|pid=|geometry=\n'
        return 0
    }
    printf 'pane=%s|pid=%s|geometry=%s\n' \
        "$pane" \
        "$(tmuxc display-message -p -t "$pane" '#{pane_pid}' 2>/dev/null || true)" \
        "$(tmuxc display-message -p -t "$pane" '#{pane_left},#{pane_top},#{pane_width},#{pane_height}' 2>/dev/null || true)"
}

trace_slice()
{
    local before="$1" after="$2"
    [ "$after" -gt "$before" ] || return 0
    sed -n "$((before + 1)),$after p" "$TRACE_FILE" 2>/dev/null || true
}

non_geometry_render_count()
{
    local pane="$1" operation_id="$2" trace="$3"
    printf '%s\n' "$trace" | awk -v prefix="pane=$pane " -v operation_id="$operation_id" '
        index($0, "transition.begin operation_id=" operation_id " ") { active=1; next }
        index($0, "transition.finish operation_id=" operation_id " ") { active=0; next }
        !active { next }
        /switch\.force-refresh\.signal/ { force=1; next }
        /selection\.sync\.delta/ { force=1; next }
        index($0, prefix "render.full.check reason=geometry-invalidated") { geometry=1; next }
        index($0, prefix "render.full.check reason=topology-invalidated") { geometry=1; next }
        index($0, prefix "render.full.check reason=external-layout-change") { geometry=1; next }
        index($0, prefix "render.full.begin") && $0 ~ /reason=force-refresh/ { force=0; next }
        index($0, prefix "render.full.begin") {
            if (!geometry && !force && !finished) count++
            geometry=0
            force=0
        }
        END { print count + 0 }
    '
}

operation_id_from_trace()
{
    local before="$1" after="$2"
    trace_slice "$before" "$after" |
        sed -n 's/.*transition\.begin operation_id=\([^ ]*\).*/\1/p' | head -n 1
}

phase_list()
{
    local operation_id="$1" before="$2" after="$3"
    trace_slice "$before" "$after" |
        sed -n "s/.*transition\.phase operation_id=$operation_id .*phase=\([^ ]*\).*/\1/p" |
        paste -sd, -
}

sidebar_field()
{
    local key="$1" state="$2"
    printf '%s\n' "$state" | tr '|' '\n' |
        sed -n "s/^${key}=//p" | head -n 1
}

batched_tmux_state()
{
    tmuxc display-message -p -t "$CLIENT_TTY" \
        'CLIENT|#{client_session}|#{window_id}|#{pane_id}' \; \
        list-panes -a -F 'PANE|#{pane_id}|#{pane_title}|#{session_name}|#{window_id}|#{pane_pid}|#{pane_left},#{pane_top},#{pane_width},#{pane_height}' 2>/dev/null || true
}

prepare_topology()
{
    local target_window work direction
    printf 'topology=%s\n' "$TOPOLOGY" > "$TOPOLOGY_FILE"
    [ "$TOPOLOGY" = single ] && return 0
    target_window="$(tmuxc display-message -p -t '=live-corr-2:' '#{window_id}')"
    work="$(tmuxc list-panes -t "$target_window" -F '#{pane_id}|#{pane_title}' |
        awk -F '|' '$2 != "dotfiles-session-sidebar" {print $1; exit}')"
    [ -n "$work" ] || return 1
    case "$TOPOLOGY" in
        horizontal) direction=-h;;
        vertical) direction=-v;;
        *) return 2;;
    esac
    tmuxc split-window "$direction" -t "$work" -c "$REPO_ROOT" >/dev/null
    tmuxc list-panes -t "$target_window" \
        -F '#{pane_id}|#{pane_title}|#{pane_left},#{pane_top},#{pane_width},#{pane_height}' \
        >> "$TOPOLOGY_FILE"
}

record_transition_event()
{
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(now_ms)" "$1" "$2" "$3" "$4" "$5" >> "$EVENTS_FILE"
}

sample_transition()
{
    local iteration="$1" start_ms="$2" operation_id="$3" target_sidebar="$4" trace_before="$5"
    local now elapsed previous_sample_ms sample_interval current sidebar phase output_size trace_size pane_state batch client_window pane_line
    local first_target_ms="" source_revert_ms="" first_ready_ms="" stable=0 sidebar_gap_seen=0 identity_changed=0
    local full_render_count=0 hook_event_count=0 max_sample_interval=0
    local failure_class=PASS last_operation_id="$operation_id"
    local target_pane target_pid current_pane current_pid
    target_pane="$(sidebar_field pane "$target_sidebar")"
    target_pid="$(sidebar_field pid "$target_sidebar")"
    # tmux list/capture calls make each sample materially slower than the
    # nominal sleep. Eight consecutive target samples are a stable boundary;
    # keeping the cap finite prevents an observer bug from hanging the suite.
    for _ in $(seq 1 160); do
        now="$(now_ms)"
        elapsed="$(awk -v s="$start_ms" -v n="$now" 'BEGIN { printf "%.3f", n-s }')"
        sample_interval=""
        if [ -n "${previous_sample_ms:-}" ]; then
            sample_interval="$(awk -v p="$previous_sample_ms" -v n="$now" 'BEGIN { printf "%.3f", n-p }')"
            max_sample_interval="$(awk -v m="$max_sample_interval" -v i="$sample_interval" 'BEGIN { print (i > m) ? i : m }')"
        fi
        previous_sample_ms="$now"
        trace_size="$(file_lines "$TRACE_FILE")"
        last_operation_id="$(operation_id_from_trace 0 "$trace_size" | tail -n 1)"
        [ -n "$last_operation_id" ] || last_operation_id="$operation_id"
        phase="$(trace_slice 0 "$trace_size" | sed -n "s/.*transition\.phase operation_id=$last_operation_id .*phase=\([^ ]*\).*/\1/p" | tail -n 1)"
        batch="$(batched_tmux_state)"
        current="$(printf '%s\n' "$batch" | awk -F '|' '$1 == "CLIENT" {print $2; exit}')"
        client_window="$(printf '%s\n' "$batch" | awk -F '|' '$1 == "CLIENT" {print $3; exit}')"
        pane_line="$(printf '%s\n' "$batch" | awk -F '|' -v w="$client_window" '$1 == "PANE" && $3 == "dotfiles-session-sidebar" && $5 == w {print; exit}')"
        current_pane="$(printf '%s\n' "$pane_line" | awk -F '|' '{print $2}')"
        current_pid="$(printf '%s\n' "$pane_line" | awk -F '|' '{print $6}')"
        sidebar="pane=${current_pane:-absent}|pid=${current_pid:-}|geometry=$(printf '%s\n' "$pane_line" | awk -F '|' '{print $7}')"
        output_size="$(file_bytes "$OUTPUT_LOG")"
        pane_state="$(printf '%s\n' "$batch" | awk -F '|' '$1 == "PANE" {print $2 ":" $3 ":" $4 ":" $5 ":" $7}' | tr ' \t\n' '_' | sed 's/_$//' || true)"
        recent_trace="$(trace_slice "$trace_before" "$trace_size")"
        full_render_count="$(non_geometry_render_count "$target_pane" "$last_operation_id" "$recent_trace")"
        hook_event_count="$(printf '%s\n' "$recent_trace" | grep -Ec "pane=$target_pane .*transition\\.hook|pane=$target_pane .*sidebar\\.hook" || true)"
        # The client necessarily leaves the source pane while switching. Only
        # a change after the target sidebar is reached is an identity fault.
        if [ -n "$first_target_ms" ] && [ -n "$current_pane" ] &&
            [ "$current_pane" != absent ] && [ "$current_pane" != "$target_pane" ]; then
            identity_changed=1
        fi
        sample_class="$failure_class"
        [ "$current_pane" = absent ] || [ -z "$current_pane" ] && sample_class=SIDEBAR_GAP
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$iteration" "$elapsed" "$last_operation_id" "$phase" "$current" \
            "$current_pane" "$current_pid" "$(sidebar_field geometry "$sidebar")" \
            "$target_pane" "$target_pid" "$output_size" "$trace_size" "$sample_interval" "$full_render_count" "$hook_event_count" "$pane_state" "$sample_class" \
            >> "$SAMPLES_FILE"
        if [ -z "$first_target_ms" ] && [ "$current" = "$target" ]; then
            first_target_ms="$elapsed"
        elif [ -n "$first_target_ms" ] && [ "$current" != "$target" ]; then
            source_revert_ms="$elapsed"
            failure_class=CLIENT_REVERTED
            break
        fi
        if [ "$current_pane" = absent ] || [ -z "$current_pane" ]; then
            sidebar_gap_seen=1
        fi
        if [ -n "$first_target_ms" ] && [ "$current_pane" = "$target_pane" ] && [ "$current_pid" = "$target_pid" ]; then
            stable=$((stable + 1))
        else
            stable=0
        fi
        if [ "$phase" = READY ] && [ -z "$first_ready_ms" ]; then
            first_ready_ms="$elapsed"
        fi
        if [ "$stable" -ge 8 ]; then
            failure_class=PASS
            break
        fi
        sleep 0.025
    done
    if [ -z "$first_target_ms" ] && [ "$failure_class" = PASS ]; then
        failure_class=TARGET_NOT_REACHED
    fi
    if [ "$failure_class" = PASS ] && [ "$sidebar_gap_seen" -eq 1 ]; then
        failure_class=SIDEBAR_DISAPPEARED
    fi
    if [ "$failure_class" = PASS ] && [ "$identity_changed" -eq 1 ]; then
        failure_class=SIDEBAR_IDENTITY_CHANGED
    fi
    if [ "$failure_class" = PASS ] && [ "$full_render_count" -gt 0 ]; then
        failure_class=FULL_REDRAW_DURING_SWITCH
    fi
    OBS_FAILURE_CLASS="$failure_class"
    OBS_FIRST_TARGET_MS="${first_target_ms:-}"
    OBS_SOURCE_REVERT_MS="${source_revert_ms:-}"
    OBS_READY_MS="${first_ready_ms:-}"
    OBS_END_MS="$elapsed"
    OBS_OPERATION_ID="$last_operation_id"
    OBS_MAX_SAMPLE_INTERVAL="$max_sample_interval"
    OBS_FULL_RENDER_COUNT="$full_render_count"
    OBS_HOOK_EVENT_COUNT="$hook_event_count"
    [ "$failure_class" = PASS ]
}

failure_snapshot()
{
    local iteration="$1" reason="$2" trace_before="$3" output_before="$4" label="failure-$iteration"
    KEEP_RUN_DIR=true
    test_log "failure.snapshot iteration=$iteration reason=$reason"
    tmuxc list-clients -F 'control=#{client_control_mode}|tty=#{client_tty}|session=#{session_name}|window=#{window_id}|pane=#{pane_id}|prefix=#{client_prefix}' \
        > "$RUN_DIR/$label-clients.tsv" 2>/dev/null || true
    tmuxc list-panes -a -F 'session=#{session_name}|window=#{window_id}|pane=#{pane_id}|title=#{pane_title}|pid=#{pane_pid}|active=#{pane_active}|dead=#{pane_dead}|geometry=#{pane_left},#{pane_top},#{pane_width},#{pane_height}' \
        > "$RUN_DIR/$label-panes.tsv" 2>/dev/null || true
    tmuxc show-options -g 2>/dev/null | grep -E 'dotfiles_sidebar|sidebar_force_refresh' \
        > "$RUN_DIR/$label-options.txt" || true
    sidebar_pane_id >/dev/null 2>&1 && tmuxc capture-pane -e -p -J -t "$(sidebar_pane_id)" \
        > "$RUN_DIR/$label-sidebar.log" 2>/dev/null || true
    output_after="$(file_bytes "$OUTPUT_LOG")"
    if [ "$output_after" -gt "$output_before" ]; then
        dd if="$OUTPUT_LOG" of="$RUN_DIR/$label-client.raw" iflag=skip_bytes,count_bytes \
            skip="$output_before" count="$((output_after - output_before))" status=none 2>/dev/null || true
    fi
    trace_slice "$trace_before" "$(file_lines "$TRACE_FILE")" > "$RUN_DIR/$label-trace.log"
    tail -c 12000 "$DEBUG_FILE" > "$RUN_DIR/$label-debug.log" 2>/dev/null || true
    printf 'iteration=%s\nreason=%s\nsidebar=%s\n' "$iteration" "$reason" "$(sidebar_state)" \
        > "$RUN_DIR/$label-summary.txt"
}

move_selection_to()
{
    local target="$1" current step attempt pane
    for attempt in 1 2; do
        focus_sidebar
        for step in $(seq 1 40); do
            current="$(sidebar_selected_name 2>/dev/null || true)"
            [ "$current" = "$target" ] && return 0
            send_keys $'\033[B'
            # A completed switch may leave the target sidebar in its first
            # refresh cycle; wait for the visible marker, not just input delivery.
            sleep 0.12
        done
        pane="$(sidebar_pane_id 2>/dev/null || true)"
        test_log "selection.input.recovery attempt=$attempt target=$target selected=${current:-none} pane=${pane:-none}"
        # Recovery is explicitly logged and scoped to the test observer. It
        # distinguishes PTY input loss from a production selection failure.
        [ -n "$pane" ] && tmuxc select-pane -t "$pane" 2>/dev/null || true
        [ -n "$pane" ] && tmuxc send-keys -t "$pane" Down 2>/dev/null || true
        sleep 0.25
    done
    test_log "selection.failed target=$target selected=$(sidebar_selected_name 2>/dev/null || true)"
    return 1
}

wait_for_target()
{
    local target="$1" deadline=$(( $(date +%s) + 5 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        [ "$(client_session 2>/dev/null || true)" = "$target" ] && return 0
        sleep 0.05
    done
    return 1
}

wait_for_marker_invariant()
{
    local target="$1" attempt
    for attempt in $(seq 1 100); do
        sidebar_marker_invariant "$target" && return 0
        sleep 0.05
    done
    test_log "marker-invariant.timeout target=$target selected=$(sidebar_selected_name 2>/dev/null || true) client=$(client_session 2>/dev/null || true)"
    return 1
}

capture_error_delta()
{
    local output_before="$1" output_after="$2" trace_before="$3" trace_after="$4" raw="$RUN_DIR/error-delta.raw" normalized="$RUN_DIR/error-delta.txt"
    if [ "$output_after" -gt "$output_before" ]; then
        dd if="$OUTPUT_LOG" of="$raw" iflag=skip_bytes,count_bytes \
            skip="$output_before" count="$((output_after - output_before))" status=none 2>/dev/null || true
        perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\e\][^\a]*\a//g; s/\r//g' "$raw" > "$normalized"
    else
        : > "$normalized"
    fi
    {
        cat "$normalized"
        trace_slice "$trace_before" "$trace_after"
    } | grep -Ein -- "$ERROR_PATTERN" > "$RUN_DIR/error-matches.log" 2>/dev/null
}

setup_interactive_test
create_session live-corr-1
create_session live-corr-2
create_session live-corr-3
tmuxc switch-client -c "$CLIENT_TTY" -t '=live-corr-1:'
wait_until "initial live correlation session" "wait_session 'live-corr-1'"
focus_sidebar
wait_until "initial live correlation sidebar" sidebar_ready
prepare_topology || {
    printf '%s\n' "FAIL: topology setup failed topology=$TOPOLOGY" >&2
    exit 1
}

: > "$TRACE_FILE"
: > "$DEBUG_FILE"
: > "$MANIFEST_FILE"
: > "$SAMPLES_FILE"
printf '%s\n' 'iteration	source	target	operation_id	input_seq	input_bytes	selected_before	selected_after	client_before	client_after	trace_before	trace_after	phases	transition_ms	first_target_ms	ready_ms	source_revert_ms	max_sample_interval_ms	full_render_count	hook_event_count	sidebar_before	sidebar_after	failure_class	result' > "$MANIFEST_FILE"
printf '%b\n' 'iteration\telapsed_ms\toperation_id\tphase\tclient_session\tsidebar_pane\tsidebar_pid\tsidebar_geometry\tbefore_sidebar_pane\tbefore_sidebar_pid\toutput_bytes\ttrace_lines\tsample_interval_ms\tfull_render_count\thook_event_count\tpane_state\tfailure_class' > "$SAMPLES_FILE"
printf '%b\n' 'timestamp_ms\tevent\titeration\toperation_id\tsource\ttarget' > "$EVENTS_FILE"
[ "$TOPOLOGY" = single ] || record_transition_event topology.prepare 0 "" live-corr-1 live-corr-2

targets=(live-corr-2 live-corr-3 live-corr-1 live-corr-2 live-corr-3 live-corr-1 live-corr-2 live-corr-3 live-corr-1 live-corr-2)
completed=0
for iteration in $(seq 1 "$EXPECTED"); do
    source_session="$(client_session)"
    target="${targets[$((iteration - 1))]}"
    move_selection_to "$target" || {
        failure_snapshot "$iteration" selection-not-target "$(file_lines "$TRACE_FILE")" "$(file_bytes "$OUTPUT_LOG")"
        exit 1
    }
    if ! wait_for_marker_invariant "$target"; then
        failure_snapshot "$iteration" selection-marker-invariant "$(file_lines "$TRACE_FILE")" "$(file_bytes "$OUTPUT_LOG")"
        printf '%s\n' "FAIL: iteration=$iteration class=SELECTION_MARKER_INVARIANT target=$target source=$source_session" >&2
        exit 1
    fi
    selected_before="$(sidebar_selected_name 2>/dev/null || true)"
    client_before="$source_session"
    sidebar_before="$(sidebar_state_for_session "$target")"
    trace_before="$(file_lines "$TRACE_FILE")"
    output_before="$(file_bytes "$OUTPUT_LOG")"
    input_before="$(file_bytes "$INPUT_LOG")"
    start_ms="$(now_ms)"
    record_transition_event input.sent "$iteration" "" "$source_session" "$target"
    send_keys $'\r'
    input_after="$(file_bytes "$INPUT_LOG")"
    operation_id=""
    for _ in $(seq 1 20); do
        trace_after="$(file_lines "$TRACE_FILE")"
        operation_id="$(operation_id_from_trace "$trace_before" "$trace_after")"
        [ -n "$operation_id" ] && break
        sleep 0.025
    done
    record_transition_event transition.begin "$iteration" "$operation_id" "$source_session" "$target"
    sample_transition "$iteration" "$start_ms" "$operation_id" "$sidebar_before" "$trace_before" || {
        trace_after="$(file_lines "$TRACE_FILE")"
        record_transition_event transition.failure "$iteration" "$OBS_OPERATION_ID" "$source_session" "$target"
        failure_snapshot "$iteration" "$OBS_FAILURE_CLASS" "$trace_before" "$output_before"
        printf '%s\n' "FAIL: iteration=$iteration class=$OBS_FAILURE_CLASS target=$target source=$source_session actual=$(client_session 2>/dev/null || true)" >&2
        exit 1
    }
    if ! sidebar_marker_invariant "$target"; then
        trace_after="$(file_lines "$TRACE_FILE")"
        record_transition_event transition.failure "$iteration" "$OBS_OPERATION_ID" "$source_session" "$target"
        failure_snapshot "$iteration" marker-invariant "$trace_before" "$output_before"
        printf '%s\n' "FAIL: iteration=$iteration class=MARKER_INVARIANT target=$target source=$source_session actual=$(client_session 2>/dev/null || true)" >&2
        exit 1
    fi
    record_transition_event stabilization.end "$iteration" "$operation_id" "$source_session" "$target"
    trace_after="$(file_lines "$TRACE_FILE")"
    operation_id="${OBS_OPERATION_ID:-$(operation_id_from_trace "$trace_before" "$trace_after")}"
    [ -n "$operation_id" ] || {
        failure_snapshot "$iteration" transition-not-started "$trace_before" "$output_before"
        exit 1
    }
    output_after="$(file_bytes "$OUTPUT_LOG")"
    selected_after="$(sidebar_selected_name 2>/dev/null || true)"
    client_after="$(client_session)"
    sidebar_after="$(sidebar_state)"
    phases="$(phase_list "$operation_id" "$trace_before" "$trace_after")"
    transition_ms="$OBS_END_MS"
    if capture_error_delta "$output_before" "$output_after" "$trace_before" "$trace_after"; then
        failure_snapshot "$iteration" client-or-trace-error "$trace_before" "$output_before"
        exit 1
    fi
    input_seq="$LAST_INPUT_EVENT_SEQUENCE"
    input_bytes="0d"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$iteration" "$source_session" "$target" "$operation_id" \
        "$input_seq" "$input_bytes" "$selected_before" "$selected_after" \
        "$client_before" "$client_after" "$trace_before" "$trace_after" \
        "$phases" "$transition_ms" "$OBS_FIRST_TARGET_MS" "$OBS_READY_MS" "$OBS_SOURCE_REVERT_MS" \
        "$OBS_MAX_SAMPLE_INTERVAL" "$OBS_FULL_RENDER_COUNT" "$OBS_HOOK_EVENT_COUNT" \
        "$sidebar_before" "$sidebar_after" "$OBS_FAILURE_CLASS" PASS \
        >> "$MANIFEST_FILE"
    completed=$((completed + 1))
done

printf 'completed=%s requested=%s manifest=%s\n' "$completed" "$EXPECTED" "$MANIFEST_FILE"
printf 'PASS: live attached-PTY session switch correlation completed\n'
