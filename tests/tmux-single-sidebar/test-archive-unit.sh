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

# 4. Test Pure Layout Calculations and CRC16 Checksum
sample_layout="5ee3,238x53,0,0,14"
pane_count="$(sidebar_archive_layout_pane_count "$sample_layout")"
[ "$pane_count" -eq 1 ] || { echo "FAIL: layout_pane_count expected 1 got $pane_count"; exit 1; }

body="$(sidebar_archive_layout_body "$sample_layout")"
[ "$body" = "238x53,0,0,14" ] || { echo "FAIL: layout_body expected 238x53,0,0,14 got $body"; exit 1; }

with_cs="$(sidebar_archive_layout_with_checksum "$body")"
[ "$with_cs" = "$sample_layout" ] || { echo "FAIL: layout_with_checksum expected $sample_layout got $with_cs"; exit 1; }

multi_layout="b624,238x53,0,0[238x26,0,0,14,238x26,0,27,15]"
multi_count="$(sidebar_archive_layout_pane_count "$multi_layout")"
[ "$multi_count" -eq 2 ] || { echo "FAIL: multi_count expected 2 got $multi_count"; exit 1; }

recomputed="$(sidebar_archive_layout_with_pane_ids "$multi_layout" "99 100")"
[ "$(sidebar_archive_layout_pane_count "$recomputed")" -eq 2 ] || { echo "FAIL: recomputed count mismatch"; exit 1; }
[[ "$recomputed" == *",99,"* ]] || [[ "$recomputed" == *",99]"* ]] || { echo "FAIL: recomputed did not contain pane id 99: $recomputed"; exit 1; }

# 5. Test v3 TSV Archive Validation
v3_valid_tsv="$tmp_dir/v3_valid.tsv"
cat <<'EOF' > "$v3_valid_tsv"
version	3
session	test-sess
archived_at	1700000000
window	0	main	1	242e,238x53,0,0,14	0,0,238,53,1
pane	0	%14	0	0	238	53	1	/tmp	bash	work
endwindow
created	1700000000
EOF

sidebar_archive_validate_file "$v3_valid_tsv" || { echo "FAIL: v3_valid_tsv failed validation"; exit 1; }

# Test malformed v3 (missing endwindow)
v3_invalid_tsv="$tmp_dir/v3_invalid.tsv"
cat <<'EOF' > "$v3_invalid_tsv"
version	3
session	test-sess
archived_at	1700000000
window	0	main	1	242e,238x53,0,0,14	0,0,238,53,1
pane	0	%14	0	0	238	53	1	/tmp	bash	work
created	1700000000
EOF

! sidebar_archive_validate_file "$v3_invalid_tsv" || { echo "FAIL: v3_invalid_tsv unexpectedly passed validation"; exit 1; }

# 6. Test v1/v2 Backward Compatibility
v1_valid_tsv="$tmp_dir/v1_valid.tsv"
cat <<'EOF' > "$v1_valid_tsv"
version	1
session	v1-sess
window	0	main	1	layout	0,0,80,24,1
pane	0	%1	0	0	80	24	1	/tmp	bash
endwindow
created	1600000000
EOF

sidebar_archive_validate_file "$v1_valid_tsv" || { echo "FAIL: v1_valid_tsv failed validation"; exit 1; }

echo "PASS: archive unit tests"
