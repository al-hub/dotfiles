#!/usr/bin/env bash
set -euo pipefail

# Failure/rollback companion for the strict sidebar-fixed transition test.

SCENARIO_NAME=sidebar-fixed-work-failure
export SCENARIO_NAME
export TMUX_SESSION_LAUNCHER_TRACE=1
export TMUX_SESSION_LAUNCHER_DEBUG=1
source "$(dirname -- "$BASH_SOURCE")/test-interactive-common.sh"

# `transition` is the supported fault boundary for the native window-local
# switch path. Keep the override for future step-specific injection tests.
FAIL_STEP="${SIDEBAR_FIXED_FAIL_STEP:-transition}"
TRACE_FILE="$RUN_DIR/trace.log"

setup_interactive_test
tmuxc new-session -d -s fixed-failure-a -c "$REPO_ROOT" 'sleep 300'
tmuxc new-session -d -s fixed-failure-b -c "$REPO_ROOT" 'sleep 300'

# The transition contract requires a target-local sidebar to exist before the
# injected source-side failure is exercised. Provision those infrastructure
# panes explicitly; otherwise the test stops at target-sidebar-missing and
# never reaches the requested rollback fault point.
for failure_session in fixed-failure-a fixed-failure-b; do
  failure_window="$(tmuxc display-message -p -t "=$failure_session:" '#{window_id}')"
  tmuxc set-option -w -t "$failure_window" @dotfiles_sidebar_managed 1
  tmuxc run-shell -b "$LAUNCHER --ensure-sidebar-window $failure_window"
done
wait_until "failure target sidebars" "[ \"\$(count_sidebars)\" -ge 3 ]"

# Replace the normal sidebar with a process whose environment contains the
# requested fault, keeping fixture creation outside the injected operation.
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_FAIL_STEP "$FAIL_STEP"
tmuxc kill-pane -t "$SIDEBAR_TARGET"
tmuxc split-window -d -t '=interactive-anchor:' -h -b -l 35 \
  "'$LAUNCHER' --sidebar"
for attempt in $(seq 1 100); do
  SIDEBAR_TARGET="$(sidebar_pane_id)"
  [ -n "$SIDEBAR_TARGET" ] && break
  sleep 0.05
done
[ -n "$SIDEBAR_TARGET" ]
tmuxc respawn-pane -k -t "$SIDEBAR_TARGET" \
  "env TMUX_SESSION_LAUNCHER_FAIL_STEP=$FAIL_STEP '$LAUNCHER' --sidebar"
wait_until "failure sidebar readiness" sidebar_ready
wait_until "failure target visible" "wait_capture fixed-failure-b"

sidebar_before="$SIDEBAR_TARGET"
geometry_before="$(tmuxc display-message -p -t "$SIDEBAR_TARGET" '#{pane_left}|#{pane_top}|#{pane_width}|#{pane_height}')"
client_before="$(client_session)"
[ "$client_before" = interactive-anchor ]
focus_sidebar

row="$(sidebar_row_for fixed-failure-b)"
current="$(tmuxc capture-pane -p -t "$SIDEBAR_TARGET" | nl -ba |
  awk '$0 ~ />[ *]/ {print $1; exit}')"
[ -n "$row" ] && [ -n "$current" ]
delta=$((row - current))
key=$'\033[B'
[ "$delta" -lt 0 ] && key=$'\033[A'
count="$delta"
[ "$count" -lt 0 ] && count=$((-count))
for i in $(seq 1 "$count"); do send_keys "$key"; done
send_keys $'\r'

for attempt in $(seq 1 100); do
  if grep -q 'transition.rollback.end' "$TRACE_FILE" 2>/dev/null; then
    break
  fi
  sleep 0.05
done

rollback_seen=false
grep -q 'transition.rollback.end' "$TRACE_FILE" 2>/dev/null && rollback_seen=true
failed_seen=false
grep -q 'transition.phase.*phase=FAILED' "$TRACE_FILE" 2>/dev/null && failed_seen=true
sidebar_after="$(sidebar_pane_id)"
geometry_after="$(tmuxc display-message -p -t "$sidebar_after" '#{pane_left}|#{pane_top}|#{pane_width}|#{pane_height}')"
client_after="$(client_session)"
sidebar_count="$(count_sidebars)"

echo "fail_step=$FAIL_STEP rollback_seen=$rollback_seen failed_seen=$failed_seen"
echo "sidebar_before=$sidebar_before sidebar_after=$sidebar_after"
echo "geometry_before=$geometry_before geometry_after=$geometry_after"
echo "client_before=$client_before client_after=$client_after sidebar_count=$sidebar_count"

if [ "$rollback_seen" != true ] || [ "$failed_seen" != true ] ||
   [ "$sidebar_before" != "$sidebar_after" ] ||
   [ "$geometry_before" != "$geometry_after" ] ||
   [ "$client_after" != "$client_before" ] || [ "$sidebar_count" -ne 1 ]; then
  KEEP_RUN_DIR=true
  echo "RED: injected $FAIL_STEP failure did not restore sidebar/client boundary" >&2
  echo "artifacts=$RUN_DIR" >&2
  exit 1
fi

echo "PASS: injected $FAIL_STEP failure preserved sidebar identity/geometry and client session"
