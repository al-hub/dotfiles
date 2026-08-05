#!/usr/bin/env bash
set -euo pipefail

# Correlates each render_full invocation with the closest preceding trace
# phase. This is an observer-only test; it validates the production render
# reason markers without changing production state.

SCENARIO_NAME=switch-render-cause
export SCENARIO_NAME
export TMUX_INTERACTIVE_CREATE_PEER=false
export TMUX_SESSION_LAUNCHER_TRACE=1
export TMUX_SESSION_LAUNCHER_DEBUG=1
source "$(dirname -- "$BASH_SOURCE")/test-interactive-common.sh"

EXPECTED="${CAUSE_TRANSITIONS:-4}"
SAMPLE_INTERVAL="${CAUSE_SAMPLE_INTERVAL:-0.005}"
CAUSE_FILE="$RUN_DIR/render-cause.tsv"
TIMELINE_FILE="$RUN_DIR/render-cause-timeline.tsv"
TRACE_FILE="$RUN_DIR/trace.log"
DEBUG_FILE="$RUN_DIR/debug.log"

file_lines() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }

transition_settled() {
  local state
  state="$(tmuxc show-option -gqv '@dotfiles_sidebar_transition' 2>/dev/null || true)"
  case "$state" in
    *result=running*) return 1 ;;
    *) return 0 ;;
  esac
}

setup_interactive_test
create_session cause-a
create_session cause-b
# This test measures render causality, not the setup transition. Establish
# the starting client/window directly and wait for the visible marker so the
# first measured Down+Enter cannot consume a stale setup event.
tmuxc switch-client -c "$CLIENT_TTY" -t '=cause-a:'
wait_until "initial render-cause session" "wait_session 'cause-a'"
focus_sidebar
wait_until "initial render-cause selection" "[ \"\$(sidebar_selected_name 2>/dev/null || true)\" = cause-a ]"

: > "$TRACE_FILE"
: > "$DEBUG_FILE"
: > "$CAUSE_FILE"
: > "$TIMELINE_FILE"

classify_trace_history() {
  local trace_file="$1" from_line="$2" to_line="$3" pane_id="$4" marker
  [ "$to_line" -gt "$from_line" ] || {
    printf '%s\n' unclassified
    return 0
  }

  # Trace has microsecond timestamps. debug_log has only second precision, so
  # this uses the sampler's observation boundary instead of timestamp equality.
  while IFS= read -r marker; do
    case "$marker" in
      *"sidebar.layout.restore"*|*"restore.sidebar-layout"*)
        printf '%s\n' layout-restore
        return 0
        ;;
      *"switch.force-refresh.final"*|*"switch.force-refresh.signal"*)
        printf '%s\n' force-refresh
        return 0
        ;;
      *"input.dispatch.begin"*"key_name=enter"*|*"action.begin type=enter"*)
        printf '%s\n' enter-dispatch
        return 0
        ;;
      *"render.full"*)
        printf '%s\n' full-render-required
        return 0
        ;;
      *"refresh_if_needed"*|*"maintenance.*refresh"*)
        printf '%s\n' periodic-refresh
        return 0
        ;;
    esac
  done < <(sed -n "$((from_line + 1)),$to_line p" "$trace_file" 2>/dev/null |
    awk -v pane="$pane_id" 'pane == "" || $0 ~ ("pane=" pane " ")' | tac)
  printf '%s\n' unclassified
}

normalize_render_reason() {
  local line="$1" reason
  reason="$(printf '%s\n' "$line" | sed -n 's/.* reason=\([^ ]*\).*/\1/p')"
  case "$reason" in
    enter-session-switch) printf '%s\n' enter-dispatch ;;
    force-refresh) printf '%s\n' force-refresh ;;
    history-restore|history-toggle|history-exit) printf '%s\n' layout-restore ;;
    initial) printf '%s\n' initial ;;
    full-render-required) printf '%s\n' full-render-required ;;
    periodic-refresh) printf '%s\n' periodic-refresh ;;
    *) printf '%s\n' "" ;;
  esac
}

