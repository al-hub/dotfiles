#!/usr/bin/env bash
set -euo pipefail

# Measurement-only scenario for the user-visible transition:
# sidebar remains mounted while the selected session changes, with each
# session containing a different multi-pane work layout. The sampler records
# sidebar completeness and pane/layout metadata during the real PTY Enter
# transition, including p50/p95 latency. This is diagnostic: different target
# sessions may legitimately have different expected sidebar geometry.

SCENARIO_NAME=switch-visual-layer-measurement
export SCENARIO_NAME
export TMUX_SESSION_LAUNCHER_TRACE=1
export TMUX_SESSION_LAUNCHER_DEBUG=1
source "$(dirname -- "$BASH_SOURCE")/test-interactive-common.sh"
export TMUX_SESSION_LAUNCHER_METRICS_FILE="${TMUX_SESSION_LAUNCHER_METRICS_FILE:-$RUN_DIR/metrics.log}"
export TMUX_SESSION_LAUNCHER_METRICS_RUN_ID="${TMUX_SESSION_LAUNCHER_METRICS_RUN_ID:-$SCENARIO_NAME-$$}"

MEASURE_FILE="$RUN_DIR/visual-transition-samples.tsv"
LATENCY_FILE="$RUN_DIR/visual-transition-latency.tsv"
RAW_SUMMARY_FILE="$RUN_DIR/visual-transition-raw.tsv"
PHASE_FILE="$RUN_DIR/visual-transition-phases.tsv"
EXPECTED_SESSIONS=(visual-a visual-b visual-c)
EXPECTED_TRANSITIONS="${VISUAL_TRANSITIONS:-10}"
declare -A EXPECTED_SIDEBAR_GEOMETRY=()
declare -A EXPECTED_PANE_SIGNATURE=()

now_us() {
  perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000000'
}

visual_signature() {
  local session="$1"
  tmuxc list-panes -t "=$session:" \
    -F '#{pane_index}|#{pane_title}|#{pane_current_path}|#{pane_current_command}|#{pane_left}|#{pane_top}|#{pane_width}|#{pane_height}' |
    sort | cksum | awk '{print $1}'
}

sidebar_geometry_for_session() {
  local session="$1" sidebar_id
  sidebar_id="$(tmuxc list-panes -t "=$session:" -F '#{pane_id}|#{pane_title}' 2>/dev/null |
    awk -F'|' '$2 == "dotfiles-session-sidebar" {print $1; exit}')"
  [ -n "$sidebar_id" ] || return 1
  tmuxc list-panes -t "=$session:" -F '#{pane_id}|#{pane_left}|#{pane_top}|#{pane_width}|#{pane_height}' |
    awk -F'|' -v id="$sidebar_id" '$1 == id {print $2 "|" $3 "|" $4 "|" $5; exit}'
}

