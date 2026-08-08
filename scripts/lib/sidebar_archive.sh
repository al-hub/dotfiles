#!/usr/bin/env bash
# Session Archive Serialization & File Service Module
set -euo pipefail

sidebar_archive_format_line() {
    local created="$1" session="$2" path="$3" window_count="$4" active_window="$5" layout="$6" width="$7" height="$8" active_pane="$9" cmd="${10}" flags="${11}"
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$created" "$session" "$path" "$window_count" "$active_window" "$layout" "$width" "$height" "$active_pane" "$cmd" "$flags"
}

sidebar_archive_save_atomic() {
    local target_file="$1" content="$2"
    local tmp_file="${target_file}.tmp.$$"
    printf '%s\n' "$content" > "$tmp_file"
    mv -f "$tmp_file" "$target_file"
}
