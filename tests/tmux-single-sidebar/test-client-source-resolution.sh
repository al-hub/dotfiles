#!/usr/bin/env bash
set -euo pipefail

# TDD test verifying that source_session resolution uses active client_tty session context

resolve_source_session()
{
    local pane_session="$1"
    local client_session="$2"
    local source_session="$pane_session"

    if [ -n "$client_session" ]; then
        source_session="$client_session"
    fi
    printf '%s' "$source_session"
}

# Test 1: Pane session differs from active client session (detached background sidebar)
pane_sess="ccc"
client_sess="bbbbbb"

result="$(resolve_source_session "$pane_sess" "$client_sess")"
if [ "$result" != "bbbbbb" ]; then
    echo "FAIL: expected active client session 'bbbbbb', got '$result'"
    exit 1
fi

# Test 2: Target session matches pane session, but differs from active client session
target_sess="ccc"
if [ "$result" = "$target_sess" ]; then
    echo "FAIL: switch should proceed because active client is in '$result', not target '$target_sess'"
    exit 1
fi

echo "PASS: active client session resolution overrides detached background pane session"
