#!/usr/bin/env bash
# Unit tests for sidebar_domain_animation.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source pure domain animation module
source "$REPO_ROOT/scripts/lib/sidebar_domain_animation.sh"

fail_count=0
pass_count=0

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    if [ "$expected" != "$actual" ]; then
        printf 'FAIL: %s (expected: [%s], got: [%s])\n' "$msg" "$expected" "$actual" >&2
        fail_count=$((fail_count + 1))
    else
        printf 'PASS: %s\n' "$msg"
        pass_count=$((pass_count + 1))
    fi
}

assert_true() {
    local condition="$1"
    local msg="$2"
    if [ "$condition" != "0" ]; then
        printf 'FAIL: %s\n' "$msg" >&2
        fail_count=$((fail_count + 1))
    else
        printf 'PASS: %s\n' "$msg"
        pass_count=$((pass_count + 1))
    fi
}

echo "=== Running Animation LUT Unit Tests ==="

# Test 1: Build 24 distinct deterministic frames
sidebar_domain_animation_build_lut "sess1" "my-session" 20 0
frame_0="$(sidebar_domain_animation_get_cell "sess1" 0)"
frame_1="$(sidebar_domain_animation_get_cell "sess1" 1)"
frame_23="$(sidebar_domain_animation_get_cell "sess1" 23)"

assert_true "$([ -n "$frame_0" ] && [ -n "$frame_1" ]; echo $?)" "Frames are non-empty"
assert_true "$([ "$frame_0" != "$frame_1" ]; echo $?)" "Adjacent frames 0 and 1 have distinct phase coloring"
assert_true "$([ "$frame_0" != "$frame_23" ]; echo $?)" "Frames 0 and 23 have distinct phase coloring"

# Test 2: O(1) lookup returns exact pre-rendered ANSI string
frame_0_repeat="$(sidebar_domain_animation_get_cell "sess1" 0)"
assert_eq "$frame_0" "$frame_0_repeat" "LUT lookup is deterministic and identical"

# Test 3: Seed offset isolation
sidebar_domain_animation_build_lut "sess2" "my-session" 20 5
frame_0_seed5="$(sidebar_domain_animation_get_cell "sess2" 0)"
assert_true "$([ "$frame_0" != "$frame_0_seed5" ]; echo $?)" "Different seed produces shifted phase colors"

# Test 4: CJK / Hangul and Emoji cell width safety
# "세션-1" has 4 characters: '세'(2 cells), '션'(2 cells), '-'(1 cell), '1'(1 cell) = 6 visual cells
cell_w="$(sidebar_domain_animation_measure_cell_width "세션-1")"
assert_eq "6" "$cell_w" "Hangul '세션-1' visual cell width measured accurately as 6"

# "🚀ai-worker" has 10 characters: '🚀'(2 cells), 'a','i','-','w','o','r','k','e','r' (9 cells) = 11 visual cells
cell_w_worker="$(sidebar_domain_animation_measure_cell_width "🚀ai-worker")"
assert_eq "11" "$cell_w_worker" "Emoji '🚀ai-worker' visual cell width measured accurately as 11"

# "🚀ai" has 3 characters: '🚀'(2 cells), 'a'(1 cell), 'i'(1 cell) = 4 visual cells
cell_w_emoji="$(sidebar_domain_animation_measure_cell_width "🚀ai")"
assert_eq "4" "$cell_w_emoji" "Emoji '🚀ai' visual cell width measured accurately as 4"

# Fitting tests (wide-character safety without UTF-8 boundary slicing)
# "세션-1" fitting in max 3 cells must cut after '세' (2 cells) and not slice '션' (2 cells)
fitted_ko="$(sidebar_domain_animation_fit_cell_width "세션-1" 3)"
assert_eq "세" "$fitted_ko" "fit_cell_width does not slice 2-cell Hangul mid-glyph"

fitted_emoji="$(sidebar_domain_animation_fit_cell_width "🚀ai-worker" 4)"
assert_eq "🚀ai" "$fitted_emoji" "fit_cell_width does not slice 2-cell Emoji mid-glyph"

fitted_emoji_5="$(sidebar_domain_animation_fit_cell_width "🚀ai-worker" 5)"
assert_eq "🚀ai-" "$fitted_emoji_5" "fit_cell_width fits exact 5 cells for emoji prefix"

# Building LUT for Hangul session name
sidebar_domain_animation_build_lut "sess_ko" "세션-1" 10 0
frame_ko="$(sidebar_domain_animation_get_cell "sess_ko" 0)"
assert_true "$([ -n "$frame_ko" ]; echo $?)" "Hangul LUT frame compiled cleanly without UTF-8 error"

# Building LUT for Emoji session name
sidebar_domain_animation_build_lut "sess_emoji" "🚀ai-worker" 15 0
frame_emoji="$(sidebar_domain_animation_get_cell "sess_emoji" 0)"
assert_true "$([ -n "$frame_emoji" ]; echo $?)" "Emoji LUT frame compiled cleanly without UTF-8 error"

# Fast-path nameref cell lookup test
ref_cell=""
sidebar_domain_animation_get_cell ref_cell "sess_emoji" 0
assert_eq "$frame_emoji" "$ref_cell" "Nameref get_cell returns exact identical pre-rendered frame"

# Test 5: Adaptive dynamic timeout resolution
to_active="$(sidebar_domain_animation_resolve_timeout 2 0 false)"
assert_eq "0.033" "$to_active" "Timeout is 0.033s (30 FPS) when active > 0"

to_cooldown="$(sidebar_domain_animation_resolve_timeout 0 0 true)"
assert_eq "0.100" "$to_cooldown" "Timeout is 0.100s (10 FPS) during cooldown decay"

to_idle="$(sidebar_domain_animation_resolve_timeout 0 5 false)"
assert_eq "1.0" "$to_idle" "Timeout is 1.0s (0% CPU sleep) when quiescent idle"

# Test 6: Invalidation
sidebar_domain_animation_invalidate "sess1"
frame_after_invalidation="$(sidebar_domain_animation_get_cell "sess1" 0)"
assert_eq "" "$frame_after_invalidation" "Invalidation completely clears cached frames for session"

if [ "$fail_count" -gt 0 ]; then
    echo "FAILED: $fail_count tests failed"
    exit 1
fi

echo "=== All $pass_count Animation LUT Unit Tests Passed ==="
