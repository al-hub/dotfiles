#!/usr/bin/env bash
# Unit tests for pure domain helpers in scripts/lib/sidebar_domain.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"

# Test name sanitization
res="$(sidebar_domain_sanitize_name "my session:name.test")"
[ "$res" = "my_session_name_test" ] || { echo "FAIL: sanitize_name expected 'my_session_name_test', got '$res'"; exit 1; }

# Test archive line validation
line="1700000000|test_session|/path|1|0|top|80|24|0|bash|0"
if ! sidebar_domain_validate_archive_line "$line"; then
    echo "FAIL: valid archive line rejected"
    exit 1
fi

invalid_line="invalid_line_format"
if sidebar_domain_validate_archive_line "$invalid_line"; then
    echo "FAIL: invalid archive line accepted"
    exit 1
fi

echo "PASS: domain unit tests"
