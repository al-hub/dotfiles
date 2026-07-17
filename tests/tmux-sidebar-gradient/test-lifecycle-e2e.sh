#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
FAKE_AI="$TEST_DIR/fake-ai.sh"
SOCKET="gradient-test-$$"
TMP_DIR="$(mktemp -d)"
CONTROL_FILE="$TMP_DIR/control"
DEBUG_FILE="$TMP_DIR/debug.log"

cleanup()
{
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

wait_for_log_after()
{
    start_line="$1"
    pattern="$2"
    attempts=0
    [ "$start_line" -lt 1 ] && start_line=1

    while [ "$attempts" -lt 80 ]; do
        if [ -f "$DEBUG_FILE" ] && tail -n "+$start_line" "$DEBUG_FILE" | grep -Eq "$pattern"; then
            return 0
        fi
        sleep 0.1
        attempts=$((attempts + 1))
    done

    printf 'missing debug pattern after line %s: %s\n' "$start_line" "$pattern" >&2
    [ -f "$DEBUG_FILE" ] && tail -n 30 "$DEBUG_FILE" >&2
    return 1
}

log_line_count()
{
    if [ -f "$DEBUG_FILE" ]; then
        wc -l < "$DEBUG_FILE"
    else
        printf '0\n'
    fi
}

printf 'active\n' > "$CONTROL_FILE"
cp "$(command -v bash)" "$TMP_DIR/codex"
fake_command="\"$TMP_DIR/codex\" \"$FAKE_AI\" \"$CONTROL_FILE\""
ai_pane="$(tmux -L "$SOCKET" new-session -d -P -F '#{pane_id}' -s gradient -x 100 -y 30 "$fake_command")"

sidebar_command="env TMUX_SESSION_LAUNCHER_DEBUG=1 TMUX_SESSION_LAUNCHER_DEBUG_FILE=\"$DEBUG_FILE\" TMUX_SESSION_SIDEBAR_STATE_REFRESH_SECONDS=1 TMUX_SESSION_SIDEBAR_POLL_TIMEOUT=0.05 \"$LAUNCHER\" --sidebar"
sidebar_pane="$(tmux -L "$SOCKET" split-window -d -P -F '#{pane_id}' -t '=gradient:0' -h -b -l 35 "$sidebar_command")"
tmux -L "$SOCKET" select-pane -t "$ai_pane" -T fake-ai
tmux -L "$SOCKET" select-pane -t "$sidebar_pane" -T dotfiles-session-sidebar
tmux -L "$SOCKET" select-pane -t "$sidebar_pane"

wait_for_log_after 0 'state session=gradient .*state=active animate=true'
printf 'PASS: fake AI output starts gradient\n'

start_line="$(log_line_count)"
printf 'waiting\n' > "$CONTROL_FILE"
wait_for_log_after "$start_line" 'state session=gradient .*state=waiting animate=false'
printf 'PASS: stable fake AI output stops gradient\n'

start_line="$(log_line_count)"
printf 'active\n' > "$CONTROL_FILE"
wait_for_log_after "$start_line" 'state session=gradient .*state=active animate=true'
printf 'PASS: resumed fake AI output restarts gradient\n'

start_line="$(log_line_count)"
printf 'exit\n' > "$CONTROL_FILE"
wait_for_log_after "$start_line" 'state session=gradient .*state=idle animate=false'
printf 'PASS: fake AI process exit clears gradient\n'

printf 'SUMMARY: pass=4 xfail=0 fail=0\n'
