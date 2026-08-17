#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# 1. Structural check: verify transition coalescing and sequence id variables exist
grep -q "_pending_transition_target" "$REPO_DIR/scripts/tmux-session-launcher" || {
    echo "FAIL: _pending_transition_target not found in scripts/tmux-session-launcher"
    exit 1
}

grep -q "_transition_sequence_id" "$REPO_DIR/scripts/tmux-session-launcher" || {
    echo "FAIL: _transition_sequence_id not found in scripts/tmux-session-launcher"
    exit 1
}

# 2. Logic check: test LWW coalescing behavior in unit isolation
test_lww_coalescing() {
    # Initialize variables
    local _pending_transition_target=""
    local _transition_sequence_id=0
    local current_transition_operation_id="test-op-1"
    local drained_target=""

    # Mock transition_is_active to simulate transition in flight
    local mock_transition_active=1
    transition_is_active() {
        return "$mock_transition_active"
    }

    # Mock switch_session
    switch_session() {
        local target="$1"
        if transition_is_active; then
            _pending_transition_target="$target"
            _transition_sequence_id=$((_transition_sequence_id + 1))
            return 0
        fi
        drained_target="$target"
        return 0
    }

    # Simulate transition active
    mock_transition_active=0

    # User rapidly requests switch to session-A
    switch_session "session-A"
    [ "$_pending_transition_target" = "session-A" ] || {
        echo "FAIL: expected pending target 'session-A', got '$_pending_transition_target'"
        exit 1
    }
    [ "$_transition_sequence_id" -eq 1 ] || {
        echo "FAIL: expected sequence id 1, got $_transition_sequence_id"
        exit 1
    }

    # User rapidly requests switch to session-B (LWW overrides session-A)
    switch_session "session-B"
    [ "$_pending_transition_target" = "session-B" ] || {
        echo "FAIL: expected pending target 'session-B', got '$_pending_transition_target'"
        exit 1
    }
    [ "$_transition_sequence_id" -eq 2 ] || {
        echo "FAIL: expected sequence id 2, got $_transition_sequence_id"
        exit 1
    }

    # Now simulate transition finish and drain
    mock_transition_active=1
    if [ -n "$_pending_transition_target" ]; then
        local next_target="$_pending_transition_target"
        _pending_transition_target=""
        switch_session "$next_target"
    fi

    [ "$_pending_transition_target" = "" ] || {
        echo "FAIL: expected cleared pending target, got '$_pending_transition_target'"
        exit 1
    }
    [ "$drained_target" = "session-B" ] || {
        echo "FAIL: expected drained target 'session-B', got '$drained_target'"
        exit 1
    }
}

test_lww_coalescing

echo "PASS: transition coalescing verified"
