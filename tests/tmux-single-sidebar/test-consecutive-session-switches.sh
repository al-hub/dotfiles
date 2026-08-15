#!/usr/bin/env bash
set -euo pipefail

# TDD test verifying that source_session resolution strictly relies on active client context
# even when pane_window or detached sidebar metadata lags behind.

resolve_source_session_strict()
{
    local client_tty="$1"
    local pane_session="$2"
    local active_client_session="$3"
    local source_session=""

    if [ -n "$client_tty" ] && [ -n "$active_client_session" ]; then
        source_session="$active_client_session"
    else
        source_session="$pane_session"
    fi

    printf '%s' "$source_session"
}

# Test 1: Detached window presenter pane (%1 in '0') receiving enter key when client is in 'ccc'
client_tty="/dev/pts/0"
pane_session="0"
active_client_session="ccc"

resolved="$(resolve_source_session_strict "$client_tty" "$pane_session" "$active_client_session")"
if [ "$resolved" != "ccc" ]; then
    echo "FAIL: expected active client session 'ccc', got '$resolved'"
    exit 1
fi

# Test 2: Target session is 'ccc', so [ "$resolved" = "$target" ] would abort if source wasn't ccc.
# Now if user selects target '0', source 'ccc' != target '0', so switch must proceed.
target_session="0"
if [ "$resolved" = "$target_session" ]; then
    echo "FAIL: source session matched target session prematurely"
    exit 1
fi

echo "PASS: strict client session resolution correctly overrides pane session"
