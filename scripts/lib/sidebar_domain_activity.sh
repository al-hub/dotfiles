#!/usr/bin/env bash
# Pure domain activity observer and state machine engine for tmux-session-launcher
# Zero tmux server dependency, zero I/O side-effects, fully unit testable

declare -gA _SIDEBAR_ACTIVITY_PID=()
declare -gA _SIDEBAR_ACTIVITY_CMD=()
declare -gA _SIDEBAR_ACTIVITY_SIG=()
declare -gA _SIDEBAR_ACTIVITY_STABLE_COUNT=()
declare -gA _SIDEBAR_ACTIVITY_STATE=()
declare -gA _SIDEBAR_ACTIVITY_ANIMATE=()

sidebar_domain_activity_parse_signature() {
    local raw="${1:-}"
    local act="0" hist="0" cy="0" cx="0"

    if [ -n "$raw" ]; then
        IFS=':' read -r act hist cy cx <<< "$raw"
    fi

    act="${act:-0}"
    hist="${hist:-0}"
    cy="${cy:-0}"
    cx="${cx:-0}"

    sig_act="$act"
    sig_hist="$hist"
    sig_cy="$cy"
    sig_cx="$cx"

    if [ "$#" -ge 5 ]; then
        local -n _ref_act="$2"
        local -n _ref_hist="$3"
        local -n _ref_cy="$4"
        local -n _ref_cx="$5"
        _ref_act="$act"
        _ref_hist="$hist"
        _ref_cy="$cy"
        _ref_cx="$cx"
    fi
}

sidebar_domain_activity_has_changed() {
    local prev_sig="${1:-}"
    local curr_sig="${2:-}"

    if [ -z "$prev_sig" ] && [ -z "$curr_sig" ]; then
        return 1
    fi

    if [ -z "$prev_sig" ] && [ -n "$curr_sig" ]; then
        return 0
    fi

    if [ "$prev_sig" != "$curr_sig" ]; then
        return 0
    fi

    return 1
}

sidebar_domain_activity_register_pid() {
    local session_name="${1:-}"
    local pid="${2:-}"
    local cmd="${3:-}"
    [ -n "$session_name" ] || return 1
    _SIDEBAR_ACTIVITY_PID["$session_name"]="$pid"
    _SIDEBAR_ACTIVITY_CMD["$session_name"]="$cmd"
    return 0
}

sidebar_domain_activity_evict_pid() {
    local session_name="${1:-}"
    [ -n "$session_name" ] || return 1
    unset '_SIDEBAR_ACTIVITY_PID["$session_name"]'
    unset '_SIDEBAR_ACTIVITY_CMD["$session_name"]'
    unset '_SIDEBAR_ACTIVITY_SIG["$session_name"]'
    unset '_SIDEBAR_ACTIVITY_STABLE_COUNT["$session_name"]'
    unset '_SIDEBAR_ACTIVITY_STATE["$session_name"]'
    unset '_SIDEBAR_ACTIVITY_ANIMATE["$session_name"]'
    return 0
}

sidebar_domain_activity_get_pid() {
    local session_name="${1:-}"
    printf '%s\n' "${_SIDEBAR_ACTIVITY_PID["$session_name"]:-}"
}

sidebar_domain_activity_is_tracked() {
    local session_name="${1:-}"
    [ -n "${_SIDEBAR_ACTIVITY_PID["$session_name"]:-}" ]
}

sidebar_domain_activity_is_pid_alive() {
    local pid="${1:-}"
    case "$pid" in
        ''|*[!0-9]*) return 1 ;;
        0) return 1 ;;
    esac

    if [ -d "/proc/$pid" ]; then
        return 0
    fi

    kill -0 "$pid" 2>/dev/null
}

sidebar_domain_activity_get_stable_count() {
    local session_name="${1:-}"
    printf '%s\n' "${_SIDEBAR_ACTIVITY_STABLE_COUNT["$session_name"]:-0}"
}

