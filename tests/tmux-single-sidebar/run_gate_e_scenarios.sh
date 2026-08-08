#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd -P)"

printf '=== Gate E Scenario Testing Initiated ===\n'

SCENARIOS=(
    "Scenario 1 (Sidebar Toggle & Provisioning):tests/tmux-single-sidebar/test-contract.sh"
    "Scenario 2 (Session Name Zero & Creation Ambiguity):tests/tmux-single-sidebar/test-session-name-zero.sh"
    "Scenario 3 (Keyboard E2E Arrow Navigation & Switch):tests/tmux-single-sidebar/test-keyboard-e2e-window-local-switch.sh"
    "Scenario 4 (Horizontal & Vertical Direct Layout Round-trip):tests/tmux-single-sidebar/test-keyboard-e2e-direct-layout.sh"
    "Scenario 5 (Arbitrary & Multi-window Topology Archive/Restore):tests/tmux-single-sidebar/test-keyboard-e2e-multi-window-topology.sh"
    "Scenario 6 (Session Rename Round-trip):tests/tmux-single-sidebar/test-keyboard-e2e-rename-roundtrip.sh"
    "Scenario 7 (Rapid Operations Stress & Conflict):tests/tmux-single-sidebar/test-keyboard-e2e-rapid-operations.sh"
    "Scenario 8 (User Live Required Suite Monitored):tests/tmux-single-sidebar/test-user-tmux-required-monitored.sh"
)

TOTAL_FAILURES=0
FAILED_SCENARIOS=()

for entry in "${SCENARIOS[@]}"; do
    label="${entry%%:*}"
    script="${entry#*:}"
    printf '%s\n' "--------------------------------------------------"
    printf '%s\n' "Running: $label"
    printf '%s\n' "Script: $script"
    printf '%s\n' "--------------------------------------------------"
    
    if bash "$REPO_ROOT/$script"; then
        printf '%s\n' "PASS: $label"
    else
        status=$?
        printf '%s\n' "FAIL: $label (exit code $status)"
        TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
        FAILED_SCENARIOS+=("$label")
    fi
done

printf '%s\n' ""
printf '%s\n' "=================================================="
printf '%s\n' "Scenario Execution Summary:"
printf '%s\n' "Total Scenarios: ${#SCENARIOS[@]}"
printf '%s\n' "Passed Scenarios: $(( ${#SCENARIOS[@]} - TOTAL_FAILURES ))"
printf '%s\n' "Failed Scenarios: $TOTAL_FAILURES"

if [ "$TOTAL_FAILURES" -gt 0 ]; then
    printf '%s\n' "Failed Scenarios List:"
    for f in "${FAILED_SCENARIOS[@]}"; do
        printf '%s\n' "  - $f"
    done
    exit 1
else
    printf '%s\n' "All scenarios PASSED with 0 functional errors!"
    exit 0
fi
