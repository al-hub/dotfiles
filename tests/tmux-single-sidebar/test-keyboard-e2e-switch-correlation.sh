#!/usr/bin/env bash
set -euo pipefail

# Correlates physical PTY input, launcher trace phases, and terminal output for
# each session switch. The test does not mutate production state beyond the
# normal attached-PTY scenario.

SCENARIO_NAME=switch-correlation
export SCENARIO_NAME
export TMUX_SESSION_LAUNCHER_TRACE=1
export TMUX_SESSION_LAUNCHER_DEBUG=1
source "$(dirname -- "$BASH_SOURCE")/test-interactive-common.sh"

MEASURE_FILE="$RUN_DIR/switch-correlation.tsv"
EXPECTED=10

file_bytes() { [ -f "$1" ] && wc -c < "$1" | tr -d ' ' || echo 0; }
file_lines() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }

setup_interactive_test
create_session corr-a
create_session corr-b
select_session_by_name corr-a

: > "$TRACE_FILE"
: > "$DEBUG_FILE"
: > "$MEASURE_FILE"

completed=0
for iteration in $(seq 1 "$EXPECTED"); do
  focus_sidebar
  if [ $((iteration % 2)) -eq 1 ]; then
    send_keys $'\033[B'
    target=corr-b
  else
    send_keys $'\033[A'
    target=corr-a
  fi
  sleep 0.02
  input_before="$(file_bytes "$INPUT_LOG")"
  output_before="$(file_bytes "$OUTPUT_LOG")"
  trace_before="$(file_lines "$TRACE_FILE")"
  send_keys $'\r'
  if ! wait_until "correlated session $target" "wait_session '$target'"; then
    break
  fi
  if ! wait_until "correlated sidebar ready $target" sidebar_ready; then
    break
  fi
  sleep 0.1
  input_after="$(file_bytes "$INPUT_LOG")"
  output_after="$(file_bytes "$OUTPUT_LOG")"
  trace_after="$(file_lines "$TRACE_FILE")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$iteration" "$target" "$input_before" "$input_after" \
    "$output_before" "$output_after" "$trace_before" "$trace_after" \
    >> "$MEASURE_FILE"
  completed=$((completed + 1))
done

switch_begin="$(grep -c 'switch.begin session=corr-' "$TRACE_FILE" 2>/dev/null || true)"
sidebar_move_begin="$(grep -c 'switch.sidebar.move.begin session=corr-' "$TRACE_FILE" 2>/dev/null || true)"
sidebar_move_end="$(grep -c 'switch.sidebar.move.end session=corr-' "$TRACE_FILE" 2>/dev/null || true)"
client_begin="$(grep -c 'switch.client.begin session=corr-' "$TRACE_FILE" 2>/dev/null || true)"
client_end="$(grep -c 'switch.client.end session=corr-' "$TRACE_FILE" 2>/dev/null || true)"
refresh_begin="$(grep -c 'switch.force-refresh.final.begin session=corr-' "$TRACE_FILE" 2>/dev/null || true)"
refresh_end="$(grep -c 'switch.force-refresh.final.end session=corr-' "$TRACE_FILE" 2>/dev/null || true)"
switch_end="$(grep -c 'switch.end session=corr-' "$TRACE_FILE" 2>/dev/null || true)"
abort_count="$(grep -c 'switch.abort.*session=corr-' "$TRACE_FILE" 2>/dev/null || true)"
render_begin=$((
  $(grep -c 'render_full start' "$DEBUG_FILE" 2>/dev/null || true) +
  $(grep -c 'render.delta.begin' "$TRACE_FILE" 2>/dev/null || true)
))
render_end=$((
  $(grep -c 'render_full end' "$DEBUG_FILE" 2>/dev/null || true) +
  $(grep -c 'render.delta.end' "$TRACE_FILE" 2>/dev/null || true)
))
hook_begin="$(grep -c 'sidebar.hook.sync.begin' "$TRACE_FILE" 2>/dev/null || true)"
hook_end="$(grep -c 'sidebar.hook.sync.end.*result=ok' "$TRACE_FILE" 2>/dev/null || true)"
layout_restore_begin="$(grep -c 'sidebar.layout.restore.begin' "$TRACE_FILE" 2>/dev/null || true)"
input_read="$(grep -c 'input.read.result.*result=key' "$TRACE_FILE" 2>/dev/null || true)"

echo "measurement_file=$MEASURE_FILE"
echo "completed=$completed requested=$EXPECTED"
echo "switch_begin=$switch_begin sidebar_move=$sidebar_move_begin/$sidebar_move_end"
echo "client_switch=$client_begin/$client_end refresh=$refresh_begin/$refresh_end"
echo "switch_end=$switch_end aborts=$abort_count"
echo "render_calls=$render_begin/$render_end hook_sync=$hook_begin/$hook_end"
echo "layout_restore_begin=$layout_restore_begin input_read=$input_read"

if [ "$completed" -ne "$EXPECTED" ] ||
   [ "$switch_begin" -ne "$EXPECTED" ] ||
   [ "$sidebar_move_begin" -ne "$EXPECTED" ] ||
   [ "$sidebar_move_end" -ne "$EXPECTED" ] ||
   [ "$client_begin" -ne "$EXPECTED" ] ||
   [ "$client_end" -ne "$EXPECTED" ] ||
   [ "$refresh_begin" -ne "$EXPECTED" ] ||
   [ "$refresh_end" -ne "$EXPECTED" ] ||
   [ "$switch_end" -ne "$EXPECTED" ] ||
   [ "$abort_count" -ne 0 ] ||
   [ "$render_begin" -ne "$EXPECTED" ] ||
   [ "$render_begin" -ne "$render_end" ] ||
   [ "$input_read" -lt "$EXPECTED" ]; then
  KEEP_RUN_DIR=true
  echo "RED: PTY input/launcher transition correlation is incomplete" >&2
  echo "artifacts=$RUN_DIR" >&2
  exit 1
fi

echo "PASS: all physical session switches correlate through launcher transition phases"