sidebar_domain_activity_get_state() {
    local session_name="${1:-}"
    printf '%s\n' "${_SIDEBAR_ACTIVITY_STATE["$session_name"]:-idle}"
}

sidebar_domain_activity_get_animate() {
    local session_name="${1:-}"
    printf '%s\n' "${_SIDEBAR_ACTIVITY_ANIMATE["$session_name"]:-false}"
}

sidebar_domain_activity_evaluate_state() {
    local has_namerefs=false
    local out_state_var="" out_anim_var=""
    local session_name="" curr_sig="" pid=""

    if [ "$#" -ge 4 ]; then
        has_namerefs=true
        out_state_var="$1"
        out_anim_var="$2"
        session_name="$3"
        curr_sig="$4"
        pid="${5:-${_SIDEBAR_ACTIVITY_PID["$session_name"]:-}}"
    else
        session_name="${1:-}"
        curr_sig="${2:-}"
        pid="${3:-${_SIDEBAR_ACTIVITY_PID["$session_name"]:-}}"
    fi

    local state="idle"
    local animate="false"

    if [ -z "$session_name" ]; then
        state="idle"
        animate="false"
    elif ! sidebar_domain_activity_is_pid_alive "$pid"; then
        state="idle"
        animate="false"
        _SIDEBAR_ACTIVITY_STABLE_COUNT["$session_name"]=0
        _SIDEBAR_ACTIVITY_SIG["$session_name"]="$curr_sig"
    else
        local prev_sig="${_SIDEBAR_ACTIVITY_SIG["$session_name"]:-}"
        if [ -z "$prev_sig" ] || [ "$curr_sig" != "$prev_sig" ]; then
            # Signature changed and PID is alive
            state="active"
            animate="true"
            _SIDEBAR_ACTIVITY_STABLE_COUNT["$session_name"]=0
            _SIDEBAR_ACTIVITY_SIG["$session_name"]="$curr_sig"
        else
            # Signature unchanged and PID is alive
            local stable_count=$(( ${_SIDEBAR_ACTIVITY_STABLE_COUNT["$session_name"]:-0} + 1 ))
            _SIDEBAR_ACTIVITY_STABLE_COUNT["$session_name"]="$stable_count"
            if [ "$stable_count" -ge 2 ]; then
                state="waiting"
                animate="false"
            else
                # Cycle 1 stable grace period
                state="active"
                animate="true"
            fi
        fi
    fi

    if [ -n "$session_name" ]; then
        _SIDEBAR_ACTIVITY_STATE["$session_name"]="$state"
        _SIDEBAR_ACTIVITY_ANIMATE["$session_name"]="$animate"
    fi

    eval_state="$state"
    eval_animate="$animate"

    if [ "$has_namerefs" = "true" ]; then
        local -n _eval_state_ref="$out_state_var"
        local -n _eval_anim_ref="$out_anim_var"
        _eval_state_ref="$state"
        _eval_anim_ref="$animate"
    fi
}

sidebar_domain_activity_resolve_active_count() {
    local count=0
    local sess_id
    for sess_id in "${!_SIDEBAR_ACTIVITY_STATE[@]}"; do
        if [ "${_SIDEBAR_ACTIVITY_STATE["$sess_id"]:-}" = "active" ]; then
            count=$((count + 1))
        fi
    done

    if [ "$#" -ge 1 ]; then
        local -n _out_count_ref="$1"
        _out_count_ref="$count"
    else
        printf '%d\n' "$count"
    fi
}

sidebar_domain_activity_reset_all() {
    _SIDEBAR_ACTIVITY_PID=()
    _SIDEBAR_ACTIVITY_CMD=()
    _SIDEBAR_ACTIVITY_SIG=()
    _SIDEBAR_ACTIVITY_STABLE_COUNT=()
    _SIDEBAR_ACTIVITY_STATE=()
    _SIDEBAR_ACTIVITY_ANIMATE=()
}

sidebar_domain_activity_clear_all() {
    sidebar_domain_activity_reset_all
}
