#!/usr/bin/env bash
set -euo pipefail

export TERM="${TERM:-xterm-256color}"

TEST_DIR="$(cd -- "$(dirname -- "$BASH_SOURCE")" && pwd -P)"
REPO_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
RUN_DIR="${TMUX_INTERACTIVE_RUN_DIR:-/tmp/dotfiles-$SCENARIO_NAME-$$}"
HOME_DIR="$RUN_DIR/home"
HISTORY_DIR="$RUN_DIR/history"
SOCKET="${TMUX_INTERACTIVE_SOCKET:-dotfiles-$SCENARIO_NAME-$$}"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
INPUT_LOG="$RUN_DIR/input.log"
OUTPUT_LOG="$RUN_DIR/output.log"
TRACE_FILE="$RUN_DIR/trace.log"
DEBUG_FILE="$RUN_DIR/debug.log"
timestamp_mono_ms() { perl -MTime::HiRes=time -e 'printf "%.3f", time * 1000'; }
timestamp_wall() { date -u '+%Y-%m-%dT%H:%M:%S%z'; }
TEST_RUN_ID="${TEST_RUN_ID:-${SCENARIO_NAME}-$(timestamp_mono_ms | tr -d .)-$$}"
TEST_EVENT_SEQUENCE=0
LAST_INPUT_EVENT_SEQUENCE=0
TMUX_CMD=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")
CLIENT_PID=""
KEEP_RUN_DIR="${KEEP_RUN_DIR:-false}"

