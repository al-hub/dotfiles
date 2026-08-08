#!/usr/bin/env bash
# Pure domain helpers for tmux-session-launcher with zero external side-effects or CLI dependencies
set -euo pipefail

sidebar_domain_sanitize_name() {
    local raw="$1"
    local clean="${raw//[:. ]/_}"
    echo "$clean"
}

sidebar_domain_validate_archive_line() {
    local line="$1"
    [[ "$line" =~ ^[0-9]+\|[^|]+\|[^|]+\|[0-9]+\|[0-9]+\|[^|]+\|[0-9]+\|[0-9]+\|[0-9]+\|[^|]+\|[0-9]+$ ]]
}

sidebar_domain_calc_render_diff() {
    local old_signature="$1" new_signature="$2"
    if [ "$old_signature" = "$new_signature" ]; then
        echo "0"
    else
        echo "1"
    fi
}
