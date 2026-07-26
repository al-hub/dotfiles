#!/usr/bin/env bash
set -euo pipefail

# Measurement-only scenario for the user-visible transition:
# sidebar remains mounted while the selected session changes, with each
# session containing a different multi-pane work layout. The sampler records
# sidebar completeness and pane/layout metadata during the real PTY Enter
# transition. No production behavior is changed by this test.

SCENARIO_NAME=switch-visual-layer-measurement
export SCENARIO_NAME
source "$(dirname -- "$BASH_SOURCE")/test-interactive-common.sh"

MEASURE_FILE="$RUN_DIR/visual-transition-samples.tsv"
EXPECTED_SESSIONS=(visual-a visual-b visual-c)

visual_signature() {
  local session="$1"
  tmuxc list-panes -t "=$session:" \
    -F '#{pane_id}|#{pane_title}|#{pane_left}|#{pane_top}|#{pane_width}|#{pane_height}|#{pane_active}' |
    sort | cksum | awk '{print $1}'
}

visual_sample() {
  local iteration="$1" phase="$2" now="$3" session capture title_count footer_count \
    session_count selected_count layer sidebar_id sidebar_geom layout pane_signature
  session="$(client_session)"
  capture="$(tmuxc capture-pane -p -t "$SIDEBAR_TARGET" 2>/dev/null || true)"
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
  layout="$(tmuxc display-message -p -t "$CLIENT_TTY" '#{window_layout}')"
  pane_signature="$(visual_signature "$session")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$iteration" "$phase" "$now" "$session" "$layer" "$sidebar_id" \
    "$sidebar_geom" "$layout" "$pane_signature" "$title_count/$session_count/$footer_count/$selected_count" \
    >> "$MEASURE_FILE"
}

sample_switch() {
  local iteration="$1" target="$2" sampler_pid start end
  start="$(date +%s%N)"
  (
    while :; do
      visual_sample "$iteration" transition "$(date +%s%N)"
      sleep 0.01
    done
  ) &
  sampler_pid="$!"

  send_keys $'\r'
  wait_until "visual session $target" "wait_session '$target'"
  wait_until "visual sidebar ready $target" sidebar_ready
  end="$(date +%s%N)"
  kill "$sampler_pid" 2>/dev/null || true
  wait "$sampler_pid" 2>/dev/null || true
  visual_sample "$iteration" stable "$end"
  printf 'iteration=%s target=%s transition_ns=%s\n' \
    "$iteration" "$target" "$((end - start))"
}

setup_interactive_test
for session in "${EXPECTED_SESSIONS[@]}"; do
  create_session "$session"
done

select_session_by_name visual-a

for session in visual-b visual-c; do
  # Establish the work topology before the user performs the switch. The
  # switch itself remains an attached-PTY keyboard action.
  work_pane="$(tmuxc list-panes -t "=$session:" -F '#{pane_id}|#{pane_title}' |
    awk -F'|' '$2 != "dotfiles-session-sidebar" {print $1; exit}')"
  tmuxc split-window -d -t "$work_pane" -h -b -l 35 'sleep 300'
  tmuxc split-window -d -t "$work_pane" -v -l 8 'sleep 300'
done

: > "$MEASURE_FILE"

for iteration in $(seq 1 6); do
  focus_sidebar
  if [ $((iteration % 2)) -eq 1 ]; then
    send_keys $'\033[B'
    target=visual-b
  else
    send_keys $'\033[A'
    target=visual-a
  fi
  sleep 0.02
  sample_switch "$iteration" "$target"
done

sample_count="$(awk 'END {print NR + 0}' "$MEASURE_FILE")"
blank_count="$(awk -F '\t' '$5 == "blank" {n++} END {print n + 0}' "$MEASURE_FILE")"
partial_count="$(awk -F '\t' '$5 == "partial" {n++} END {print n + 0}' "$MEASURE_FILE")"
complete_count="$(awk -F '\t' '$5 == "complete" {n++} END {print n + 0}' "$MEASURE_FILE")"
sidebar_identity_count="$(cut -f6 "$MEASURE_FILE" | sort -u | wc -l | tr -d ' ')"
sidebar_geometry_count="$(cut -f7 "$MEASURE_FILE" | sort -u | wc -l | tr -d ' ')"

echo "measurement_file=$MEASURE_FILE"
echo "samples=$sample_count blank_frames=$blank_count partial_frames=$partial_count complete_frames=$complete_count"
echo "sidebar_identities=$sidebar_identity_count sidebar_geometries=$sidebar_geometry_count"

if [ "$blank_count" -gt 0 ] || [ "$partial_count" -gt 0 ] ||
   [ "$sidebar_identity_count" -ne 1 ] || [ "$sidebar_geometry_count" -ne 1 ]; then
  echo "RED: visual transition exposed blank/partial sidebar frames or changed sidebar identity/geometry" >&2
  echo "invalid_sample_rows(iteration phase timestamp session layer sidebar_id geometry layout pane_signature completeness):"
  awk -F '\t' '$5 != "complete" {print}' "$MEASURE_FILE"
  exit 1
fi

echo "PASS: visual transition remained complete and geometrically stable in sampled frames"