visual_sample() {
  local iteration="$1" phase="$2" now="$3" session capture title_count footer_count \
    session_count selected_count layer sidebar_id sidebar_geom expected_geom geometry_match \
    layout pane_signature expected_pane_signature pane_match output_offset
  session="$(client_session)"
  capture="$(tmuxc capture-pane -p -t "$(sidebar_pane_id)" 2>/dev/null || true)"
  title_count="$(printf '%s\n' "$capture" | grep -Ec '^sessions *$' || true)"
  footer_count="$(printf '%s\n' "$capture" | grep -Ec 'j/k .*Enter.*c/r/d.*o.*q' || true)"
  session_count=0
  for name in "${EXPECTED_SESSIONS[@]}"; do
    printf '%s\n' "$capture" | grep -Fq "$name" && session_count=$((session_count + 1))
  done
  selected_count="$(printf '%s\n' "$capture" | grep -Ec '^> *\*? ' || true)"

  if [ -z "$capture" ]; then
    layer=blank
  elif [ "$title_count" -eq 1 ] && [ "$footer_count" -eq 1 ] &&
       [ "$session_count" -eq "${#EXPECTED_SESSIONS[@]}" ] && [ "$selected_count" -eq 1 ]; then
    layer=complete
  else
    layer=partial
  fi

  sidebar_id="$(sidebar_pane_id)"
  sidebar_geom="$(tmuxc list-panes -a -F '#{pane_id}|#{pane_left}|#{pane_top}|#{pane_width}|#{pane_height}' |
    awk -F'|' -v id="$sidebar_id" '$1 == id {print $2 "|" $3 "|" $4 "|" $5; exit}')"
  expected_geom="${EXPECTED_SIDEBAR_GEOMETRY[$session]:-unknown}"
  geometry_match=false
  [ "$sidebar_geom" = "$expected_geom" ] && geometry_match=true
  layout="$(tmuxc display-message -p -t "$CLIENT_TTY" '#{window_layout}')"
  pane_signature="$(visual_signature "$session")"
  expected_pane_signature="${EXPECTED_PANE_SIGNATURE[$session]:-unknown}"
  pane_match=false
  [ "$pane_signature" = "$expected_pane_signature" ] && pane_match=true
  output_offset="$(wc -c < "$OUTPUT_LOG" | tr -d ' ')"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$iteration" "$phase" "$now" "$session" "$layer" "$sidebar_id" \
    "$sidebar_geom" "$expected_geom" "$geometry_match" "$layout" "$pane_signature" \
    "$expected_pane_signature" "$pane_match" \
    "$title_count/$session_count/$footer_count/$selected_count" "$output_offset" \
    >> "$MEASURE_FILE"
}

move_selection_to() {
  local target="$1" row current delta key count i
  row="$(sidebar_row_for "$target")"
  [ -n "$row" ] || return 1
  current="$(tmuxc capture-pane -p -t "$(sidebar_pane_id)" |
    sed $'s/\033\\[[0-9;]*m//g' | nl -ba |
    awk '$0 ~ />[ *]/ {print $1; exit}')"
  [ -n "$current" ] || return 1
  delta=$((row - current))
  [ "$delta" -eq 0 ] && return 0
  key=$'\033[B'
  [ "$delta" -lt 0 ] && key=$'\033[A'
  count="$delta"
  [ "$count" -lt 0 ] && count=$((-count))
  for i in $(seq 1 "$count"); do
    send_keys "$key"
    wait_until "sidebar ready after navigation $target/$i" sidebar_ready
  done
}

switch_fixture_session() {
  local name="$1"
  # Fixture construction is deliberately observer-only. The measured path
  # below still uses the attached PTY and real sidebar arrows/Enter; using the
  # public selector here would make topology setup depend on a prior session's
  # selection marker and contaminate the redraw measurement.
  tmuxc switch-client -c "$CLIENT_TTY" -t "=$name:"
  wait_until "fixture session $name" "wait_session '$name'"
  wait_until "fixture sidebar $name" sidebar_ready
}

trace_operation_id() {
  local from_line="$1" to_line="$2" target="$3"
  awk -v from="$from_line" -v to="$to_line" -v target="$target" '
    NR > from && NR <= to && /transition.begin/ {
      found_target = 0
      operation = ""
      for (i = 1; i <= NF; i++) {
        if ($i == "target=" target) found_target = 1
        if ($i ~ /^operation_id=/) { operation = $i; sub(/^operation_id=/, "", operation) }
      }
      if (found_target && operation != "") { print operation; exit }
    }
  ' "$TRACE_FILE" 2>/dev/null || true
}

trace_phase_us() {
  local from_line="$1" to_line="$2" operation_id="$3" phase="$4"
  awk -v from="$from_line" -v to="$to_line" -v operation_id="$operation_id" -v phase="$phase" '
    NR > from && NR <= to && /transition.phase/ {
      found_operation = 0
      found_phase = 0
      for (i = 1; i <= NF; i++) {
        if ($i == "operation_id=" operation_id) found_operation = 1
        if ($i == "phase=" phase) found_phase = 1
      }
      if (found_operation && found_phase) {
        split($1, timestamp, "\\.")
        value = timestamp[1] * 1000000 + timestamp[2]
        latest = value
      }
    }
    END { if (latest != "") printf "%.0f\n", latest }
  ' "$TRACE_FILE" 2>/dev/null || true
}

