#!/usr/bin/env bash
set -euo pipefail

# Test for Fast-Path Self-Transition & Instant Return in scripts/tmux-session-launcher
# Target threshold: <100ms Hard Gate (P50 15~30ms) when source == target session.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"

# 1. Verify code structure in switch_session()
if ! grep -q "switch.self-transition.fast-path" "$LAUNCHER"; then
    echo "FAIL: fast-path self-transition not found in switch_session in $LAUNCHER"
    exit 1
fi

# 2. Extract and test switch_session behavior in isolation
current_session="sess-alpha"
view_mode="history" # verify it switches to sessions
ensure_called=0
render_called=0
last_trace=""

ensure_selection_visible() {
    ensure_called=$((ensure_called + 1))
}

render_visible_session_rows() {
    render_called=$((render_called + 1))
}

trace_event() {
    last_trace="$1"
}

session_exists() {
    # If fast path works, session_exists must NOT be called on self switch
    echo "ERROR: session_exists called on fast path!" >&2
    return 1
}

# Extract switch_session function from launcher
eval "$(sed -n '/^switch_session()/,/^}/p' "$LAUNCHER")"

# Execute self-transition
start_ns=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
for i in {1..20}; do
    switch_session "sess-alpha"
done
end_ns=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')

total_ns=$((end_ns - start_ns))
# Average duration per iteration in milliseconds
avg_ms=$(awk "BEGIN {printf \"%.2f\", $total_ns / 20 / 1000000}")
echo "Measured 20 self-transitions: total ${total_ns}ns, avg ${avg_ms}ms"

# Hard Gate check: avg < 100ms
is_under_100ms=$(awk "BEGIN {print ($avg_ms < 100) ? 1 : 0}")
if [ "$is_under_100ms" -ne 1 ]; then
    echo "FAIL: self-transition exceeded 100ms hard gate ($avg_ms ms)"
    exit 1
fi

# Verify state mutations and events
if [ "$view_mode" != "sessions" ]; then
    echo "FAIL: view_mode was not reset to 'sessions', got '$view_mode'"
    exit 1
fi

if [ "$ensure_called" -lt 1 ]; then
    echo "FAIL: ensure_selection_visible was not called"
    exit 1
fi

if [ "$render_called" -lt 1 ]; then
    echo "FAIL: render_visible_session_rows was not called"
    exit 1
fi

if [[ "$last_trace" != *"switch.self-transition.fast-path session=sess-alpha result=success"* ]]; then
    echo "FAIL: unexpected trace event: '$last_trace'"
    exit 1
fi

echo "PASS: fast-path self-transition verified (<100ms Hard Gate: ${avg_ms}ms, state updated, trace verified)"
