#!/usr/bin/env bash
set -euo pipefail

# Strict measurement scenario for the user-visible contract:
# the sidebar remains fixed while only the selected session's work panes
# change.  This test does not modify production behavior; it records the
# intermediate pane/capture state and fails when the sidebar itself moves or
# is redrawn during a physical PTY Enter transition.

SCENARIO_NAME=sidebar-fixed-work-switch
export SCENARIO_NAME
export TMUX_SESSION_LAUNCHER_TRACE=1
export TMUX_SESSION_LAUNCHER_DEBUG=1
source "$(dirname -- "$BASH_SOURCE")/test-interactive-common.sh"

EXPECTED_SESSIONS=(fixed-a fixed-b fixed-c)
EXPECTED_TRANSITIONS="${SIDEBAR_FIXED_TRANSITIONS:-10}"
SAMPLE_INTERVAL="${SIDEBAR_FIXED_SAMPLE_INTERVAL:-0.02}"
SAMPLE_FILE="$RUN_DIR/sidebar-fixed-samples.tsv"
SUMMARY_FILE="$RUN_DIR/sidebar-fixed-summary.tsv"
METRICS_FILE="$RUN_DIR/sidebar-fixed-metrics.log"
TIMING_FILE="$RUN_DIR/sidebar-fixed-timing.tsv"
export TMUX_SESSION_LAUNCHER_METRICS_FILE="$METRICS_FILE"
export TMUX_SESSION_LAUNCHER_METRICS_RUN_ID="sidebar-fixed-$$"
export TMUX_SESSION_LAUNCHER_METRICS_FLUSH_SECONDS=0
declare -A EXPECTED_WORK_SIGNATURE=()
SIDEBAR_BASELINE_ID=""
SIDEBAR_BASELINE_GEOMETRY=""
SIDEBAR_BASELINE_HASH=""

file_bytes() { wc -c < "$1" | tr -d ' '; }

metrics_switch_count() {
  [ -f "$METRICS_FILE" ] || { printf '0\n'; return 0; }
  awk '$0 ~ /op=switch/ && $0 ~ /phase=complete/ {n++} END {print n+0}' "$METRICS_FILE"
}

