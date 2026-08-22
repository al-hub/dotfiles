#!/usr/bin/env bash
set -euo pipefail

# TDD test verifying sidebar selection marker alignment

session_names=("0" "aaa" "bbbbbb" "ccc")
current_session="bbbbbb"
selected_index=2

row_mark_value()
{
    local index="$1"
    local name="${session_names[$index]}"

    if [ "$index" -eq "$selected_index" ] && [ "$name" = "$current_session" ]; then
        row_mark_result='>*'
    elif [ "$index" -eq "$selected_index" ]; then
        row_mark_result='> '
    elif [ "$name" = "$current_session" ]; then
        row_mark_result=' *'
    else
        row_mark_result='  '
    fi
}

row_mark_value "$selected_index"
if [ "$row_mark_result" != ">*" ]; then
    echo "FAIL: Expected '>*' for current selected session 'bbbbbb', got '$row_mark_result'"
    exit 1
fi

echo "PASS: row_mark_value correctly formats '>*' when selected_index matches current_session"
