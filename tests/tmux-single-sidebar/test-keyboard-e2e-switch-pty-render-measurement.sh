#!/usr/bin/env bash
set -euo pipefail

# The pane-buffer sampler cannot observe terminal repaint order. This test
# measures the raw bytes emitted by the attached PTY client instead, which is
# closer to what a user sees: clear-screen, cursor-home, and redraw sequences
# during each physical arrow+Enter session switch.

SCENARIO_NAME=switch-pty-render-measurement
export SCENARIO_NAME
source "$(dirname -- "$BASH_SOURCE")/test-interactive-common.sh"

MEASURE_FILE="$RUN_DIR/pty-render-samples.tsv"
EXPECTED_SESSIONS=(pty-a pty-b)
EXPECTED_TRANSITIONS="${PTY_RENDER_TRANSITIONS:-20}"

output_bytes() {
  wc -c < "$OUTPUT_LOG" | tr -d ' '
}

count_sequence() {
  local file="$1" sequence="$2"
  LC_ALL=C grep -a -oF "$sequence" "$file" 2>/dev/null | wc -l | tr -d ' '
}

capture_transition_output() {
  local iteration="$1" start_offset="$2" end_offset="$3" output_file="$4" count
  count=$((end_offset - start_offset))
  [ "$count" -gt 0 ] || : > "$output_file"
  if [ "$count" -gt 0 ]; then
    dd if="$OUTPUT_LOG" of="$output_file" iflag=skip_bytes,count_bytes \
      skip="$start_offset" count="$count" status=none
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$iteration" "$start_offset" "$end_offset" "$count" \
    "$(count_sequence "$output_file" $'\033[2J')" \
    "$(count_sequence "$output_file" $'\033[H')" \
    "$(count_sequence "$output_file" $'\033[1;1H')" >> "$MEASURE_FILE"
}

setup_interactive_test
create_session pty-a
create_session pty-b
select_session_by_name pty-a
: > "$MEASURE_FILE"

completed=true
for iteration in $(seq 1 "$EXPECTED_TRANSITIONS"); do
  focus_sidebar
  if [ $((iteration % 2)) -eq 1 ]; then
    send_keys $'\033[B'
    target=pty-b
  else
    send_keys $'\033[A'
    target=pty-a
  fi
  sleep 0.02
  start_offset="$(output_bytes)"
  send_keys $'\r'
  if ! wait_until "PTY render session $target" "wait_session '$target'"; then
    completed=false
    break
  fi
  if ! wait_until "PTY render sidebar ready $target" sidebar_ready; then
    completed=false
    break
  fi
  sleep 0.2
  end_offset="$(output_bytes)"
  capture_transition_output "$iteration" "$start_offset" "$end_offset" \
    "$RUN_DIR/transition-$iteration.raw"
done

sample_count="$(awk 'END {print NR + 0}' "$MEASURE_FILE")"
clear_total="$(awk -F '\t' '{n += $5} END {print n + 0}' "$MEASURE_FILE")"
home_total="$(awk -F '\t' '{n += $6} END {print n + 0}' "$MEASURE_FILE")"
home11_total="$(awk -F '\t' '{n += $7} END {print n + 0}' "$MEASURE_FILE")"
clear_every="$(awk -F '\t' '$5 > 0 {n++} END {print n + 0}' "$MEASURE_FILE")"

echo "measurement_file=$MEASURE_FILE"
echo "transitions=$sample_count clear_screen_total=$clear_total"
echo "cursor_home_total=$home_total cursor_1_1_home_total=$home11_total"
echo "transitions_with_clear_screen=$clear_every"
echo "completed_all_requested_transitions=$completed"

if [ "$completed" != true ] || [ "$sample_count" -ne "$EXPECTED_TRANSITIONS" ]; then
  echo "RED: not all requested PTY transitions produced measurable output" >&2
  KEEP_RUN_DIR=true
  echo "artifacts=$RUN_DIR" >&2
  exit 1
fi

if [ "$clear_every" -eq "$sample_count" ]; then
  echo "MEASURED: every transition emitted a full-screen clear sequence"
else
  echo "MEASURED: full-screen clear sequence was not present in every transition"
fi

echo "raw transition artifacts are available under $RUN_DIR until cleanup"
echo "PASS: raw PTY render measurement completed"
