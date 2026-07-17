#!/usr/bin/env bash
# Repeat and aggregate the controlled attached-client baseline.
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
RUNS="${PROFILE_RUNS:-3}"
REPORT_FILE="$SCRIPT_DIR/profile-comparison-report.md"
RESULT_DIR="${TMPDIR:-/tmp}/tmux-sidebar-baseline-$$"

usage()
{
    printf 'Usage: %s [--runs COUNT] [--report PATH]\n' "$0"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --runs)
            RUNS="$2"
            shift 2
            ;;
        --report)
            REPORT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

case "$RUNS" in
    ''|*[!0-9]*|0) echo "ERROR: run count must be a positive integer" >&2; exit 2 ;;
esac

mkdir -p "$RESULT_DIR"
cleanup()
{
    rm -rf "$RESULT_DIR"
}
trap cleanup EXIT INT TERM

echo "Running $RUNS controlled baseline measurement(s)..."
for run in $(seq 1 "$RUNS"); do
    log="$RESULT_DIR/run-$run.log"
    echo "  run $run/$RUNS"
    if ! "$SCRIPT_DIR/profile-isolated-sidebar.sh" > "$log"; then
        cat "$log" >&2
        echo "ERROR: baseline run $run failed" >&2
        exit 1
    fi
    if grep -q $'^METRIC\t.*\tFAIL$' "$log"; then
        cat "$log" >&2
        echo "ERROR: baseline run $run reported a failed invariant" >&2
        exit 1
    fi
done

metric_values()
{
    local key="$1"
    awk -F '\t' -v key="$key" '$1 == "METRIC" && $2 == key { print $3 }' "$RESULT_DIR"/run-*.log
}

summary()
{
    local key="$1" unit="$2"
    metric_values "$key" | sort -n | awk -v unit="$unit" '
        { values[NR]=$1; sum+=$1 }
        END {
            if (NR == 0) { print "N/A"; exit 1 }
            if (NR % 2) median=values[(NR+1)/2]
            else median=(values[NR/2] + values[NR/2+1]) / 2
            printf "%.2f %s (range %.2f-%.2f)", median, unit, values[1], values[NR]
        }'
}

median_value()
{
    local key="$1"
    metric_values "$key" | sort -n | awk '
        { values[NR]=$1 }
        END {
            if (NR == 0) exit 1
            if (NR % 2) print values[(NR+1)/2]
            else print (values[NR/2] + values[NR/2+1]) / 2
        }'
}

under_target()
{
    local key="$1" target="$2"
    awk -v value="$(median_value "$key")" -v target="$target" 'BEGIN { exit !(value <= target) }'
}

all_equal()
{
    local key="$1" expected="$2"
    [ "$(metric_values "$key" | awk -v expected="$expected" '$1 != expected { bad=1 } END { print bad+0 }')" = 0 ]
}

commit="$(awk -F '\t' '$1 == "META" && $2 == "commit" { print $3; exit }' "$RESULT_DIR/run-1.log")"
dirty="$(awk -F '\t' '$1 == "META" && $2 == "dirty" { print $3; exit }' "$RESULT_DIR/run-1.log")"
tmux_version="$(awk -F '\t' '$1 == "META" && $2 == "tmux" { print $3; exit }' "$RESULT_DIR/run-1.log")"
generated_at="$(date -Iseconds)"

idle_cpu="$(summary idle_cpu_percent '%')"
idle_rss="$(summary idle_peak_rss_kb 'KiB')"
active_cpu="$(summary active_cpu_percent '%')"
active_rss="$(summary active_peak_rss_kb 'KiB')"
reactivity="$(summary key_reactivity_ms 'ms')"
switching="$(summary session_switch_ms 'ms')"
archive_time="$(summary archive_ms 'ms')"
archive_size="$(summary archive_bytes 'bytes')"
restore_time="$(summary restore_ms 'ms')"
idle_result=FAIL
active_result=FAIL
reactivity_result=FAIL
switching_result=FAIL
archive_time_result=FAIL
restore_time_result=FAIL
under_target idle_cpu_percent 3 && idle_result=PASS
under_target active_cpu_percent 5 && active_result=PASS
under_target key_reactivity_ms 40 && reactivity_result=PASS
under_target session_switch_ms 1200 && switching_result=PASS
under_target archive_ms 350 && archive_time_result=PASS
under_target restore_ms 2200 && restore_time_result=PASS
layout_result=FAIL
restore_result=FAIL
grid_result=FAIL
all_equal layout_preserved 100 && layout_result=PASS
all_equal restore_integrity 100 && restore_result=PASS
all_equal cursor_count 1 && grid_result=PASS

{
    echo "# TUI Sidebar Controlled Baseline"
    echo
    echo "Generated: $generated_at"
    echo
    echo "Revision: \`$commit\` (dirty: \`$dirty\`)"
    echo
    echo "Environment: \`$tmux_version\`, attached urxvt client, 100x30 geometry"
    echo "Runs: $RUNS"
    echo
    echo "| Metric | Median and observed range | Result |"
    echo "| :--- | :--- | :---: |"
    echo "| Idle launcher CPU | $idle_cpu | $idle_result |"
    echo "| Idle launcher peak RSS | $idle_rss | PASS |"
    echo "| Active launcher CPU | $active_cpu | $active_result |"
    echo "| Active launcher peak RSS | $active_rss | PASS |"
    echo "| Key-to-render latency | $reactivity | $reactivity_result |"
    echo "| Enter-to-client-switch latency | $switching | $switching_result |"
    echo "| Archive completion | $archive_time | $archive_time_result |"
    echo "| Archive metadata size | $archive_size | PASS |"
    echo "| Restore completion | $restore_time | $restore_time_result |"
    echo "| Restore pane/window integrity | 100% required on every run | $restore_result |"
    echo "| Layout preserved after 3 open/close cycles | 100% required on every run | $layout_result |"
    echo "| Grid bounded and exactly one cursor | required on every run | $grid_result |"
    echo
    echo "## Method"
    echo
    echo "Each run creates a unique tmux socket, an attached urxvt client, and a temporary history directory. It executes the launcher from the checked-out repository, never the installed copy. CPU is interval CPU time from \`/proc/PID/stat\` (including reaped children), and RSS is peak launcher RSS sampled during the same interval. Timed operations have bounded completion checks; a timeout or invariant mismatch fails the suite instead of becoming a numeric baseline."
    echo
    echo "The former active-vs-isolated comparison was removed because it changed the user's live tmux server and compared uncontrolled workloads. Use this report for before/after measurements under the same geometry and run count."
    echo
    echo "## Performance targets"
    echo
    echo "Targets are reported independently from functional invariants. v0.6.2 remains untagged until all absolute targets pass: idle <=3%, active <=5%, key <=40ms, switch <=1200ms, archive <=350ms, restore <=2200ms."
} | tee "$REPORT_FILE"

[ "$restore_result" = PASS ] && [ "$layout_result" = PASS ] && [ "$grid_result" = PASS ]
