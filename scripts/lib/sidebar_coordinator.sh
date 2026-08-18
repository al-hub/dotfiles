#!/usr/bin/env bash
# Coordinator Event Bus & State Lifecycle Manager Module
set -euo pipefail

sidebar_coordinator_init() {
    local session_id="${1:-global}"
    echo "INIT_OK"
}

sidebar_coordinator_dispatch_event() {
    local event_type="$1" payload="$2"
    case "$event_type" in
        "SWITCH_REQUEST")
            echo "HANDLED_SWITCH"
            ;;
        "RESIZE_EVENT")
            echo "HANDLED_RESIZE"
            ;;
        *)
            echo "UNKNOWN_EVENT"
            ;;
    esac
}

selection_coordinator_align_current() {
    local target_curr="${1:-}"
    if [ "${#session_names[@]}" -eq 0 ]; then
        selected_session=""
        selected_index=-1
        return 0
    fi

    local candidate="${target_curr:-${selected_session:-${current_session:-}}}"
    local idx
    if [ -n "$candidate" ]; then
        for idx in "${!session_names[@]}"; do
            if [ "${session_names[$idx]}" = "$candidate" ]; then
                selected_session="${session_names[$idx]}"
                selected_index="$idx"
                return 0
            fi
        done
    fi

    # If candidate wasn't found, try current_session or selected_session
    if [ -n "${current_session:-}" ] && [ "${current_session:-}" != "$candidate" ]; then
        for idx in "${!session_names[@]}"; do
            if [ "${session_names[$idx]}" = "$current_session" ]; then
                selected_session="${session_names[$idx]}"
                selected_index="$idx"
                return 0
            fi
        done
    fi

    if [ -n "${selected_session:-}" ] && [ "${selected_session:-}" != "$candidate" ]; then
        for idx in "${!session_names[@]}"; do
            if [ "${session_names[$idx]}" = "$selected_session" ]; then
                selected_session="${session_names[$idx]}"
                selected_index="$idx"
                return 0
            fi
        done
    fi

    # Fallback to first session if not found or empty
    selected_session="${session_names[0]}"
    selected_index=0
}

selection_coordinator_compute_delta() {
    local -a changed_indexes=()
    local arg idx duplicate

    for arg in "$@"; do
        case "$arg" in
            ''|*[!0-9]*) continue ;;
        esac
        duplicate=false
        for idx in "${changed_indexes[@]}"; do
            if [ "$idx" -eq "$arg" ]; then
                duplicate=true
                break
            fi
        done
        if [ "$duplicate" = false ]; then
            changed_indexes+=("$arg")
        fi
    done

    if [ "${#changed_indexes[@]}" -gt 0 ]; then
        printf '%s\n' "${changed_indexes[@]}"
    fi
}
