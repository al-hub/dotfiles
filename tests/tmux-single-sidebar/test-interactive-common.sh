#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "$BASH_SOURCE")" && pwd -P)"
REPO_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
RUN_DIR="/tmp/dotfiles-$SCENARIO_NAME-$$"
HOME_DIR="$RUN_DIR/home"
HISTORY_DIR="$RUN_DIR/history"
SOCKET="dotfiles-$SCENARIO_NAME-$$"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
INPUT_LOG="$RUN_DIR/input.log"
OUTPUT_LOG="$RUN_DIR/output.log"
TMUX_CMD=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")
CLIENT_PID=""
KEEP_RUN_DIR="${KEEP_RUN_DIR:-false}"

mkdir -p "$HOME_DIR/.local/bin" "$HISTORY_DIR"
ln -sfn "$LAUNCHER" "$HOME_DIR/.local/bin/tmux-session-launcher"
ln -sfn "$REPO_ROOT/scripts/tmux-sidebar-tmux-adapter" "$HOME_DIR/.local/bin/tmux-sidebar-tmux-adapter"
ln -sfn "$REPO_ROOT/scripts/tmux-sidebar-controller" "$HOME_DIR/.local/bin/tmux-sidebar-controller"
export HOME="$HOME_DIR" TMUX_SESSION_HISTORY_DIR="$HISTORY_DIR" TERM=xterm
tmuxc() { HOME="$HOME_DIR" tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf" "$@"; }

cleanup() {
  set +e
  kill "$CLIENT_PID" 2>/dev/null
  tmuxc kill-server 2>/dev/null
  [ "$KEEP_RUN_DIR" = true ] || rm -rf "$RUN_DIR"
}
trap cleanup EXIT

send_keys() {
  eval 'exec 9>&"${ATTACHED[1]}"'
  printf '%b' "$1" >&9
}

wait_until() {
  local description="$1" command="$2" i
  for i in $(seq 1 100); do
    if eval "$command"; then return 0; fi
    sleep 0.05
  done
  echo "FAIL: timeout waiting for $description" >&2
  tmuxc capture-pane -p -t "$SIDEBAR_TARGET" 2>/dev/null || true
  return 1
}

client_session() { tmuxc display-message -p -t "$CLIENT_TTY" '#{client_session}'; }
client_tty() { tmuxc list-clients -F '#{client_tty}' | head -n 1; }
sidebar_pane_id() { tmuxc list-panes -a -F '#{pane_id}|#{pane_title}' | awk -F'|' '$2=="dotfiles-session-sidebar"{print $1; exit}'; }
count_sidebars() { tmuxc list-panes -a -F '#{pane_title}' | awk '$1=="dotfiles-session-sidebar"{n++} END{print n+0}'; }
session_exists() { tmuxc has-session -t "=$1" 2>/dev/null; }
wait_session() { [ "$(client_session)" = "$1" ]; }
wait_sidebar_count() { [ "$(count_sidebars)" = "$1" ]; }
wait_session_exists() { session_exists "$1"; }
wait_session_absent() { ! session_exists "$1"; }
wait_capture() { tmuxc capture-pane -p -t "$SIDEBAR_TARGET" | grep -Fq "$1"; }
pane_count_at_least() { [ "$(tmuxc list-panes -t "=$1:" | wc -l)" -ge "$2" ]; }
sidebar_ready() { [ "$(tmuxc show-options -gqv @dotfiles_sidebar_input_ready 2>/dev/null || true)" = 1 ]; }
sidebar_active() { [ "$(tmuxc display-message -p -t "$CLIENT_TTY" '#{pane_title}')" = dotfiles-session-sidebar ]; }

wait_prompt() {
  local expected="$1"
  wait_until "prompt $expected" "tmuxc capture-pane -p -t \"$SIDEBAR_TARGET\" | grep -Fq '$expected'"
}

sidebar_row_for() {
  local name="$1"
  tmuxc capture-pane -p -t "$SIDEBAR_TARGET" | nl -ba | awk -v n="$name" 'index($0,n)>0 {print $1; exit}'
}

focus_sidebar() {
  local i
  for i in $(seq 1 8); do
    sidebar_active && return 0
    send_keys $'\001o'
    sleep 0.1
  done
  wait_until "sidebar focus" "sidebar_active"
}

create_session() {
  local name="$1"
  focus_sidebar
  send_keys c
  wait_prompt New:
  send_keys "$name"
  send_keys $'\r'
  wait_until "session $name" "wait_session_exists '$name'"
  wait_until "sidebar ready" sidebar_ready
}

select_session_by_name() {
  local name="$1" row current delta key i count
  focus_sidebar
  row="$(sidebar_row_for "$name")"
  [ -n "$row" ] || return 1
  current="$(tmuxc capture-pane -p -t "$SIDEBAR_TARGET" | nl -ba | awk '$0 ~ />[ *]/ {print $1; exit}')"
  [ -n "$current" ] || current="$row"
  delta=$((row - current))
  key=$'\033[B'
  [ "$delta" -lt 0 ] && key=$'\033[A'
  count="$delta"
  [ "$count" -lt 0 ] && count=$((-count))
  for i in $(seq 1 "$count"); do send_keys "$key"; done
  send_keys $'\r'
  wait_until "session selection $name" "wait_session '$name'"
  wait_until "sidebar ready" sidebar_ready
}

setup_interactive_test() {
  tmuxc new-session -d -s interactive-anchor -c "$REPO_ROOT" 'sleep 300'
  tmuxc new-session -d -s interactive-peer -c "$REPO_ROOT" 'sleep 300'
  tmuxc split-window -d -t '=interactive-anchor:' -h -b -l 35 "$LAUNCHER --sidebar"
  local i
  for i in $(seq 1 100); do
    SIDEBAR_TARGET="$(sidebar_pane_id)"
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
  wait_until "sidebar input readiness" sidebar_ready
  [ "$(count_sidebars)" = 1 ]
}