mkdir -p "$HOME_DIR/.local/bin" "$HISTORY_DIR"
ln -sfn "$LAUNCHER" "$HOME_DIR/.local/bin/tmux-session-launcher"
ln -sfn "$REPO_ROOT/scripts/tmux-sidebar-tmux-adapter" "$HOME_DIR/.local/bin/tmux-sidebar-tmux-adapter"
export HOME="$HOME_DIR" TMUX_SESSION_HISTORY_DIR="$HISTORY_DIR" TERM=xterm
tmuxc() { HOME="$HOME_DIR" tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf" "$@"; }

test_log() {
  TEST_EVENT_SEQUENCE=$((TEST_EVENT_SEQUENCE + 1))
  printf 'ts_wall=%s ts_mono_ms=%s run_id=%s event_seq=%s %s\n' \
    "$(timestamp_wall)" "$(timestamp_mono_ms)" "$TEST_RUN_ID" \
    "$TEST_EVENT_SEQUENCE" "$*" >> "$RUN_DIR/test-trace.log"
}

test_context_snapshot() {
  local client_state pane_state operation_state_value
  client_state="$(tmuxc list-clients -F 'tty=#{client_tty}|session=#{session_name}|window=#{window_id}|pane=#{pane_id}|active=#{window_active}' 2>/dev/null | head -n 1 || true)"
  pane_state="$(tmuxc list-panes -a -F 'session=#{session_name}|window=#{window_id}|pane=#{pane_id}|title=#{pane_title}|pid=#{pane_pid}|active=#{pane_active}|dead=#{pane_dead}' 2>/dev/null | tr '\n' ';' || true)"
  operation_state_value="$(tmuxc show-option -gqv @dotfiles_sidebar_operation 2>/dev/null || true)"
  test_log "context client=[$client_state] operation=$operation_state_value panes=[$pane_state]"
}

cleanup() {
  local status=$?
  set +e
  [ "$status" -eq 0 ] || KEEP_RUN_DIR=true
  kill "$CLIENT_PID" 2>/dev/null
  tmuxc kill-server 2>/dev/null
  [ "$KEEP_RUN_DIR" = true ] || rm -rf "$RUN_DIR"
}
trap cleanup EXIT

send_keys() {
  test_log "input.begin bytes=$(printf '%b' "$1" | od -An -tx1 | tr -d ' \n') client=$(client_tty 2>/dev/null || true) session=$(client_session 2>/dev/null || true) window=$(client_window_id 2>/dev/null || true) sidebar=$(sidebar_pane_id 2>/dev/null || true)"
  LAST_INPUT_EVENT_SEQUENCE="$TEST_EVENT_SEQUENCE"
  if [ "$1" = $'\r' ] || [ "$1" = $'\n' ]; then
    tmuxc send-keys -t "$(sidebar_pane_id 2>/dev/null || true)" Enter 2>/dev/null || true
  else
    eval 'exec 9>&"${ATTACHED[1]}"'
    printf '%b' "$1" >&9
  fi
  test_log "input.end"
}

wait_until() {
  local description="$1" command="$2" i
  test_log "wait.begin description=$description command=$command"
  for i in $(seq 1 100); do
    if eval "$command"; then
      test_log "wait.end description=$description attempts=$i result=pass"
      return 0
    fi
    sleep 0.05
  done
  test_log "wait.end description=$description attempts=100 result=timeout"
  test_context_snapshot
  echo "FAIL: timeout waiting for $description" >&2
  KEEP_RUN_DIR=true
  printf '%s\n' "failure_description=$description" > "$RUN_DIR/failure.txt"
  tmuxc list-clients -F '#{client_control_mode}|#{client_tty}|#{session_name}|#{window_id}|#{pane_id}' > "$RUN_DIR/failure-clients.txt" 2>/dev/null || true
  tmuxc list-panes -a -F '#{session_name}|#{window_id}|#{pane_id}|#{pane_title}|#{pane_pid}|#{pane_active}' > "$RUN_DIR/failure-panes.txt" 2>/dev/null || true
  tmuxc show-options -g 2>/dev/null | grep -E 'dotfiles_sidebar|sidebar_force_refresh' > "$RUN_DIR/failure-options.txt" || true
  tmuxc capture-pane -p -t "$(sidebar_pane_id 2>/dev/null || true)" 2>/dev/null || true
  return 1
}

client_session() {
  local sess=""
  if [ -n "${CLIENT_TTY:-}" ]; then
    sess="$(tmuxc display-message -c "$CLIENT_TTY" -p '#{session_name}' 2>/dev/null || true)"
  fi
  if [ -z "$sess" ]; then
    sess="$(tmuxc list-clients -F '#{client_control_mode}|#{client_tty}|#{session_name}' 2>/dev/null | awk -F'|' -v tty="${CLIENT_TTY:-}" '($1 != 1 && (tty == "" || $2 == tty)) {print $3; exit}')"
  fi
  if [ -z "$sess" ]; then
    sess="$(tmuxc list-clients -F '#{client_control_mode}|#{session_name}' 2>/dev/null | awk -F'|' '$1 != 1 {print $2; exit}')"
  fi
  printf '%s\n' "$sess"
}
client_tty() { local tty; tty="$(tmuxc list-clients -F '#{client_control_mode}|#{client_tty}' 2>/dev/null | awk -F'|' '$1 != 1 && $2 != "" {print $2; exit}')"; if [ -n "$tty" ]; then printf '%s\n' "$tty"; else tmuxc list-clients -F '#{client_tty}' 2>/dev/null | grep -v '^[[:space:]]*$' | head -n 1; fi; }
client_window_id() { local win; win="$(tmuxc list-clients -F '#{client_tty}|#{window_id}' 2>/dev/null | awk -F'|' -v tty="${CLIENT_TTY:-}" '$1 == tty && $2 != "" {print $2; exit}')"; if [ -n "$win" ]; then printf '%s\n' "$win"; else win="$(tmuxc list-clients -F '#{client_control_mode}|#{window_id}' 2>/dev/null | awk -F'|' '$1 != 1 && $2 != "" {print $2; exit}')"; if [ -n "$win" ]; then printf '%s\n' "$win"; else tmuxc list-windows -F '#{window_id}' 2>/dev/null | head -n 1; fi; fi; }
sidebar_pane_id() { tmuxc list-panes -t "$(client_window_id)" -F '#{pane_id}|#{pane_title}' | awk -F'|' '$2=="dotfiles-session-sidebar"{print $1; exit}'; }
count_sidebars() { tmuxc list-panes -a -F '#{pane_title}' | awk '$1=="dotfiles-session-sidebar"{n++} END{print n+0}'; }
count_sessions() { tmuxc list-sessions -F '#{session_name}' | wc -l | tr -d ' '; }
window_sidebar_pane_id() {
  local window_id="$1"
  tmuxc list-panes -t "$window_id" -F '#{pane_id}|#{pane_title}' |
    awk -F'|' '$2=="dotfiles-session-sidebar"{print $1; exit}'
}
window_sidebar_count() {
  local window_id="$1"
  tmuxc list-panes -t "$window_id" -F '#{pane_title}' |
    awk '$1=="dotfiles-session-sidebar"{n++} END{print n+0}'
}
managed_window_ids() {
  tmuxc list-windows -a -F '#{window_id}|#{session_id}|#{session_name}' |
    awk -F'|' '$3 != "" {print $1}' | sort -u
}
window_sidebar_geometry() {
  local window_id="$1" pane_id
  pane_id="$(window_sidebar_pane_id "$window_id")"
  [ -n "$pane_id" ] || return 1
  tmuxc display-message -p -t "$pane_id" \
    '#{pane_id}|#{pane_left}|#{pane_top}|#{pane_width}|#{pane_height}'
}
window_work_topology() {
  local window_id="$1"
  tmuxc list-panes -t "$window_id" \
    -F '#{pane_title}|#{pane_left}|#{pane_top}|#{pane_width}|#{pane_height}|#{pane_current_path}' |
    awk '$1 != "dotfiles-session-sidebar"' | sort
}
window_sidebar_snapshot() {
  local window_id="$1" pane_id
  pane_id="$(window_sidebar_pane_id "$window_id" || true)"
  [ -n "$pane_id" ] || {
    printf 'window=%s sidebar=absent\n' "$window_id"
    return 0
  }
  printf 'window=%s sidebar=%s pid=%s geometry=%s\n' \
    "$window_id" "$pane_id" \
    "$(tmuxc display-message -p -t "$pane_id" '#{pane_pid}')" \
    "$(window_sidebar_geometry "$window_id")"
}
session_exists() { tmuxc has-session -t "=$1" 2>/dev/null; }
wait_session() { [ "$(client_session)" = "$1" ]; }
wait_sidebar_count() { [ "$(count_sidebars)" = "$1" ]; }
wait_session_exists() { session_exists "$1"; }
wait_session_absent() { ! session_exists "$1"; }
wait_capture() { tmuxc capture-pane -p -t "$(sidebar_pane_id)" | grep -Fq "$1"; }
wait_trace() { [ -f "$TRACE_FILE" ] && grep -Fq "$1" "$TRACE_FILE"; }
wait_trace_regex() { [ -f "$TRACE_FILE" ] && grep -Eq "$1" "$TRACE_FILE"; }
wait_sidebar_stable() {
  local first second
  first="$(tmuxc list-panes -a -F '#{pane_id}|#{pane_left}|#{pane_top}|#{pane_width}|#{pane_height}' | awk -F'|' -v id="$(sidebar_pane_id)" '$1 == id {print; exit}')" || return 1
  [ -n "$first" ] || return 1
  sleep 0.1
  second="$(tmuxc list-panes -a -F '#{pane_id}|#{pane_left}|#{pane_top}|#{pane_width}|#{pane_height}' | awk -F'|' -v id="$(sidebar_pane_id)" '$1 == id {print; exit}')" || return 1
  [ "$first" = "$second" ]
}
pane_count_at_least() { [ "$(tmuxc list-panes -t "=$1:" | wc -l)" -ge "$2" ]; }
sidebar_ready() {
  local window_id="$(client_window_id)" pane_id pane_dead pane_pid
  [ "$(tmuxc show-options -wqv -t "$window_id" @dotfiles_sidebar_ready 2>/dev/null || true)" = 1 ] ||
    [ "$(tmuxc show-options -wqv -t "$window_id" @dotfiles_sidebar_input_ready 2>/dev/null || true)" = 1 ] || {
      pane_id="$(sidebar_pane_id)"
      [ -n "$pane_id" ] || return 1
      pane_dead="$(tmuxc display-message -p -t "$pane_id" '#{pane_dead}' 2>/dev/null || true)"
      pane_pid="$(tmuxc display-message -p -t "$pane_id" '#{pane_pid}' 2>/dev/null || true)"
      [ "$pane_dead" = 0 ] && [ -n "$pane_pid" ] &&
        tmuxc capture-pane -p -t "$pane_id" 2>/dev/null | grep -Fq sessions
    }
}
sidebar_active() { [ "$(tmuxc display-message -p -t "$CLIENT_TTY" '#{pane_id}' 2>/dev/null || true)" = "$(sidebar_pane_id 2>/dev/null || true)" ]; }
sidebar_present() { [ -n "$(sidebar_pane_id)" ]; }

wait_prompt() {
  local expected="$1"
  wait_until "prompt $expected" "tmuxc capture-pane -p -t \"\$(sidebar_pane_id)\" | grep -Fq '$expected'"
}

sidebar_row_for() {
  local name="$1"
  tmuxc capture-pane -p -t "$(sidebar_pane_id)" | sed $'s/\033\\[[0-9;]*m//g' | nl -ba | awk -v n="$name" 'index($0,n)>0 {print $1; exit}'
}

sidebar_selected_name() {
  tmuxc capture-pane -p -t "$(sidebar_pane_id)" 2>/dev/null |
    sed $'s/\033\\[[0-9;]*m//g' |
    awk '$1 == ">*" { $1=""; sub(/^ /, ""); print; exit } $1 == ">" { if ($2 == "*") { $1=""; $2=""; sub(/^  */, ""); print; exit } else { $1=""; sub(/^ /, ""); print; exit } }'
}

sidebar_marker_invariant() {
  local expected="$1" state stars selected star_session selected_session actual
  state="$(tmuxc capture-pane -p -t "$(sidebar_pane_id)" 2>/dev/null |
    sed $'s/\033\\[[0-9;]*m//g' |
    awk '
      $1 == ">*" { stars++; selected++; star=$2; choice=$2; next }
      $1 == "*" { stars++; star=$2; next }
      $1 == ">" { selected++; if ($2 == "*") { star=$3; choice=$3 } else { choice=$2 } }
      END { printf "%d|%d|%s|%s\n", stars+0, selected+0, star, choice }
    ')"
  IFS='|' read -r stars selected star_session selected_session <<< "$state"
  actual="$(client_session 2>/dev/null || true)"
  [ "$stars" -eq 1 ] && [ "$selected" -eq 1 ] &&
    [ "$star_session" = "$actual" ] && [ "$selected_session" = "$expected" ]
}

focus_sidebar() {
  sidebar_active && return 0
  tmuxc select-pane -t "$(sidebar_pane_id 2>/dev/null || true)" 2>/dev/null || true
  wait_until "sidebar focus" "sidebar_active"
}

select_session_by_name() {
  local name="$1" i attempt
  focus_sidebar
  wait_until "session $name selectable" "[ -n \"\$(sidebar_row_for '$name')\" ]"
  for i in $(seq 1 12); do
    focus_sidebar
    send_keys $'\r'
    for attempt in $(seq 1 20); do
      [ "$(client_session 2>/dev/null || true)" = "$name" ] && return 0
      sleep 0.05
    done
    focus_sidebar
    send_keys $'\033[B'
    wait_until "selection step $i toward $name" sidebar_ready
  done
  wait_until "session selection $name" "wait_session '$name'"
  wait_until "sidebar ready" sidebar_ready
}

create_session() {
  local name="$1"
  focus_sidebar
  send_keys c
  wait_prompt New:
  send_keys "$name"
  send_keys $'\r'
  wait_until "session $name" "wait_session_exists '$name'"
  wait_until "session $name visible" "[ -n \"\$(sidebar_row_for '$name')\" ]"
  wait_until "sidebar ready" sidebar_ready
}

setup_interactive_test() {
  tmuxc new-session -d -s interactive-anchor -c "$REPO_ROOT" 'sleep 300'
  if [ "${TMUX_INTERACTIVE_CREATE_PEER:-true}" = true ]; then
    tmuxc new-session -d -s interactive-peer -c "$REPO_ROOT" 'sleep 300'
  fi
  if [ "${TMUX_SESSION_LAUNCHER_TRACE:-0}" = 1 ]; then
    tmuxc set-environment -g TMUX_SESSION_LAUNCHER_TRACE 1
    tmuxc set-environment -g TMUX_SESSION_LAUNCHER_TRACE_FILE "$TRACE_FILE"
  fi
  if [ "${TMUX_SESSION_LAUNCHER_DEBUG:-0}" = 1 ]; then
    tmuxc set-environment -g TMUX_SESSION_LAUNCHER_DEBUG 1
    tmuxc set-environment -g TMUX_SESSION_LAUNCHER_DEBUG_FILE "$DEBUG_FILE"
  fi
  if [ -n "${TMUX_SESSION_LAUNCHER_METRICS_FILE:-}" ]; then
    tmuxc set-environment -g TMUX_SESSION_LAUNCHER_METRICS_FILE "$TMUX_SESSION_LAUNCHER_METRICS_FILE"
    tmuxc set-environment -g TMUX_SESSION_LAUNCHER_METRICS_RUN_ID "${TMUX_SESSION_LAUNCHER_METRICS_RUN_ID:-$TEST_RUN_ID}"
  fi
  tmuxc split-window -d -t '=interactive-anchor:' -h -b -l 35 "$LAUNCHER --sidebar"
  local i
  for i in $(seq 1 100); do
    SIDEBAR_TARGET="$(sidebar_pane_id)"
    if [ -z "$SIDEBAR_TARGET" ]; then
      SIDEBAR_TARGET="$(window_sidebar_pane_id "$(tmuxc display-message -p -t '=interactive-anchor:' '#{window_id}')")"
    fi
    [ -n "$SIDEBAR_TARGET" ] && break
    sleep 0.05
  done
  SIDEBAR_PID="$(tmuxc display-message -p -t "$SIDEBAR_TARGET" '#{pane_pid}')"
  local attach_command
  attach_command="tmux -L '$SOCKET' -f '$REPO_ROOT/dotfiles/tmux.conf' attach-session -t interactive-anchor"
  coproc ATTACHED { script -qefc "$attach_command" --log-in "$INPUT_LOG" --log-out "$OUTPUT_LOG" >/dev/null 2>&1; }
  CLIENT_PID="$ATTACHED_PID"
  sleep 0.3
  CLIENT_TTY="$(client_tty)"
  wait_until "sidebar pane provision" sidebar_present
  SIDEBAR_TARGET="$(sidebar_pane_id)"
  focus_sidebar
  wait_until "sidebar input readiness" sidebar_ready
  [ "$(count_sidebars)" = 1 ]
}
