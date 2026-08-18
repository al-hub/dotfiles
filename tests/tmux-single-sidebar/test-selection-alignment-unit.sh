#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

# Source the coordinator module
source "$REPO_ROOT/scripts/lib/sidebar_coordinator.sh"

# Setup test state
session_names=("0" "aaa" "bbb" "ccc")
selected_session=""
selected_index=-1

# Case 1: Align to "bbb" -> index 2
selection_coordinator_align_current "bbb"
if [ "$selected_session" != "bbb" ] || [ "$selected_index" -ne 2 ]; then
    printf 'FAIL: expected selected_session="bbb", selected_index=2; got session="%s", index=%s\n' "$selected_session" "$selected_index" >&2
    exit 1
fi
printf 'PASS: selection_coordinator_align_current "bbb" -> index 2\n'

# Case 2: Align to "0" -> index 0 (handling numeric session correctly)
selection_coordinator_align_current "0"
if [ "$selected_session" != "0" ] || [ "$selected_index" -ne 0 ]; then
    printf 'FAIL: expected selected_session="0", selected_index=0; got session="%s", index=%s\n' "$selected_session" "$selected_index" >&2
    exit 1
fi
printf 'PASS: selection_coordinator_align_current "0" -> index 0\n'

# Case 3: Align to non-existent session -> fallback selected_index=0, selected_session="0"
selection_coordinator_align_current "non-existent"
if [ "$selected_index" -ne 0 ] || [ "$selected_session" != "0" ]; then
    printf 'FAIL: expected selected_index=0, selected_session="0" for non-existent session; got session="%s", index=%s\n' "$selected_session" "$selected_index" >&2
    exit 1
fi
printf 'PASS: selection_coordinator_align_current "non-existent" -> fallback index 0\n'

# Case 4: Single item array
session_names=("only_session")
selected_session=""
selected_index=-1
selection_coordinator_align_current "only_session"
if [ "$selected_session" != "only_session" ] || [ "$selected_index" -ne 0 ]; then
    printf 'FAIL: expected selected_session="only_session", selected_index=0; got session="%s", index=%s\n' "$selected_session" "$selected_index" >&2
    exit 1
fi
selection_coordinator_align_current "other_session"
if [ "$selected_session" != "only_session" ] || [ "$selected_index" -ne 0 ]; then
    printf 'FAIL: single item fallback expected session="only_session", index=0; got session="%s", index=%s\n' "$selected_session" "$selected_index" >&2
    exit 1
fi
printf 'PASS: selection_coordinator_align_current single item array\n'

# Case 5: Empty array
session_names=()
selected_session="stale"
selected_index=5
selection_coordinator_align_current "some_target"
if [ "$selected_session" != "" ] || [ "$selected_index" -ne -1 ]; then
    printf 'FAIL: empty array expected session="", index=-1; got session="%s", index=%s\n' "$selected_session" "$selected_index" >&2
    exit 1
fi
selection_coordinator_align_current ""
if [ "$selected_session" != "" ] || [ "$selected_index" -ne -1 ]; then
    printf 'FAIL: empty array empty target expected session="", index=-1; got session="%s", index=%s\n' "$selected_session" "$selected_index" >&2
    exit 1
fi
printf 'PASS: selection_coordinator_align_current empty array edge cases\n'

# Case 6: Empty target with pre-existing valid selected_session
session_names=("x" "y" "z")
selected_session="y"
selected_index=-1
selection_coordinator_align_current ""
if [ "$selected_session" != "y" ] || [ "$selected_index" -ne 1 ]; then
    printf 'FAIL: empty target with existing selection expected session="y", index=1; got session="%s", index=%s\n' "$selected_session" "$selected_index" >&2
    exit 1
fi
printf 'PASS: selection_coordinator_align_current empty target with valid selection\n'

# ==============================================================================
# selection_coordinator_compute_delta unit tests
# ==============================================================================

# Test Delta Case 1: 4 distinct indices
mapfile -t delta_res < <(selection_coordinator_compute_delta 0 1 2 3)
if [ "${#delta_res[@]}" -ne 4 ] || [ "${delta_res[*]}" != "0 1 2 3" ]; then
    printf 'FAIL: compute_delta distinct indices expected "0 1 2 3"; got "%s"\n' "${delta_res[*]}" >&2
    exit 1
fi
printf 'PASS: selection_coordinator_compute_delta 4 distinct indices\n'

# Test Delta Case 2: Overlapping duplicate indices
mapfile -t delta_res < <(selection_coordinator_compute_delta 1 2 1 2)
if [ "${#delta_res[@]}" -ne 2 ] || [ "${delta_res[*]}" != "1 2" ]; then
    printf 'FAIL: compute_delta duplicates expected "1 2"; got "%s"\n' "${delta_res[*]}" >&2
    exit 1
fi
printf 'PASS: selection_coordinator_compute_delta overlapping duplicates\n'

# Test Delta Case 3: All same indices
mapfile -t delta_res < <(selection_coordinator_compute_delta 0 0 0 0)
if [ "${#delta_res[@]}" -ne 1 ] || [ "${delta_res[*]}" != "0" ]; then
    printf 'FAIL: compute_delta all same expected "0"; got "%s"\n' "${delta_res[*]}" >&2
    exit 1
fi
printf 'PASS: selection_coordinator_compute_delta all same indices\n'

# Test Delta Case 4: Non-numeric and empty values
mapfile -t delta_res < <(selection_coordinator_compute_delta "" "invalid" 3 "-1" "4")
if [ "${#delta_res[@]}" -ne 2 ] || [ "${delta_res[*]}" != "3 4" ]; then
    printf 'FAIL: compute_delta invalid inputs expected "3 4"; got "%s"\n' "${delta_res[*]}" >&2
    exit 1
fi
printf 'PASS: selection_coordinator_compute_delta filters invalid values\n'

# Test Delta Case 5: Empty inputs
mapfile -t delta_res < <(selection_coordinator_compute_delta "" "" "" "")
if [ "${#delta_res[@]}" -ne 0 ]; then
    printf 'FAIL: compute_delta empty inputs expected 0 elements; got %d ("%s")\n' "${#delta_res[@]}" "${delta_res[*]}" >&2
    exit 1
fi
printf 'PASS: selection_coordinator_compute_delta empty inputs\n'

# Test Delta Case 6: Numeric 0 preserved properly
mapfile -t delta_res < <(selection_coordinator_compute_delta 0 1 0 "")
if [ "${#delta_res[@]}" -ne 2 ] || [ "${delta_res[*]}" != "0 1" ]; then
    printf 'FAIL: compute_delta numeric 0 expected "0 1"; got "%s"\n' "${delta_res[*]}" >&2
    exit 1
fi
printf 'PASS: selection_coordinator_compute_delta preserves numeric 0\n'

printf 'ALL SELECTION ALIGNMENT UNIT TESTS PASSED\n'
