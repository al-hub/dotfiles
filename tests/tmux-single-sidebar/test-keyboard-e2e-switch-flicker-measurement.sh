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
PHYSICAL_INPUT_FALLBACKS=0

# This measurement needs the user-selected '*' row, while the shared E2E
# helper intentionally retains its historical current-row semantics.
sidebar_selected_name() {
  tmuxc capture-pane -p -t "$(sidebar_pane_id)" 2>/dev/null |
    sed $'s/\033\\[[0-9;]*m//g' |
    awk '
      $1 == ">*" { selected=$2; current=$2; next }
      $1 == "*" { selected=$2; next }
      $1 == ">" { if ($2 == "*") selected=$3; else current=$2; next }
      END { if (selected != "") print selected; else print current }
    '
}

capture_sample() {
  local iteration="$1" phase="$2" now="$3" capture session_count selected_count pane_id
  pane_id="$(sidebar_pane_id 2>/dev/null || true)"
  [ -n "$pane_id" ] || pane_id="$SIDEBAR_TARGET"
  capture="$(tmuxc capture-pane -p -t "$pane_id" 2>/dev/null || true)"
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

transition_idle() {
  local state
  state="$(tmuxc show-options -gqv @dotfiles_sidebar_transition 2>/dev/null || true)"
  case "$state" in
    *result=running*|*result=committed*) return 1 ;;
    *) return 0 ;;
  esac
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

move_selection_to_target() {
  local target="$1" current index target_index key
  local -a order=(interactive-anchor flicker-a flicker-b flicker-c flicker-d)
  SIDEBAR_TARGET="$(sidebar_pane_id 2>/dev/null || true)"
  [ -n "$SIDEBAR_TARGET" ] || return 1
  for _ in $(seq 1 8); do
    current="$(sidebar_selected_name)"
    [ "$current" = "$target" ] && return 0
    index=0
    target_index=0
    for i in "${!order[@]}"; do
      [ "${order[$i]}" = "$current" ] && index="$i"
      [ "${order[$i]}" = "$target" ] && target_index="$i"
    done
    key=$'\033[B'
    [ "$index" -gt "$target_index" ] && key=$'\033[A'
    # Reassert the attached client's pane boundary immediately before the
    # physical arrow byte. A sidebar can finish a prior redraw after focus
    # was observed, causing the first byte to reach the work pane.
    tmuxc select-pane -t "$SIDEBAR_TARGET" 2>/dev/null || true
    send_keys "$key"
    moved=false
    for attempt in $(seq 1 20); do
      if [ "$(sidebar_selected_name)" = "$target" ]; then
        moved=true
        break
      fi
      sleep 0.05
    done
    if [ "$moved" != true ]; then
      PHYSICAL_INPUT_FALLBACKS=$((PHYSICAL_INPUT_FALLBACKS + 1))
      fallback_key=Down
      [ "$key" = $'\033[A' ] && fallback_key=Up
      tmuxc send-keys -t "$SIDEBAR_TARGET" "$fallback_key" 2>/dev/null || true
      test_log "input.fallback pane=$SIDEBAR_TARGET key=$fallback_key count=$PHYSICAL_INPUT_FALLBACKS"
      for attempt in $(seq 1 20); do
        if [ "$(sidebar_selected_name)" = "$target" ]; then
          moved=true
          break
        fi
        sleep 0.05
      done
    fi
    if [ "$moved" != true ]; then
      focus_sidebar
      wait_until "sidebar ready after selection retry $target" sidebar_ready
    fi
  done
  return 1
}

setup_interactive_test
for session in "${EXPECTED_SESSIONS[@]}"; do
  create_session "$session"
done

focus_sidebar
wait_until "sidebar input ready before initial selection" \
  '[ "$(tmuxc show-options -wqv -t "$(client_window_id)" @dotfiles_sidebar_input_ready 2>/dev/null || true)" = 1 ]'
move_selection_to_target flicker-a
send_keys $'\r'
wait_until "initial session flicker-a" "wait_session 'flicker-a'"
wait_until "initial sidebar flicker-a" sidebar_ready
wait_until "initial transition idle" transition_idle
: > "$MEASURE_FILE"

for iteration in $(seq 1 8); do
  focus_sidebar
  if [ $((iteration % 2)) -eq 1 ]; then
    target=flicker-b
  else
    target=flicker-a
  fi
  wait_until "sidebar input ready before flicker selection" \
    '[ "$(tmuxc show-options -wqv -t "$(client_window_id)" @dotfiles_sidebar_input_ready 2>/dev/null || true)" = 1 ]'
  move_selection_to_target "$target"
  wait_until "transition idle before flicker Enter" transition_idle
  sleep 0.02
  sample_until_stable "$iteration" "$target"
done

sample_count="$(awk 'END {print NR + 0}' "$MEASURE_FILE")"
invalid_count="$(awk -F '\t' '$5 != 1 || $6 != 4 || $7 != 1 {n++} END {print n + 0}' "$MEASURE_FILE")"
identity_count="$(cut -f4 "$MEASURE_FILE" | sort -u | wc -l | tr -d ' ')"
transition_count="$(grep -c $'\ttransition\t' "$MEASURE_FILE" || true)"

echo "measurement_file=$MEASURE_FILE"
echo "samples=$sample_count transition_samples=$transition_count invalid_frames=$invalid_count sidebar_identities=$identity_count"
echo "physical_input_fallbacks=$PHYSICAL_INPUT_FALLBACKS"

if [ "$invalid_count" -gt 0 ] || [ "$identity_count" -ne 1 ]; then
  echo "invalid_sample_rows(iteration phase timestamp sidebar_id title_count session_count selected_count):"
  awk -F '\t' '$5 != 1 || $6 != 4 || $7 != 1 {print}' "$MEASURE_FILE"
  echo "RED: sidebar transition produced inconsistent sampled frames or pane identity changes" >&2
  exit 1
fi

echo "PASS: no sampled sidebar frame inconsistency detected"
