#!/usr/bin/env bash
# Run the three separated benchmarks under one campaign identifier.
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
RUN_ID="${SEPARATION_RUN_ID:-separation-$(date +%Y%m%d-%H%M%S)-$$}"
OUT_DIR="${SEPARATION_OUT_DIR:-${TMPDIR:-/tmp}/sidebar-separation-$RUN_ID}"
mkdir -p "$OUT_DIR"

run_benchmark()
{
    local name="$1"
    shift
    SEPARATION_RUN_ID="$RUN_ID" "$@" > "$OUT_DIR/$name.log" 2>&1
    printf 'CAMPAIGN\t%s\t%s\n' "$RUN_ID" "$name"
    rg '^(META|METRIC|INTERNAL|PHASE|SETTLEMENT|OBSERVER|SUMMARY)' \
        "$OUT_DIR/$name.log" || true
}

run_benchmark launcher \
    env PROFILE_TRACE=1 PROFILE_EVENT_LOOP_ENABLED=true \
        PROFILE_SIGNAL_TIMER_ENABLED=true PROFILE_SECONDS="${PROFILE_SECONDS:-3}" \
        bash "$SCRIPT_DIR/profile-isolated-sidebar-reproduction.sh"
run_benchmark settlement \
    env SETTLEMENT_RUNS="${SETTLEMENT_RUNS:-10}" \
        bash "$SCRIPT_DIR/profile-tmux-settlement.sh"
run_benchmark observer \
    env OBSERVER_RUNS="${OBSERVER_RUNS:-10}" \
        bash "$SCRIPT_DIR/profile-observer-settlement.sh"

printf 'CAMPAIGN_DIR\t%s\n' "$OUT_DIR"