trace_ready_after() {
  local from_line="$1"
  awk -v from="$from_line" 'NR > from && /transition.phase/ && /phase=READY/ {found=1} END {exit !found}' "$TRACE_FILE" 2>/dev/null
}

trace_count_range() {
  local from_line="$1" to_line="$2" pattern="$3"
  awk -v from="$from_line" -v to="$to_line" -v pattern="$pattern" \
    'NR > from && NR <= to && $0 ~ pattern {n++} END {print n + 0}' \
    "$TRACE_FILE" 2>/dev/null || printf '0\n'
}

trace_finish_result() {
  local from_line="$1" to_line="$2" operation_id="$3"
  awk -v from="$from_line" -v to="$to_line" -v operation_id="$operation_id" '
    NR > from && NR <= to && /transition.finish/ {
      matched = 0; result = ""
      for (i = 1; i <= NF; i++) {
        if ($i == "operation_id=" operation_id) matched = 1
        if ($i ~ /^result=/) { result = $i; sub(/^result=/, "", result) }
      }
      if (matched) latest = result
    }
    END { print (latest == "" ? "unknown" : latest) }
  ' "$TRACE_FILE" 2>/dev/null || printf 'unknown\n'
}

phase_percentile_us() {
  local field="$1" percentile="$2" count index
  count="$(awk -F '\t' -v field="$field" -v min=1 'NR > 1 && $field >= min {print $field}' "$PHASE_FILE" |
    sort -n | wc -l | tr -d ' ')"
  [ "$count" -gt 0 ] || { printf 'NA'; return 0; }
  index=$(( (count * percentile + 99) / 100 ))
  awk -F '\t' -v field="$field" -v min=1 'NR > 1 && $field >= min {print $field}' "$PHASE_FILE" |
    sort -n | sed -n "${index}p"
}

record_phase_measurement() {
  local iteration="$1" target="$2" input_us="$3" trace_before="$4" trace_after="$5" raw_bytes="$6"
  local operation_id prepare snapshot move_sidebar switch_client restore_layout restore_focus render_once ready
  local render_request render_full render_delta finish_result error_count
  local t1 t2 t3 t4 total
  operation_id="$(trace_operation_id "$trace_before" "$trace_after" "$target")"
  # The current production trace names the lifecycle boundaries
  # VALIDATE_TARGET -> SWITCH_CLIENT -> READY. Keep the archive-era phase
  # columns for compatibility, but derive required timing from boundaries
  # that are actually emitted by the implementation.
  prepare="$(trace_phase_us "$trace_before" "$trace_after" "$operation_id" VALIDATE_TARGET)"
  snapshot="$(trace_phase_us "$trace_before" "$trace_after" "$operation_id" SNAPSHOT)"
  move_sidebar="$(trace_phase_us "$trace_before" "$trace_after" "$operation_id" MOVE_SIDEBAR)"
  switch_client="$(trace_phase_us "$trace_before" "$trace_after" "$operation_id" SWITCH_CLIENT)"
  restore_layout="$(trace_phase_us "$trace_before" "$trace_after" "$operation_id" RESTORE_LAYOUT)"
  restore_focus="$(trace_phase_us "$trace_before" "$trace_after" "$operation_id" RESTORE_FOCUS)"
  render_once="$(trace_phase_us "$trace_before" "$trace_after" "$operation_id" RENDER_ONCE)"
  [ -n "$render_once" ] ||
    render_once="$(trace_phase_us "$trace_before" "$trace_after" "$operation_id" RENDER_DELTA)"
  ready="$(trace_phase_us "$trace_before" "$trace_after" "$operation_id" READY)"
  render_request="$(trace_count_range "$trace_before" "$trace_after" 'render.request')"
  render_full="$(trace_count_range "$trace_before" "$trace_after" 'render.full.begin')"
  render_delta="$(trace_count_range "$trace_before" "$trace_after" 'render.delta.begin')"
  finish_result="$(trace_finish_result "$trace_before" "$trace_after" "$operation_id")"
  error_count="$(trace_count_range "$trace_before" "$trace_after" 'switch.abort|session switch failed|returned 1|transition.rollback')"
  t1=0; t2=0; t3=0; t4=0; total=0
  [ -n "$prepare" ] && t1=$((prepare - input_us))
  [ -n "$prepare" ] && [ -n "$switch_client" ] && t2=$((switch_client - prepare))
  [ -n "$switch_client" ] && [ -n "$ready" ] && t3=$((ready - switch_client))
  [ -n "$ready" ] && total=$((ready - input_us))
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$iteration" "$target" "${operation_id:-unknown}" "$input_us" \
    "${prepare:-0}" "${snapshot:-0}" "${move_sidebar:-0}" "${switch_client:-0}" \
    "${restore_layout:-0}" "${restore_focus:-0}" "${render_once:-0}" "${ready:-0}" \
    "$t1" "$t2" "$t3" "$t4" "$total" "$raw_bytes" \
    "$render_request" "$render_full" "$render_delta" "$finish_result" "$error_count" >> "$PHASE_FILE"
}

