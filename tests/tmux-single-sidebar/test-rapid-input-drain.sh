#!/usr/bin/env bash
set -euo pipefail

# TDD test verifying rapid key sequence non-blocking timeout selection

resolve_read_timeout()
{
    local post_operation_fast_read="$1"
    local has_pending_input="$2"
    local read_timeout="1.0"

    if [ "$post_operation_fast_read" = "true" ] || [ "$has_pending_input" = "true" ]; then
        read_timeout=0.001
    fi
    printf '%s' "$read_timeout"
}

# Test 1: Rapid key press ensures non-blocking timeout
result="$(resolve_read_timeout "true" "false")"
if [ "$result" != "0.001" ]; then
    echo "FAIL: expected non-blocking timeout '0.001', got '$result'"
    exit 1
fi

# Test 2: Rapid pending input ensures non-blocking timeout
result_pending="$(resolve_read_timeout "false" "true")"
if [ "$result_pending" != "0.001" ]; then
    echo "FAIL: expected non-blocking timeout '0.001' for pending input, got '$result_pending'"
    exit 1
fi

echo "PASS: rapid input sequence correctly selects non-blocking read_timeout"
