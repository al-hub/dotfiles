#!/usr/bin/env bash
# Unit tests for pure domain helpers in scripts/lib/sidebar_domain.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"

# 1. Test name sanitization
res="$(sidebar_domain_sanitize_name "my session:name.test")"
[ "$res" = "my_session_name_test" ] || { echo "FAIL: sanitize_name expected 'my_session_name_test', got '$res'"; exit 1; }

res="$(sidebar_domain_sanitize_name "plain_name")"
[ "$res" = "plain_name" ] || { echo "FAIL: sanitize_name plain expected 'plain_name', got '$res'"; exit 1; }

res="$(sidebar_domain_sanitize_name "a:b.c d")"
[ "$res" = "a_b_c_d" ] || { echo "FAIL: sanitize_name expected 'a_b_c_d', got '$res'"; exit 1; }

# 2. Test archive line validation
line="1700000000|test_session|/path|1|0|top|80|24|0|bash|0"
if ! sidebar_domain_validate_archive_line "$line"; then
    echo "FAIL: valid archive line rejected"
    exit 1
fi

empty_cmd_line="1700000000|test_session|/path|1|0|top|80|24|0||0"
if ! sidebar_domain_validate_archive_line "$empty_cmd_line"; then
    echo "FAIL: valid archive line with empty cmd rejected"
    exit 1
fi

invalid_line="invalid_line_format"
if sidebar_domain_validate_archive_line "$invalid_line"; then
    echo "FAIL: invalid archive line accepted"
    exit 1
fi

short_line="1700000000|test_session|/path"
if sidebar_domain_validate_archive_line "$short_line"; then
    echo "FAIL: short archive line accepted"
    exit 1
fi

# 3. Test epoch now
epoch="$(sidebar_domain_epoch_now)"
[[ "$epoch" =~ ^[0-9]+$ ]] || { echo "FAIL: epoch_now expected numeric string, got '$epoch'"; exit 1; }
[ "$epoch" -gt 1500000000 ] || { echo "FAIL: epoch_now timestamp too small: '$epoch'"; exit 1; }

# 4. Test format duration
dur="$(sidebar_domain_format_duration 0)"
[ "$dur" = "0:00:00:00" ] || { echo "FAIL: format_duration 0 expected '0:00:00:00', got '$dur'"; exit 1; }

dur="$(sidebar_domain_format_duration 59)"
[ "$dur" = "0:00:00:59" ] || { echo "FAIL: format_duration 59 expected '0:00:00:59', got '$dur'"; exit 1; }

dur="$(sidebar_domain_format_duration 3661)"
[ "$dur" = "0:01:01:01" ] || { echo "FAIL: format_duration 3661 expected '0:01:01:01', got '$dur'"; exit 1; }

dur="$(sidebar_domain_format_duration 90061)"
[ "$dur" = "1:01:01:01" ] || { echo "FAIL: format_duration 90061 expected '1:01:01:01', got '$dur'"; exit 1; }

dur="$(sidebar_domain_format_duration "invalid")"
[ "$dur" = "0:00:00:00" ] || { echo "FAIL: format_duration invalid expected '0:00:00:00', got '$dur'"; exit 1; }

# 5. Test session age value
now="$(sidebar_domain_epoch_now)"
created=$((now - 3661))
age_val=""
sidebar_domain_session_age_value age_val "$created"
[ "$age_val" = "0:01:01:01" ] || { echo "FAIL: session_age_value expected '0:01:01:01', got '$age_val'"; exit 1; }

age_val=""
sidebar_domain_session_age_value age_val "invalid_created"
[ "$age_val" = "0:00:00:00" ] || { echo "FAIL: session_age_value invalid expected '0:00:00:00', got '$age_val'"; exit 1; }

age_val=""
sidebar_domain_session_age_value age_val $((now + 100))
[ "$age_val" = "0:00:00:00" ] || { echo "FAIL: session_age_value future expected '0:00:00:00', got '$age_val'"; exit 1; }

# 6. Test layout body extraction
body="$(sidebar_domain_layout_body "c01a,158x40,0,0,0")"
[ "$body" = "158x40,0,0,0" ] || { echo "FAIL: layout_body with checksum expected '158x40,0,0,0', got '$body'"; exit 1; }

body="$(sidebar_domain_layout_body "1234,80x24,0,0,0")"
[ "$body" = "80x24,0,0,0" ] || { echo "FAIL: layout_body with hex checksum expected '80x24,0,0,0', got '$body'"; exit 1; }

body="$(sidebar_domain_layout_body "80x24,0,0,0")"
[ "$body" = "80x24,0,0,0" ] || { echo "FAIL: layout_body without checksum expected '80x24,0,0,0', got '$body'"; exit 1; }

echo "PASS: domain unit tests"