sample_switch() {
  local iteration="$1" target="$2" sampler_pid start end input_us trace_before trace_after output_before output_after raw_file raw_bytes clear_count home_count
  start="$(now_us)"
  input_us="$(now_us)"
  trace_before="$(wc -l < "$TRACE_FILE" 2>/dev/null || printf '0')"
  output_before="$(wc -c < "$OUTPUT_LOG" | tr -d ' ')"
  (
    while :; do
      visual_sample "$iteration" transition "$(now_us)"
      sleep 0.01
    done
  ) &
  sampler_pid="$!"

  send_keys $'\r'
  if ! wait_until "visual session $target" "wait_session '$target'"; then
    kill "$sampler_pid" 2>/dev/null || true
    wait "$sampler_pid" 2>/dev/null || true
    return 1
  fi
  if ! wait_until "visual sidebar ready $target" sidebar_ready; then
    kill "$sampler_pid" 2>/dev/null || true
    wait "$sampler_pid" 2>/dev/null || true
    return 1
  fi
  if ! wait_until "visual sidebar stable $target" wait_sidebar_stable; then
    kill "$sampler_pid" 2>/dev/null || true
    wait "$sampler_pid" 2>/dev/null || true
    return 1
  fi
  # The tmux/client readiness flag can become visible just before the trace
  # writer flushes READY. Extend the correlation boundary until that marker is
  # observable, otherwise the last transition can be falsely reported as a
  # missing phase row.
  wait_until "trace READY $target" "trace_ready_after '$trace_before'"
  end="$(now_us)"
  trace_after="$(wc -l < "$TRACE_FILE" 2>/dev/null || printf '0')"
  output_after="$(wc -c < "$OUTPUT_LOG" | tr -d ' ')"
  kill "$sampler_pid" 2>/dev/null || true
  wait "$sampler_pid" 2>/dev/null || true
  visual_sample "$iteration" stable "$end"
  raw_file="$RUN_DIR/transition-$iteration.raw"
  raw_bytes=$((output_after - output_before))
  if [ "$raw_bytes" -gt 0 ]; then
    dd if="$OUTPUT_LOG" of="$raw_file" iflag=skip_bytes,count_bytes \
      skip="$output_before" count="$raw_bytes" status=none
  else
    : > "$raw_file"
  fi
  clear_count="$( { LC_ALL=C grep -a -oF $'\033[2J' "$raw_file" 2>/dev/null || true; } | wc -l | tr -d ' ')"
  home_count="$( { LC_ALL=C grep -a -oF $'\033[H' "$raw_file" 2>/dev/null || true; } | wc -l | tr -d ' ')"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$iteration" "$target" "$output_before" "$output_after" "$raw_bytes" \
    "$clear_count/$home_count" >> "$RAW_SUMMARY_FILE"
  record_phase_measurement "$iteration" "$target" "$input_us" "$trace_before" "$trace_after" "$raw_bytes"
  printf 'iteration=%s target=%s transition_us=%s\n' \
    "$iteration" "$target" "$((end - start))"
  printf '%s\t%s\t%s\n' "$iteration" "$target" "$(( (end - start) / 1000 ))" >> "$LATENCY_FILE"
}

