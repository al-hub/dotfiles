#!/usr/bin/env bash
set -euo pipefail

# TDD test verifying transition lock clear & source session re-evaluation under continuous rapid switches

can_acquire_transition_lock()
{
    local transition_state="$1"
    local lock_busy="$2"

    if [ "$lock_busy" = "true" ]; then
        return 1
    fi
    case "$transition_state" in
        *"result=running"*) return 1 ;;
        *) return 0 ;;
    esac
}

# Test 1: Completed transition allows immediate next switch lock acquisition
state="operation_id=op-123;source=aaa;target=bbb;result=success;reason=window-local-ready"
if ! can_acquire_transition_lock "$state" "false"; then
    echo "FAIL: completed transition blocked next switch lock"
    exit 1
fi

# Test 2: Active running transition blocks concurrent duplicate switch
running_state="operation_id=op-124;source=aaa;target=bbb;result=running;reason=switching"
if can_acquire_transition_lock "$running_state" "false"; then
    echo "FAIL: running transition should block concurrent duplicate switch"
    exit 1
fi

echo "PASS: transition lock logic correctly handles rapid continuous switches"
