#!/usr/bin/env bash
set -euo pipefail

# Runs the complete keyboard E2E workflow in an isolated tmux server and
# monitors the attached PTY and launcher trace while the workflow is running.
# It deliberately does not attach a nested tmux to the user's current server.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
if [ -n "${TMUX_LIVE_FULL_RUN_DIR:-}" ]; then
    RUN_DIR="$TMUX_LIVE_FULL_RUN_DIR"
else
    RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-live-full-XXXXXX")"
fi
SOCKET="${TMUX_LIVE_FULL_SOCKET:-dotfiles-live-full-$$}"
EXISTING_SERVER="${TMUX_LIVE_FULL_USER_SERVER:-0}"
VISIBLE_CLIENT="${TMUX_LIVE_FULL_VISIBLE_CLIENT:-}"
MONITOR_LOG="$RUN_DIR/live-monitor.log"
RESULT_LOG="$RUN_DIR/live-result.log"
TEST_PID=""
MONITOR_PID=""
PTY_MONITOR_PID=""
TRACE_MONITOR_PID=""
EVENT_SEQUENCE=0

mkdir -p "$RUN_DIR"
: > "$MONITOR_LOG"
: > "$RESULT_LOG"

log()
{
    EVENT_SEQUENCE=$((EVENT_SEQUENCE + 1))
    printf 'ts_wall=%s ts_mono_ms=%s event_seq=%s %s\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%S%z')" \
        "$(perl -MTime::HiRes=time -e 'printf "%.3f", time * 1000')" \
        "$EVENT_SEQUENCE" "$*" | tee -a "$MONITOR_LOG"
}

normalize_delta()
{
    local source="$1" offset="$2" destination="$3" size bytes
    size="$(wc -c < "$source" 2>/dev/null || printf 0)"
    bytes=$((size - offset))
    [ "$bytes" -gt 0 ] || return 1
    dd if="$source" of="$destination" iflag=skip_bytes,count_bytes \
        skip="$offset" count="$bytes" status=none 2>/dev/null || return 1
    perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\e\][^\a]*\a//g; s/\r//g' \
        "$destination" > "${destination}.txt"
    printf '%s\n' "${destination}.txt"
}

monitor_file()
{
    local name="$1" file="$2" offset=0 normalized delta
    while kill -0 "$TEST_PID" 2>/dev/null; do
        if [ -f "$file" ]; then
            delta="$(normalize_delta "$file" "$offset" "$RUN_DIR/${name}-delta.raw" || true)"
            if [ -n "$delta" ]; then
                normalized="$delta"
                if grep -Ein -- 'ensure-sidebar-window.*returned 1|session[[:space:]]+switch.*failed|longjmp[[:space:]]+causes[[:space:]]+uninitialized[[:space:]]+stack[[:space:]]+frame' "$normalized" > "$RUN_DIR/${name}-matches.log" 2>/dev/null; then
                    while IFS= read -r line; do
                        log "event.source=$name event.match=$line"
                    done < "$RUN_DIR/${name}-matches.log"
                fi
                offset="$(wc -c < "$file")"
            fi
        fi
        sleep 0.05
    done
    if [ -f "$file" ]; then
        delta="$(normalize_delta "$file" "$offset" "$RUN_DIR/${name}-final-delta.raw" || true)"
        if [ -n "$delta" ] && grep -Ein -- 'ensure-sidebar-window.*returned 1|session[[:space:]]+switch.*failed|longjmp[[:space:]]+causes[[:space:]]+uninitialized[[:space:]]+stack[[:space:]]+frame' "$delta" > "$RUN_DIR/${name}-final-matches.log" 2>/dev/null; then
            while IFS= read -r line; do
                log "event.final_source=$name event.match=$line"
            done < "$RUN_DIR/${name}-final-matches.log"
        fi
    fi
}

cleanup()
{
    local status=$?
    # Stop asynchronous hooks before removing temporary panes. Without this,
    # an after-select/session hook can recreate a sidebar in the original
    # visible window after the test has already started cleanup.
    tmux -L "$SOCKET" set-option -gq @dotfiles_sidebar_enabled 0 >/dev/null 2>&1 || true
    tmux -L "$SOCKET" set-option -gq @dotfiles_sidebar_owner_client "" >/dev/null 2>&1 || true
    [ -n "$PTY_MONITOR_PID" ] && kill "$PTY_MONITOR_PID" 2>/dev/null || true
    [ -n "$TRACE_MONITOR_PID" ] && kill "$TRACE_MONITOR_PID" 2>/dev/null || true
    [ -n "$PTY_MONITOR_PID" ] && wait "$PTY_MONITOR_PID" 2>/dev/null || true
    [ -n "$TRACE_MONITOR_PID" ] && wait "$TRACE_MONITOR_PID" 2>/dev/null || true
    # The child test owns this isolated socket and also performs its normal
    # cleanup. This fallback covers interruption before the child trap runs.
    if [ "$EXISTING_SERVER" != 1 ]; then
        tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    fi
    log "runner.exit status=$status socket=$SOCKET artifacts=$RUN_DIR"
    exit "$status"
}
trap cleanup EXIT INT TERM

log "runner.start scenario=full transport=${TMUX_LIVE_FULL_TRANSPORT:-script} socket=$SOCKET artifacts=$RUN_DIR"

TMUX_KEYBOARD_E2E_RUN_DIR="$RUN_DIR" \
TMUX_KEYBOARD_E2E_SOCKET="$SOCKET" \
TMUX_KEYBOARD_E2E_EXISTING_SERVER="$EXISTING_SERVER" \
TMUX_KEYBOARD_E2E_VISIBLE_CLIENT="$VISIBLE_CLIENT" \
TMUX_KEYBOARD_E2E_SCENARIO=full \
TMUX_KEYBOARD_E2E_TRANSPORT="${TMUX_LIVE_FULL_TRANSPORT:-script}" \
TMUX_KEYBOARD_E2E_ANCHOR_SESSION="${TMUX_LIVE_FULL_ANCHOR_SESSION:-keyboard-anchor}" \
TMUX_KEYBOARD_E2E_SEED_LIVE_TOPOLOGY="${TMUX_LIVE_FULL_SEED_LIVE_TOPOLOGY:-0}" \
KEEP_RUN_DIR=true \
    bash "$TEST_DIR/test-keyboard-e2e.sh" > "$RESULT_LOG" 2>&1 &
TEST_PID=$!

while [ ! -f "$RUN_DIR/client.log" ] && kill -0 "$TEST_PID" 2>/dev/null; do
    sleep 0.05
done

monitor_file client-pty "$RUN_DIR/client.log" &
PTY_MONITOR_PID=$!
monitor_file launcher-trace "$RUN_DIR/trace.log" &
TRACE_MONITOR_PID=$!
MONITOR_PID="$PTY_MONITOR_PID $TRACE_MONITOR_PID"

set +e
wait "$TEST_PID"
status=$?
set -e
TEST_PID=""
wait "$PTY_MONITOR_PID" 2>/dev/null || true
wait "$TRACE_MONITOR_PID" 2>/dev/null || true
MONITOR_PID=""

cat "$RESULT_LOG"
if grep -Fq 'event.match=' "$MONITOR_LOG" ||
    [ -s "$RUN_DIR/client-pty-final-matches.log" ] ||
    [ -s "$RUN_DIR/launcher-trace-final-matches.log" ]; then
    log "summary.raw_error=detected"
else
    log "summary.raw_error=not-detected"
fi
log "summary.child_status=$status"
exit "$status"