setup_interactive_test
for session in "${EXPECTED_SESSIONS[@]}"; do
  create_session "$session"
done

switch_fixture_session visual-a

for session in visual-b visual-c; do
  # Keep the fixture deterministic. The P0 split-cycle tests cover physical
  # split shortcuts; this P1 test focuses on the physical Enter transition
  # and its raw PTY observation boundary.
  switch_fixture_session "$session"
  work_pane="$(tmuxc list-panes -t "=$session:" -F '#{pane_id}|#{pane_title}' |
    awk -F'|' '$2 != "dotfiles-session-sidebar" {print $1; exit}')"
  tmuxc split-window -d -t "$work_pane" -h -b -l 35 'sleep 300'
  tmuxc split-window -d -t "$work_pane" -v -b -l 8 'sleep 300'
  if [ "$session" = visual-c ]; then
    tmuxc split-window -d -t "$work_pane" -h -b -l 20 'sleep 300'
  fi
  expected_panes=3
  [ "$session" = visual-c ] && expected_panes=4
  wait_until "visual topology $session" "pane_count_at_least '$session' '$expected_panes'"
  wait_until "visual sidebar stable $session" wait_sidebar_stable
  EXPECTED_SIDEBAR_GEOMETRY["$session"]="$(sidebar_geometry_for_session "$session")"
  EXPECTED_PANE_SIGNATURE["$session"]="$(visual_signature "$session")"
done

switch_fixture_session visual-a
wait_until "visual sidebar stable before transitions" wait_sidebar_stable
EXPECTED_SIDEBAR_GEOMETRY[visual-a]="$(sidebar_geometry_for_session visual-a)"
EXPECTED_PANE_SIGNATURE[visual-a]="$(visual_signature visual-a)"

: > "$MEASURE_FILE"
: > "$LATENCY_FILE"
: > "$RAW_SUMMARY_FILE"
: > "$PHASE_FILE"
printf '%b\n' 'iteration\ttarget\toperation_id\tinput_us\tprepare_us\tsnapshot_us\tmove_sidebar_us\tswitch_client_us\trestore_layout_us\trestore_focus_us\trender_once_us\tready_us\tt1_us\tt2_us\tt3_us\tt4_us\ttotal_us\traw_bytes\trender_request_count\trender_full_count\trender_delta_count\tfinish_result\terror_marker_count' > "$PHASE_FILE"

TARGET_SEQUENCE=(visual-b visual-c visual-a)
for iteration in $(seq 1 "$EXPECTED_TRANSITIONS"); do
  focus_sidebar
  target="${TARGET_SEQUENCE[$(( (iteration - 1) % ${#TARGET_SEQUENCE[@]} ))]}"
  move_selection_to "$target"
  sleep 0.02
  sample_switch "$iteration" "$target"
done