start_sampler() {
  local iteration="$1" trace_start="$2" debug_start="$3"
  (
    local debug_seen="$debug_start" trace_seen="$trace_start"
    local trace_before_debug trace_now debug_now line candidate_pre candidate_observed timestamp pane_id
    while :; do
      trace_before_debug="$trace_seen"
      trace_now="$(file_lines "$TRACE_FILE")"
      debug_now="$(file_lines "$DEBUG_FILE")"
      if [ "$debug_now" -gt "$debug_seen" ]; then
        while IFS= read -r line; do
          case "$line" in
            *"render_full start"*)
              timestamp="$(date +%s%N)"
              candidate_pre="$(normalize_render_reason "$line")"
              candidate_observed="$candidate_pre"
              pane_id="$(printf '%s\n' "$line" | sed -n 's/.* pane=\([^ ]*\) .*/\1/p')"
              if [ -z "$candidate_pre" ]; then
                candidate_pre="$(classify_trace_history "$TRACE_FILE" "$trace_start" "$trace_before_debug" "$pane_id")"
                candidate_observed="$(classify_trace_history "$TRACE_FILE" "$trace_start" "$trace_now" "$pane_id")"
              fi
              printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$iteration" "$timestamp" "$debug_seen" "$trace_before_debug" \
                "$trace_now" "$candidate_pre" "$candidate_observed" "$line" >> "$CAUSE_FILE"
              ;;
          esac
          debug_seen=$((debug_seen + 1))
        done < <(sed -n "$((debug_seen + 1)),$debug_now p" "$DEBUG_FILE" 2>/dev/null)
      fi
      if [ "$trace_now" -gt "$trace_seen" ]; then
        while IFS= read -r line; do
          case "$line" in
            *"render.delta.begin"*)
              timestamp="$(date +%s%N)"
              printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$iteration" "$timestamp" "$debug_seen" "$trace_seen" \
                "$trace_now" enter-dispatch enter-dispatch "$line" >> "$CAUSE_FILE"
              ;;
          esac
        done < <(sed -n "$((trace_seen + 1)),$trace_now p" "$TRACE_FILE" 2>/dev/null)
      fi
      printf '%s\t%s\t%s\t%s\t%s\n' \
        "$iteration" "$(date +%s%N)" "$trace_now" "$debug_now" \
        "$(client_session 2>/dev/null || true)" >> "$TIMELINE_FILE"
      trace_seen="$trace_now"
      sleep "$SAMPLE_INTERVAL"
    done
  ) &
  CAUSE_SAMPLER_PID=$!
}

stop_sampler() {
  kill "$CAUSE_SAMPLER_PID" 2>/dev/null || true
  wait "$CAUSE_SAMPLER_PID" 2>/dev/null || true
}

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  iteration timestamp debug_line trace_before_debug trace_after_debug cause_pre cause_observed > "$RUN_DIR/render-cause.header"

completed=0
for iteration in $(seq 1 "$EXPECTED"); do
  focus_sidebar
  if [ $((iteration % 2)) -eq 1 ]; then
    send_keys $'\033[B'
    target=cause-b
  else
    send_keys $'\033[A'
    target=cause-a
  fi
  # Establish the visible selection boundary before starting the observer.
  # A fixed sleep allowed the previous session's marker to be submitted when
  # the TUI was still processing a geometry/refresh signal.
  wait_until "selection target $target" "[ \"\$(sidebar_selected_name 2>/dev/null || true)\" = \"$target\" ]"

  trace_before="$(file_lines "$TRACE_FILE")"
  debug_before="$(file_lines "$DEBUG_FILE")"
  start_sampler "$iteration" "$trace_before" "$debug_before"
  send_keys $'\r'
  if ! wait_until "render cause session $target" "wait_session '$target'"; then
    stop_sampler
    break
  fi
  if ! wait_until "render cause sidebar ready $target" sidebar_ready; then
    stop_sampler
    break
  fi
  if ! wait_until "render cause transition settled $target" transition_settled; then
    stop_sampler
    break
  fi
  sleep 0.1
  stop_sampler
  completed=$((completed + 1))
done

{
  cat "$RUN_DIR/render-cause.header"
  cat "$CAUSE_FILE"
} > "$RUN_DIR/render-cause-with-header.tsv"
mv "$RUN_DIR/render-cause-with-header.tsv" "$CAUSE_FILE"

render_total="$(awk -F '\t' 'NR > 1 {n++} END {print n + 0}' "$CAUSE_FILE")"
unclassified_total="$(awk -F '\t' 'NR > 1 && ($6 == "unclassified" || $7 == "unclassified") {n++} END {print n + 0}' "$CAUSE_FILE")"
ambiguous_total="$(awk -F '\t' 'NR > 1 && $6 != $7 {n++} END {print n + 0}' "$CAUSE_FILE")"
enter_total="$(awk -F '\t' 'NR > 1 && ($6 == "enter-dispatch" || $7 == "enter-dispatch") {n++} END {print n + 0}' "$CAUSE_FILE")"
force_total="$(awk -F '\t' 'NR > 1 && ($6 == "force-refresh" || $7 == "force-refresh") {n++} END {print n + 0}' "$CAUSE_FILE")"
layout_total="$(awk -F '\t' 'NR > 1 && ($6 == "layout-restore" || $7 == "layout-restore") {n++} END {print n + 0}' "$CAUSE_FILE")"
full_total="$(awk -F '\t' 'NR > 1 && ($6 == "full-render-required" || $7 == "full-render-required") {n++} END {print n + 0}' "$CAUSE_FILE")"

echo "cause_file=$CAUSE_FILE"
echo "timeline_file=$TIMELINE_FILE"
echo "completed=$completed requested=$EXPECTED"
echo "render_calls=$render_total enter_dispatch=$enter_total force_refresh=$force_total layout_restore=$layout_total full_render_required=$full_total ambiguous=$ambiguous_total unclassified=$unclassified_total"

if [ "$completed" -ne "$EXPECTED" ] || [ "$render_total" -lt "$EXPECTED" ] ||
   [ "$unclassified_total" -ne 0 ] || [ "$ambiguous_total" -ne 0 ]; then
  KEEP_RUN_DIR=true
  echo "RED: one or more render calls have no unique causal classification" >&2
  echo "artifacts=$RUN_DIR" >&2
  exit 1
fi

echo "PASS: every observed render call has a correlated trace-cause candidate"
