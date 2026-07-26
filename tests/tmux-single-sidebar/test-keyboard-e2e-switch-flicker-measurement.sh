#!/usr/bin/env bash
set -euo pipefail

# Measurement-only regression scenario for the perceived sidebar flicker:
# create several sessions, move the TUI selection with physical arrow bytes,
# press Enter, and sample the same sidebar pane while the session transition
# is in flight. This test intentionally does not change production behavior.

SCENARIO_NAME=switch-flicker-measurement
export SCENARIO_NAME
source "$(dirname -- "$BASH_SOURCE")/test-interactive-common.sh"

MEASURE_FILE="$RUN_DIR/transition-samples.tsv"
EXPECTED_SESSIONS=(flicker-a flicker-b flicker-c flicker-d)

capture_sample() {
  local iteration="$1" phase="$2" now="$3" capture session_count selected_count
  capture="$(tmuxc capture-pane -p -t "$SIDEBAR_TARGET" 2>/dev/null || true)"
  session_count=0
  for session in "${EXPECTED_SESSIONS[@]}"; do
    printf '%s\n' "$capture" | grep -Fq "$session" && session_count=$((session_count + 1))
  done
  selected_count="$(printf '%s\n' "$capture" | grep -Ec '^> *\*? ' || true)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$iteration" "$phase" "$now" "$(sidebar_pane_id)" \
    "$(printf '%s\n' "$capture" | grep -Fc sessions || true)" \
    "$session_count" "$selected_count" >> "$MEASURE_FILE"
}

sample_until_stable() {
  local iteration="$1" target="$2" sampler_pid start end
  start="$(date +%s%N)"
  (
    while :; do
      capture_sample "$iteration" transition "$(date +%s%3N)"
      sleep 0.01
    done
  ) &
  sampler_pid="$!"

  send_keys $'\r'
  wait_until "session $target" "wait_session '$target'"
  wait_until "sidebar ready after session $target" sidebar_ready
  end="$(date +%s%N)"
  kill "$sampler_pid" 2>/dev/null || true
  wait "$sampler_pid" 2>/dev/null || true
  capture_sample "$iteration" stable "$end"
  printf 'iteration=%s target=%s transition_ns=%s\n' \
    "$iteration" "$target" "$((end - start))"
}

setup_interactive_test
for session in "${EXPECTED_SESSIONS[@]}"; do
  create_session "$session"
done

select_session_by_name flicker-a
: > "$MEASURE_FILE"

for iteration in $(seq 1 8); do
  focus_sidebar
  if [ $((iteration % 2)) -eq 1 ]; then
    send_keys $'\033[B'
    target=flicker-b
  else
    send_keys $'\033[A'
    target=flicker-a
  fi
  sleep 0.02
  sample_until_stable "$iteration" "$target"
done

sample_count="$(awk 'END {print NR + 0}' "$MEASURE_FILE")"
invalid_count="$(awk -F '\t' '$5 != 1 || $6 != 4 || $7 != 1 {n++} END {print n + 0}' "$MEASURE_FILE")"
identity_count="$(cut -f4 "$MEASURE_FILE" | sort -u | wc -l | tr -d ' ')"
transition_count="$(grep -c $'\ttransition\t' "$MEASURE_FILE" || true)"

echo "measurement_file=$MEASURE_FILE"
echo "samples=$sample_count transition_samples=$transition_count invalid_frames=$invalid_count sidebar_identities=$identity_count"

if [ "$invalid_count" -gt 0 ] || [ "$identity_count" -ne 1 ]; then
  echo "invalid_sample_rows(iteration phase timestamp sidebar_id title_count session_count selected_count):"
  awk -F '\t' '$5 != 1 || $6 != 4 || $7 != 1 {print}' "$MEASURE_FILE"
  echo "RED: sidebar transition produced inconsistent sampled frames or pane identity changes" >&2
  exit 1
fi

echo "PASS: no sampled sidebar frame inconsistency detected"