sample_count="$(awk 'END {print NR + 0}' "$MEASURE_FILE")"
blank_count="$(awk -F '\t' '$5 == "blank" {n++} END {print n + 0}' "$MEASURE_FILE")"
partial_count="$(awk -F '\t' '$5 == "partial" {n++} END {print n + 0}' "$MEASURE_FILE")"
complete_count="$(awk -F '\t' '$5 == "complete" {n++} END {print n + 0}' "$MEASURE_FILE")"
sidebar_identity_count="$(cut -f6 "$MEASURE_FILE" | sort -u | wc -l | tr -d ' ')"
geometry_mismatch_count="$(awk -F '\t' '$9 != "true" {n++} END {print n + 0}' "$MEASURE_FILE")"
pane_mismatch_count="$(awk -F '\t' '$13 != "true" {n++} END {print n + 0}' "$MEASURE_FILE")"
stable_geometry_mismatch_count="$(awk -F '\t' '$2 == "stable" && $9 != "true" {n++} END {print n + 0}' "$MEASURE_FILE")"
stable_pane_mismatch_count="$(awk -F '\t' '$2 == "stable" && $13 != "true" {n++} END {print n + 0}' "$MEASURE_FILE")"
latency_count="$(awk 'END {print NR + 0}' "$LATENCY_FILE")"
latency_p50="$(sort -n -k3,3 "$LATENCY_FILE" | awk -v n="$latency_count" 'n {v[NR]=$3} END {print v[int((n + 1) / 2)] + 0}')"
latency_p95="$(sort -n -k3,3 "$LATENCY_FILE" | awk -v n="$latency_count" 'n {v[NR]=$3} END {i=int(n * 0.95 + 0.999); if (i < 1) i=1; print v[i] + 0}')"
missing_phase_count="$(awk -F '\t' 'NR > 1 && ($3 == "unknown" || $12 == 0 || $17 == 0 || (($20 + $21) < 1 && $18 == 0) || $22 != "success") {n++} END {print n + 0}' "$PHASE_FILE")"
full_render_count="$(awk -F '\t' 'NR > 1 {n += $20} END {print n + 0}' "$PHASE_FILE")"
delta_render_count="$(awk -F '\t' 'NR > 1 {n += $21} END {print n + 0}' "$PHASE_FILE")"
error_marker_count="$(awk -F '\t' 'NR > 1 {n += $23} END {print n + 0}' "$PHASE_FILE")"

echo "measurement_file=$MEASURE_FILE"
echo "samples=$sample_count blank_frames=$blank_count partial_frames=$partial_count complete_frames=$complete_count"
echo "sidebar_identities=$sidebar_identity_count geometry_mismatches=$geometry_mismatch_count stable_geometry_mismatches=$stable_geometry_mismatch_count pane_mismatches=$pane_mismatch_count stable_pane_mismatches=$stable_pane_mismatch_count"
echo "latency_samples=$latency_count latency_p50_ms=$latency_p50 latency_p95_ms=$latency_p95"
echo "raw_summary=$RAW_SUMMARY_FILE"
echo "phase_summary=$PHASE_FILE missing_or_ambiguous_rows=$missing_phase_count render_full=$full_render_count render_delta=$delta_render_count error_markers=$error_marker_count metrics=$TMUX_SESSION_LAUNCHER_METRICS_FILE"
echo "phase_p50_us t1=$(phase_percentile_us 13 50) t2=$(phase_percentile_us 14 50) t3=$(phase_percentile_us 15 50) t4=$(phase_percentile_us 16 50) total=$(phase_percentile_us 17 50)"
echo "phase_p95_us t1=$(phase_percentile_us 13 95) t2=$(phase_percentile_us 14 95) t3=$(phase_percentile_us 15 95) t4=$(phase_percentile_us 16 95) total=$(phase_percentile_us 17 95)"

if [ "$sidebar_identity_count" -ne "${#EXPECTED_SESSIONS[@]}" ] || [ "$stable_geometry_mismatch_count" -gt 0 ] ||
   [ "$stable_pane_mismatch_count" -gt 0 ] || [ "$missing_phase_count" -ne 0 ]; then
  echo "RED: sidebar identity cardinality, target geometry, pane signature, or phase metadata did not match expected values" >&2
  echo "invalid_sample_rows(iteration phase timestamp session layer sidebar_id geometry expected_geometry geometry_match layout pane_signature expected_pane_signature pane_match completeness output_offset):"
  awk -F '\t' '$2 == "stable" && ($9 != "true" || $13 != "true") {print}' "$MEASURE_FILE"
  exit 1
fi

if [ "$blank_count" -gt 0 ] || [ "$partial_count" -gt 0 ] ||
   [ "$geometry_mismatch_count" -gt 0 ] || [ "$pane_mismatch_count" -gt 0 ]; then
  echo "WARN: transition sampling observed intermediate blank/partial or manifest-mismatch snapshots; correlate raw PTY artifacts before treating this as final-state failure" >&2
else
  echo "PASS: pane-buffer sampling remained complete"
fi
echo "PASS: window-local sidebar identities and target-specific geometry matched expected metadata"