write_timing_summary() {
  local line field value
  printf '%b\n' 'operation_id\ttarget\tsidebar_move_us\tforce_refresh_us\tclient_lookup_us\tclient_switch_us\tfinal_force_refresh_us\ttotal_us' > "$TIMING_FILE"
  [ -f "$METRICS_FILE" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    [ "$(printf '%s\n' "$line" | grep -c 'op=switch' || true)" -eq 1 ] || continue
    operation_id="$(printf '%s\n' "$line" | sed -n 's/.*operation_id=\([^ ]*\).*/\1/p')"
    target="$(printf '%s\n' "$line" | sed -n 's/.*session=\([^ ]*\).*/\1/p')"
    sidebar_move=0; force_refresh=0; client_lookup=0; client_switch=0
    final_force_refresh=0; total=0
    for field in sidebar_move_us force_refresh_us client_lookup_us client_switch_us final_force_refresh_us total_us; do
      value="$(printf '%s\n' "$line" | sed -n "s/.*$field=\([0-9]*\).*/\1/p")"
      eval "$field=\${value:-0}"
    done
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$operation_id" "$target" "$sidebar_move_us" "$force_refresh_us" \
      "$client_lookup_us" "$client_switch_us" "$final_force_refresh_us" "$total_us" >> "$TIMING_FILE"
  done < "$METRICS_FILE"
}

sidebar_geometry() {
  local id="${1:-$(sidebar_pane_id)}"
  tmuxc list-panes -a -F '#{pane_id}|#{pane_left}|#{pane_top}|#{pane_width}|#{pane_height}' |
    awk -F'|' -v id="$id" '$1 == id {print $2 "|" $3 "|" $4 "|" $5; exit}'
}

sidebar_fixed_capture() {
  local capture name
  # Selection/current-session markers, status, and age are expected to change
  # when the client moves between sessions. Preserve each known row identity
  # and keep header/footer/row structure strict.
  capture="$(tmuxc capture-pane -p -t "$SIDEBAR_TARGET" 2>/dev/null || true)"
  for name in "${EXPECTED_SESSIONS[@]}"; do
    capture="$(printf '%s\n' "$capture" | sed -E "s/^.*${name}.*$/session:${name}/")"
  done
  printf '%s\n' "$capture" |
    sed -E \
      -e 's/^[[:space:]]*[>*][[:space:]]*//' \
      -e 's/[[:space:]][0-9]+:[0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]*$//' |
    cksum | awk '{print $1}'
}

work_signature() {
  local session="$1"
  tmuxc list-panes -t "=$session:" -F '#{pane_id}|#{pane_title}|#{pane_current_path}|#{pane_current_command}|#{pane_left}|#{pane_top}|#{pane_width}|#{pane_height}' |
    awk -F'|' '$2 != "dotfiles-session-sidebar"' | sort | cksum | awk '{print $1}'
}

sidebar_frame() {
  local capture title_count footer_count session_count name
  capture="$(tmuxc capture-pane -p -t "$SIDEBAR_TARGET" 2>/dev/null || true)"
  title_count="$(printf '%s\n' "$capture" | grep -Ec '^sessions *$' || true)"
  footer_count="$(printf '%s\n' "$capture" | grep -Ec 'j/k .*Enter.*c/r/d.*o.*q' || true)"
  session_count=0
  for name in "${EXPECTED_SESSIONS[@]}"; do
    printf '%s\n' "$capture" | grep -Fq "$name" && session_count=$((session_count + 1))
  done
  if [ -z "$capture" ]; then
    printf 'blank'
  elif [ "$title_count" -eq 1 ] && [ "$footer_count" -eq 1 ] &&
       [ "$session_count" -eq "${#EXPECTED_SESSIONS[@]}" ]; then
    printf 'complete'
  else
    printf 'partial'
  fi
}

sample_sidebar() {
  local iteration="$1" phase="$2" target="$3" id geometry hash frame session now output
  now="$(date +%s%N)"
  session="$(client_session)"
  id="$(sidebar_pane_id)"
  geometry="$(sidebar_geometry "$id")"
  hash="$(sidebar_fixed_capture)"
  frame="$(sidebar_frame)"
  output="$(file_bytes "$OUTPUT_LOG")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$iteration" "$phase" "$now" "$target" "$session" "$id" \
    "$geometry" "$hash" "$frame" "$output" \
    "$(work_signature "$session")" "$(tmuxc display-message -p -t "$CLIENT_TTY" '#{window_layout}')" \
    >> "$SAMPLE_FILE"
}

move_selection_to() {
  local target="$1" row current delta key count i
  row="$(sidebar_row_for "$target")"
  [ -n "$row" ] || return 1
  current="$(tmuxc capture-pane -p -t "$SIDEBAR_TARGET" | nl -ba |
    awk '$0 ~ />[ *]/ {print $1; exit}')"
  [ -n "$current" ] || return 1
  delta=$((row - current))
  [ "$delta" -eq 0 ] && return 0
  key=$'\033[B'
  [ "$delta" -lt 0 ] && key=$'\033[A'
  count="$delta"
  [ "$count" -lt 0 ] && count=$((-count))
  for i in $(seq 1 "$count"); do send_keys "$key"; done
}

setup_interactive_test
for session in "${EXPECTED_SESSIONS[@]}"; do create_session "$session"; done

# Give every session the same sidebar geometry but deliberately different work
# topology. The differing work signatures must not be mistaken for sidebar
# instability.
for session in "${EXPECTED_SESSIONS[@]}"; do
  select_session_by_name "$session"
  work_pane="$(tmuxc list-panes -t "=$session:" -F '#{pane_id}|#{pane_title}' |
    awk -F'|' '$2 != "dotfiles-session-sidebar" {print $1; exit}')"
  tmuxc split-window -d -t "$work_pane" -h -b -l 35 'sleep 300'
  if [ "$session" != fixed-a ]; then
    tmuxc split-window -d -t "$work_pane" -v -b -l 8 'sleep 300'
  fi
  if [ "$session" = fixed-c ]; then
    tmuxc split-window -d -t "$work_pane" -h -b -l 20 'sleep 300'
  fi
  expected_count=2
  [ "$session" != fixed-a ] && expected_count=3
  [ "$session" = fixed-c ] && expected_count=4
  wait_until "fixed topology $session" "pane_count_at_least '$session' '$expected_count'"
  wait_until "fixed sidebar stable $session" wait_sidebar_stable
  EXPECTED_WORK_SIGNATURE["$session"]="$(work_signature "$session")"
