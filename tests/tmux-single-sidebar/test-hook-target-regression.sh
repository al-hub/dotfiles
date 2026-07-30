#!/usr/bin/env bash
set -euo pipefail

# Regression test for the user-visible blank hook target:
#   tmux-session-launcher --ensure-sidebar-window  returned 1
# The test uses an attached PTY because tmux reports run-shell failures through
# the client message stream, not through pane capture.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd -P)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-hook-target-$$"
RUN_DIR="${TMUX_HOOK_TARGET_RUN_DIR:-${TMPDIR:-/tmp}/dotfiles-hook-target-$SOCKET}"
ATTACH_PID=""

mkdir -p "$RUN_DIR"

cleanup()
{
    local status=$?
    set +e
    [ -n "$ATTACH_PID" ] && kill "$ATTACH_PID" >/dev/null 2>&1 || true
    [ -n "$ATTACH_PID" ] && wait "$ATTACH_PID" 2>/dev/null || true
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    [ "$status" -eq 0 ] || printf 'artifacts=%s\n' "$RUN_DIR" >&2
    exit "$status"
}
trap cleanup EXIT INT TERM

tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf" \
    new-session -d -s hook-test -c "$REPO_ROOT" 'sleep 300'
tmux -L "$SOCKET" set-environment -g TMUX_SESSION_LAUNCHER_TRACE 1
tmux -L "$SOCKET" set-environment -g TMUX_SESSION_LAUNCHER_TRACE_FILE "$RUN_DIR/trace.log"
tmux -L "$SOCKET" set-environment -g TMUX_SESSION_LAUNCHER_DEBUG 1
tmux -L "$SOCKET" set-environment -g TMUX_SESSION_LAUNCHER_DEBUG_FILE "$RUN_DIR/debug.log"
tmux -L "$SOCKET" run-shell "$LAUNCHER --install-sidebar-hooks"

script -qefc "TERM=xterm tmux -L '$SOCKET' attach-session -t =hook-test" \
    --log-out "$RUN_DIR/client.log" >/dev/null 2>&1 &
ATTACH_PID=$!
sleep 0.3

wait_for_trace()
{
    local pattern="$1" deadline=$(( $(date +%s) + 5 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        grep -Fq -- "$pattern" "$RUN_DIR/trace.log" 2>/dev/null && return 0
        sleep 0.05
    done
    printf 'ERROR: trace did not contain %s\n' "$pattern" >&2
    return 1
}

window_id="$(tmux -L "$SOCKET" new-window -d -t '=hook-test:' -P -F '#{window_id}' 'sleep 300')"
wait_for_trace "args=--ensure-sidebar-window $window_id"

tmux -L "$SOCKET" split-window -d -h -t "$window_id" 'sleep 300'
wait_for_trace "args=--sync-sidebar-layout $window_id"

tmux -L "$SOCKET" new-session -d -s hook-created -c "$REPO_ROOT" 'sleep 300'
wait_for_trace 'args=--ensure-sidebar-session hook-created'

perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\e\][^\a]*\a//g; s/\r//g' \
    "$RUN_DIR/client.log" > "$RUN_DIR/client-normalized.log"
if grep -Ein -- 'ensure-sidebar-window[[:space:]]+([^@[:space:]]|$).*returned 1|--ensure-sidebar-window[[:space:]]+returned 1' \
    "$RUN_DIR/client-normalized.log" "$RUN_DIR/trace.log" 2>/dev/null; then
    printf 'FAIL: blank ensure-sidebar-window target or returned 1 detected\n' >&2
    exit 1
fi

printf 'PASS: after-window hooks receive non-empty window_id\n'
printf 'PASS: after-session hook receives session_name\n'
printf 'PASS: no blank ensure-sidebar-window target or returned 1\n'
printf 'artifacts=%s\n' "$RUN_DIR"
