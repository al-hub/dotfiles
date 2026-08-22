#!/usr/bin/env bash
# Unit tests for pure domain activity tracker in scripts/lib/sidebar_domain_activity.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/sidebar_domain_activity.sh"

echo "=== Running Activity Observer Domain Unit Tests ==="

# 1. Parse signature
if ! sidebar_domain_activity_parse_signature "1700000000:100:12:5"; then
    echo "FAIL: valid signature failed to parse"
    exit 1
fi
[ "$sig_act" = "1700000000" ] && [ "$sig_hist" = "100" ] && [ "$sig_cy" = "12" ] && [ "$sig_cx" = "5" ] || {
    echo "FAIL: signature fields incorrect: act=$sig_act hist=$sig_hist cy=$sig_cy cx=$sig_cx"
    exit 1
}
echo "PASS: Signature parsed accurately: act=$sig_act hist=$sig_hist cy=$sig_cy cx=$sig_cx"

# 2. Signature changes
if ! sidebar_domain_activity_has_changed "1000:50:5:10" "1001:50:5:10"; then
    echo "FAIL: expected change on activity difference"
    exit 1
fi
echo "PASS: Signature change detected on activity difference"

if ! sidebar_domain_activity_has_changed "1000:50:5:10" "1000:50:6:10"; then
    echo "FAIL: expected change on cursor difference"
    exit 1
fi
echo "PASS: Signature change detected on cursor difference"

if sidebar_domain_activity_has_changed "1000:50:5:10" "1000:50:5:10"; then
    echo "FAIL: expected no change on identical signature"
    exit 1
fi
echo "PASS: Signature identical detected as unchanged"

# 3. PID registration & eviction
sidebar_domain_activity_register_pid "session-test" "12345" "opencode"
pid_res="$(sidebar_domain_activity_get_pid "session-test")"
[ "$pid_res" = "12345" ] || { echo "FAIL: registered PID mismatch: '$pid_res'"; exit 1; }
echo "PASS: PID registered accurately: $pid_res"

sidebar_domain_activity_evict_pid "session-test"
pid_res="$(sidebar_domain_activity_get_pid "session-test")"
[ -z "$pid_res" ] || { echo "FAIL: evicted PID still present: '$pid_res'"; exit 1; }
echo "PASS: PID eviction cleared entry"

# 4. PID liveness
if ! sidebar_domain_activity_is_pid_alive "$$"; then
    echo "FAIL: current process reported dead"
    exit 1
fi
echo "PASS: Current PID is reported alive"

if sidebar_domain_activity_is_pid_alive "99999999"; then
    echo "FAIL: non-existent PID reported alive"
    exit 1
fi
echo "PASS: Invalid PID 99999999 is reported dead"

# 5. State evaluation
sidebar_domain_activity_register_pid "sess-1" "$$" "opencode"
sidebar_domain_activity_evaluate_state "sess-1" "1000:10:1:1" "$$"
[ "$eval_state" = "active" ] && [ "$eval_animate" = "true" ] || {
    echo "FAIL: expected initial state active (animate=true), got state=$eval_state animate=$eval_animate"
    exit 1
}
echo "PASS: Fresh active state with alive PID evaluates to active (animate=true)"

# Stable cycle 1
sidebar_domain_activity_evaluate_state "sess-1" "1000:10:1:1" "$$"
[ "$eval_state" = "active" ] && [ "$eval_animate" = "true" ] || {
    echo "FAIL: expected cycle 1 to remain active, got state=$eval_state animate=$eval_animate"
    exit 1
}
echo "PASS: First unchanged cycle remains active (animate=true)"

# Stable cycle 2 -> waiting
sidebar_domain_activity_evaluate_state "sess-1" "1000:10:1:1" "$$"
[ "$eval_state" = "waiting" ] && [ "$eval_animate" = "false" ] || {
    echo "FAIL: expected cycle 2 to transition to waiting, got state=$eval_state animate=$eval_animate"
    exit 1
}
echo "PASS: Second unchanged cycle transitions to waiting (animate=false)"

# New activity -> active
sidebar_domain_activity_evaluate_state "sess-1" "1001:10:1:2" "$$"
[ "$eval_state" = "active" ] && [ "$eval_animate" = "true" ] || {
    echo "FAIL: expected new activity to transition back to active, got state=$eval_state animate=$eval_animate"
    exit 1
}
echo "PASS: New activity transitions back to active (animate=true)"

# Dead PID -> idle
sidebar_domain_activity_evaluate_state "sess-1" "1001:10:1:2" "99999999"
[ "$eval_state" = "idle" ] && [ "$eval_animate" = "false" ] || {
    echo "FAIL: expected dead PID to transition to idle, got state=$eval_state animate=$eval_animate"
    exit 1
}
echo "PASS: Dead PID immediately transitions to idle (animate=false)"

# 6. Active count resolution
sidebar_domain_activity_clear_all
sidebar_domain_activity_register_pid "sess-a" "$$" "claude"
sidebar_domain_activity_register_pid "sess-b" "$$" "opencode"
# Must evaluate state to populate _SIDEBAR_ACTIVITY_STATE
sidebar_domain_activity_evaluate_state "sess-a" "1000:10:1:1" "$$"
sidebar_domain_activity_evaluate_state "sess-b" "2000:20:2:2" "$$"
cnt="$(sidebar_domain_activity_resolve_active_count)"
[ "$cnt" = "2" ] || { echo "FAIL: expected 2 active sessions, got $cnt"; exit 1; }
echo "PASS: Active session count is 2"

# Transition sess-a to idle by killing its PID reference
sidebar_domain_activity_evaluate_state "sess-a" "1000:10:1:1" "99999999"
cnt="$(sidebar_domain_activity_resolve_active_count)"
[ "$cnt" = "1" ] || { echo "FAIL: expected 1 active session, got $cnt"; exit 1; }
echo "PASS: Active session count decremented to 1 after sess-a became idle"

sidebar_domain_activity_clear_all
cnt="$(sidebar_domain_activity_resolve_active_count)"
[ "$cnt" = "0" ] || { echo "FAIL: expected 0 active sessions after clear, got $cnt"; exit 1; }
echo "PASS: Active session count is 0 after clearing all"

echo "=== All 12 Activity Observer Unit Tests Passed ==="
