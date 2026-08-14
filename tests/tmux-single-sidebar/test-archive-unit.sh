#!/usr/bin/env bash
# Unit test for archive persistence service in scripts/lib/sidebar_archive.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/sidebar_domain.sh"
source "$SCRIPT_DIR/scripts/lib/sidebar_archive.sh"

tmp_dir="/tmp/test_sidebar_archive_$$"
mkdir -p "$tmp_dir"
trap 'rm -rf "$tmp_dir"' EXIT

tmp_file="$tmp_dir/archive.txt"

# 1. Test sidebar_archive_format_line
formatted="$(sidebar_archive_format_line "1700000000" "my_sess" "/tmp" "1" "0" "top" "80" "24" "0" "bash" "0")"
expected="1700000000|my_sess|/tmp|1|0|top|80|24|0|bash|0"
[ "$formatted" = "$expected" ] || { echo "FAIL: archive format_line output mismatch: got '$formatted'"; exit 1; }

if ! sidebar_domain_validate_archive_line "$formatted"; then
    echo "FAIL: archive formatted line invalid by domain validation"
    exit 1
fi

# 2. Test sidebar_archive_save_atomic
sidebar_archive_save_atomic "$tmp_file" "$formatted"
[ -f "$tmp_file" ] || { echo "FAIL: atomic save file does not exist"; exit 1; }
saved_content="$(cat "$tmp_file")"
[ "$saved_content" = "$formatted" ] || { echo "FAIL: atomic saved content mismatch"; exit 1; }

# Overwrite atomically
sidebar_archive_save_atomic "$tmp_file" "new_content"
[ "$(cat "$tmp_file")" = "new_content" ] || { echo "FAIL: atomic save overwrite failed"; exit 1; }

# Verify atomic save creates nested target directory if missing
nested_file="$tmp_dir/sub/dir/nested_archive.txt"
sidebar_archive_save_atomic "$nested_file" "nested_content"
[ -f "$nested_file" ] || { echo "FAIL: atomic save did not create nested directory/file"; exit 1; }
[ "$(cat "$nested_file")" = "nested_content" ] || { echo "FAIL: nested content mismatch"; exit 1; }

# Verify no tmp files leftover
tmp_leftovers="$(find "$tmp_dir" -name "*.tmp.*" 2>/dev/null || true)"
[ -z "$tmp_leftovers" ] || { echo "FAIL: tmp files leftover: $tmp_leftovers"; exit 1; }

# 3. Test sidebar_archive_validate_path
sidebar_archive_validate_path "$tmp_file" || { echo "FAIL: validate_path expected true for valid file"; exit 1; }

empty_file="$tmp_dir/empty.txt"
touch "$empty_file"
! sidebar_archive_validate_path "$empty_file" || { echo "FAIL: validate_path expected false for empty file"; exit 1; }

! sidebar_archive_validate_path "$tmp_dir/nonexistent.txt" || { echo "FAIL: validate_path expected false for nonexistent file"; exit 1; }
! sidebar_archive_validate_path "" || { echo "FAIL: validate_path expected false for empty string path"; exit 1; }

echo "PASS: archive unit tests"
