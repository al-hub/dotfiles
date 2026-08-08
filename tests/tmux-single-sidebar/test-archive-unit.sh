#!/usr/bin/env bash
# Unit test for archive persistence service in scripts/lib/sidebar_archive.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_archive.sh"

tmp_file="/tmp/test_sidebar_archive_$$"
trap 'rm -f "$tmp_file"' EXIT

sidebar_archive_format_line "1700000000" "my_sess" "/tmp" "1" "0" "top" "80" "24" "0" "bash" "0" > "$tmp_file"
line="$(cat "$tmp_file")"

if ! sidebar_domain_validate_archive_line "$line"; then
    echo "FAIL: archive formatted line invalid"
    exit 1
fi

echo "PASS: archive unit tests"
