#!/usr/bin/env bash
set -euo pipefail

# Correlates render_full/debug events and layout transition trace events with
# the raw PTY output emitted during the same physical session switch.
# Production launcher/controller code is intentionally unchanged.

SCENARIO_NAME=switch-render-phase
export SCENARIO_NAME
export TMUX_SESSION_LAUNCHER_TRACE=1
export TMUX_SESSION_LAUNCHER_DEBUG=1
source "$(dirname -- "$BASH_SOURCE")/test-interactive-common.sh"

EXPECTED="${PHASE_TRANSITIONS:-10}"
TIMELINE_FILE="$RUN_DIR/transition-timeline.tsv"
SUMMARY_FILE="$RUN_DIR/phase-summary.tsv"
TRACE_FILE="$RUN_DIR/trace.log"
DEBUG_FILE="$RUN_DIR/debug.log"

file_lines() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }
file_bytes() { [ -f "$1" ] && wc -c < "$1" | tr -d ' ' || echo 0; }

count_range() {
  local file="$1" before="$2" after="$3" pattern="$4"
  [ "$after" -gt "$before" ] || {
    echo 0
    return 0
  }
  sed -n "$((before + 1)),$after p" "$file" 2>/dev/null |
    grep -c "$pattern" 2>/dev/null || true
}

sample_state() {
  local iteration="$1" phase="$2"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$iteration" "$phase" "$(date +%s%N)" \
    "$(file_lines "$TRACE_FILE")" "$(file_lines "$DEBUG_FILE")" \
    "$(file_bytes "$OUTPUT_LOG")" "$(client_session)" >> "$TIMELINE_FILE"
}

summarize_transition() {
  local iteration="$1" target="$2" trace_before="$3" trace_after="$4"
  local debug_before="$5" debug_after="$6" output_before="$7" output_after="$8"
  local raw_file="$RUN_DIR/transition-$iteration.raw" output_count
  output_count=$((output_after - output_before))
  if [ "$output_count" -gt 0 ]; then
    dd if="$OUTPUT_LOG" of="$raw_file" iflag=skip_bytes,count_bytes \
      skip="$output_before" count="$output_count" status=none
  else
    : > "$raw_file"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$iteration" "$target" "$trace_before" "$trace_after" \
    "$debug_before" "$debug_after" "$output_before" "$output_after" \
    "$(count_range "$TRACE_FILE" "$trace_before" "$trace_after" 'switch.begin')" \
    "$(count_range "$TRACE_FILE" "$trace_before" "$trace_after" 'sidebar.layout.restore.begin')" \
    "$(count_range "$TRACE_FILE" "$trace_before" "$trace_after" 'switch.force-refresh.final.begin')" \
    "$(count_range "$DEBUG_FILE" "$debug_before" "$debug_after" 'render_full start')" \
    "$output_count" >> "$SUMMARY_FILE"
}

setup_interactive_test
create_session phase-a
create_session phase-b
select_session_by_name phase-a

: > "$TRACE_FILE"
: > "$DEBUG_FILE"
: > "$TIMELINE_FILE"
: > "$SUMMARY_FILE"

completed=0
for iteration in $(seq 1 "$EXPECTED"); do
  focus_sidebar
  if [ $((iteration % 2)) -eq 1 ]; then
    send_keys $'\033[B'
    target=phase-b
  else
    send_keys $'\033[A'
    target=phase-a
  fi
  sleep 0.02

  trace_before="$(file_lines "$TRACE_FILE")"
  debug_before="$(file_lines "$DEBUG_FILE")"
  output_before="$(file_bytes "$OUTPUT_LOG")"
  (
    while :; do
      sample_state "$iteration" transition
      sleep 0.01
    done
  ) &
  sampler_pid="$!"

  send_keys $'\r'
  if ! wait_until "render phase session $target" "wait_session '$target'"; then
    kill "$sampler_pid" 2>/dev/null || true
    wait "$sampler_pid" 2>/dev/null || true
    break
  fi
  if ! wait_until "render phase sidebar ready $target" sidebar_ready; then
    kill "$sampler_pid" 2>/dev/null || true
    wait "$sampler_pid" 2>/dev/null || true
    break
  fi
  sleep 0.1
  kill "$sampler_pid" 2>/dev/null || true
  wait "$sampler_pid" 2>/dev/null || true
  trace_after="$(file_lines "$TRACE_FILE")"
  debug_after="$(file_lines "$DEBUG_FILE")"
  output_after="$(file_bytes "$OUTPUT_LOG")"
  sample_state "$iteration" stable
  summarize_transition "$iteration" "$target" "$trace_before" "$trace_after" \
    "$debug_before" "$debug_after" "$output_before" "$output_after"
  completed=$((completed + 1))
done

{
  echo "iteration target trace_before trace_after debug_before debug_after output_before output_after switch_begin layout_restore force_refresh render_full output_bytes"
  cat "$SUMMARY_FILE"
} > "$RUN_DIR/phase-summary-with-header.tsv"
mv "$RUN_DIR/phase-summary-with-header.tsv" "$SUMMARY_FILE"

render_total="$(awk -F '\t' 'NR > 1 {n += $12} END {print n + 0}' "$SUMMARY_FILE")"
layout_total="$(awk -F '\t' 'NR > 1 {n += $10} END {print n + 0}' "$SUMMARY_FILE")"
refresh_total="$(awk -F '\t' 'NR > 1 {n += $11} END {print n + 0}' "$SUMMARY_FILE")"
output_total="$(awk -F '\t' 'NR > 1 {n += $13} END {print n + 0}' "$SUMMARY_FILE")"
unclassified="$(awk -F '\t' 'NR > 1 && $12 == 0 {n++} END {print n + 0}' "$SUMMARY_FILE")"

echo "summary=$SUMMARY_FILE"
echo "completed=$completed requested=$EXPECTED"
echo "render_full=$render_total layout_restore=$layout_total force_refresh=$refresh_total"
echo "raw_output_bytes=$output_total unclassified_render_iterations=$unclassified"

if [ "$completed" -ne "$EXPECTED" ] || [ "$unclassified" -ne 0 ]; then
  KEEP_RUN_DIR=true
  echo "RED: render/layout/raw-output correlation is incomplete" >&2
  echo "artifacts=$RUN_DIR" >&2
  exit 1
fi

echo "PASS: render_full and layout/raw-output transition phases are correlated"