done

select_session_by_name fixed-a
wait_until "fixed sidebar stable baseline" wait_sidebar_stable
SIDEBAR_BASELINE_ID="$(sidebar_pane_id)"
SIDEBAR_BASELINE_GEOMETRY="$(sidebar_geometry "$SIDEBAR_BASELINE_ID")"
SIDEBAR_BASELINE_HASH="$(sidebar_fixed_capture)"

: > "$SAMPLE_FILE"
: > "$SUMMARY_FILE"
: > "$METRICS_FILE"
printf '%b\n' 'iteration\tphase\ttimestamp_ns\ttarget\tclient_session\tsidebar_id\tsidebar_geometry\tsidebar_hash\tframe\toutput_bytes\twork_signature\twindow_layout' > "$SAMPLE_FILE"
printf '%b\n' 'iteration\ttarget\tsamples\tsidebar_id_changes\tsidebar_geometry_changes\tsidebar_hash_changes\tblank_frames\tpartial_frames\twork_mismatches\tfull_render_calls\ttransition_ms\traw_bytes' > "$SUMMARY_FILE"

TARGET_SEQUENCE=(fixed-b fixed-c fixed-a)
for iteration in $(seq 1 "$EXPECTED_TRANSITIONS"); do
  focus_sidebar
  target="${TARGET_SEQUENCE[$(( (iteration - 1) % ${#TARGET_SEQUENCE[@]} ))]}"
  move_selection_to "$target"
  sleep 0.02
  before="$(file_bytes "$OUTPUT_LOG")"
  trace_before="$(wc -l < "$TRACE_FILE" 2>/dev/null || printf '0')"
  start_ns="$(date +%s%N)"
  (
    while :; do
      sample_sidebar "$iteration" transition "$target"
      sleep "$SAMPLE_INTERVAL"
    done
  ) &
  sampler_pid="$!"
  send_keys $'\r'
  if ! wait_until "fixed session $target" "wait_session '$target'" ||
     ! wait_until "fixed sidebar ready $target" sidebar_ready ||
     ! wait_until "fixed sidebar stable $target" wait_sidebar_stable; then
    kill "$sampler_pid" 2>/dev/null || true
    wait "$sampler_pid" 2>/dev/null || true
    KEEP_RUN_DIR=true
    echo "RED: transition $iteration failed; artifacts=$RUN_DIR" >&2
    exit 1
  fi
  end_ns="$(date +%s%N)"
  trace_after="$(wc -l < "$TRACE_FILE" 2>/dev/null || printf '0')"
  kill "$sampler_pid" 2>/dev/null || true
  wait "$sampler_pid" 2>/dev/null || true
  sample_sidebar "$iteration" stable "$target"

  rows="$RUN_DIR/iteration-$iteration.tsv"
  awk -F '\t' -v i="$iteration" 'NR > 1 && $1 == i' "$SAMPLE_FILE" > "$rows"
  samples="$(wc -l < "$rows" | tr -d ' ')"
  id_changes="$(awk -F '\t' -v id="$SIDEBAR_BASELINE_ID" '$6 != id {n++} END {print n+0}' "$rows")"
  geometry_changes="$(awk -F '\t' -v g="$SIDEBAR_BASELINE_GEOMETRY" '$7 != g {n++} END {print n+0}' "$rows")"
  hash_changes="$(awk -F '\t' -v h="$SIDEBAR_BASELINE_HASH" '$8 != h {n++} END {print n+0}' "$rows")"
  blank_frames="$(awk -F '\t' '$9 == "blank" {n++} END {print n+0}' "$rows")"
  partial_frames="$(awk -F '\t' '$9 == "partial" {n++} END {print n+0}' "$rows")"
  # During the transition the client may still expose the source work layout;
  # only the stable target sample is a final-state assertion. Intermediate
  # work changes are expected and are represented by the raw/capture samples.
  work_mismatches="$(awk -F '\t' -v expected="${EXPECTED_WORK_SIGNATURE[$target]}" '$2 == "stable" && $11 != expected {n++} END {print n+0}' "$rows")"
  full_render_calls="$(sed -n "$((trace_before + 1)),$trace_after p" "$TRACE_FILE" 2>/dev/null |
    grep -c 'render.full.begin' 2>/dev/null || true)"
  raw_bytes=$(( $(file_bytes "$OUTPUT_LOG") - before ))
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$iteration" "$target" "$samples" "$id_changes" "$geometry_changes" \
    "$hash_changes" "$blank_frames" "$partial_frames" "$work_mismatches" \
    "$full_render_calls" "$(( (end_ns - start_ns) / 1000000 ))" "$raw_bytes" >> "$SUMMARY_FILE"
done

wait_until "switch metrics" "[ \"\$(metrics_switch_count)\" -ge \"$EXPECTED_TRANSITIONS\" ]"
write_timing_summary

transition_count="$(awk 'NR > 1 {n++} END {print n+0}' "$SUMMARY_FILE")"
id_changes="$(awk -F '\t' 'NR > 1 {n += $4} END {print n+0}' "$SUMMARY_FILE")"
geometry_changes="$(awk -F '\t' 'NR > 1 {n += $5} END {print n+0}' "$SUMMARY_FILE")"
hash_changes="$(awk -F '\t' 'NR > 1 {n += $6} END {print n+0}' "$SUMMARY_FILE")"
blank_frames="$(awk -F '\t' 'NR > 1 {n += $7} END {print n+0}' "$SUMMARY_FILE")"
partial_frames="$(awk -F '\t' 'NR > 1 {n += $8} END {print n+0}' "$SUMMARY_FILE")"
work_mismatches="$(awk -F '\t' 'NR > 1 {n += $9} END {print n+0}' "$SUMMARY_FILE")"
full_render_calls="$(awk -F '\t' 'NR > 1 {n += $10} END {print n+0}' "$SUMMARY_FILE")"
latency_p50="$(awk -F '\t' 'NR > 1 {print $11}' "$SUMMARY_FILE" | sort -n |
  awk '{v[NR]=$1} END {i=int((NR + 1) / 2); if (i < 1) i=1; print v[i]+0}')"
latency_p95="$(awk -F '\t' 'NR > 1 {print $11}' "$SUMMARY_FILE" | sort -n | awk '{v[NR]=$1} END {i=int(NR * 0.95 + 0.999); if (i < 1) i=1; print v[i]+0}')"
raw_bytes="$(awk -F '\t' 'NR > 1 {n += $12} END {print n+0}' "$SUMMARY_FILE")"

echo "summary=$SUMMARY_FILE"
echo "metrics=$METRICS_FILE timing=$TIMING_FILE"
echo "transitions=$transition_count sidebar_id_changes=$id_changes sidebar_geometry_changes=$geometry_changes"
echo "sidebar_hash_changes=$hash_changes blank_frames=$blank_frames partial_frames=$partial_frames"
echo "work_signature_mismatches=$work_mismatches full_render_calls=$full_render_calls raw_bytes=$raw_bytes"
echo "latency_p50_ms=${latency_p50:-0} latency_p95_ms=${latency_p95:-0}"
echo "timing_p95_us sidebar_move=$(awk -F '\t' 'NR > 1 {print $3}' "$TIMING_FILE" | sort -n | tail -1) client_switch=$(awk -F '\t' 'NR > 1 {print $6}' "$TIMING_FILE" | sort -n | tail -1) total=$(awk -F '\t' 'NR > 1 {print $8}' "$TIMING_FILE" | sort -n | tail -1)"

if [ "$transition_count" -ne "$EXPECTED_TRANSITIONS" ] || [ "$id_changes" -ne 0 ] ||
   [ "$geometry_changes" -ne 0 ] || [ "$hash_changes" -ne 0 ] ||
   [ "$blank_frames" -ne 0 ] || [ "$partial_frames" -ne 0 ] ||
   [ "$work_mismatches" -ne 0 ] || [ "$full_render_calls" -ne 0 ]; then
  KEEP_RUN_DIR=true
  echo "RED: sidebar was not strictly fixed during one or more work transitions" >&2
  echo "artifacts=$RUN_DIR" >&2
  exit 1
fi

echo "PASS: sidebar remained fixed and only target work topology changed"
