#!/usr/bin/env bash
# Pure domain animation and Look-Up Table (LUT) waveform engine for tmux-session-launcher
# Zero external CLI dependencies, zero side-effects, fully unit testable
set -euo pipefail

declare -gA _SIDEBAR_ANIM_LUT=()

sidebar_domain_animation_char_width() {
    local c="${1:-}"
    case "$c" in
        [\ -~]|$'\t'|"")
            printf '1\n'
            return 0
            ;;
    esac

    # CJK, Hangul, Fullwidth, Ideographs, Emoji, Symbols
    if [[ "$c" == [ᄀ-ᇿ⺀-꓏가-힣豈-﫿！-｠￠-￦] ]] || \
       [[ "$c" == [☀-➿㈀-㋿] ]] || \
       [[ "$c" == [🀀-🫿𠀀-㓟] ]] || \
       [[ "$c" == [🌀-🿽] ]]; then
        printf '2\n'
        return 0
    fi
    printf '1\n'
}

sidebar_domain_animation_measure_cell_width() {
    local text="${1:-}"
    local total=0
    local len="${#text}"
    local i char w
    for ((i = 0; i < len; i++)); do
        char="${text:i:1}"
        case "$char" in
            [\ -~]|$'\t'|"") w=1 ;;
            *)
                if [[ "$char" == [ᄀ-ᇿ⺀-꓏가-힣豈-﫿！-｠￠-￦] ]] || \
                   [[ "$char" == [☀-➿㈀-㋿] ]] || \
                   [[ "$char" == [🀀-🫿𠀀-㓟] ]] || \
                   [[ "$char" == [🌀-🿽] ]]; then
                    w=2
                else
                    w=1
                fi
                ;;
        esac
        total=$((total + w))
    done
    printf '%d\n' "$total"
}

sidebar_domain_animation_fit_cell_width() {
    local text="${1:-}"
    local max_cells="${2:-30}"
    local out=""
    local cur_cells=0
    local len="${#text}"
    local i char w
    for ((i = 0; i < len; i++)); do
        char="${text:i:1}"
        case "$char" in
            [\ -~]|$'\t'|"") w=1 ;;
            *)
                if [[ "$char" == [ᄀ-ᇿ⺀-꓏가-힣豈-﫿！-｠￠-￦] ]] || \
                   [[ "$char" == [☀-➿㈀-㋿] ]] || \
                   [[ "$char" == [🀀-🫿𠀀-㓟] ]] || \
                   [[ "$char" == [🌀-🿽] ]]; then
                    w=2
                else
                    w=1
                fi
                ;;
        esac
        if [ $((cur_cells + w)) -gt "$max_cells" ]; then
            break
        fi
        out+="$char"
        cur_cells=$((cur_cells + w))
    done
    printf '%s\n' "$out"
}

sidebar_domain_animation_build_lut() {
    local sess_id name max_cells seed
    if [ "$#" -le 3 ]; then
        sess_id="$1"
        name="$1"
        max_cells="${2:-20}"
        seed="${3:-0}"
    else
        sess_id="$1"
        name="$2"
        max_cells="${3:-20}"
        seed="${4:-0}"
    fi

    [ "$max_cells" -lt 1 ] && max_cells=1
    local fitted_name
    fitted_name="$(sidebar_domain_animation_fit_cell_width "$name" "$max_cells")"
    local visual_width
    visual_width="$(sidebar_domain_animation_measure_cell_width "$fitted_name")"
    local padding_len=$((max_cells - visual_width))
    local padding_str=""
    if [ "$padding_len" -gt 0 ]; then
        printf -v padding_str '%*s' "$padding_len" ''
    fi

    local -a palette=(
        255 254 252 250 248 246 241 241
        241 241 241 241 241 241 241 241
        241 241 241 241 241 241 241 241
    )

    local char_count="${#fitted_name}"
    local f i char phase color frame_str

    for ((f = 0; f < 24; f++)); do
        frame_str=""
        for ((i = 0; i < char_count; i++)); do
            char="${fitted_name:i:1}"
            phase=$(( ((i - f + seed) % 24 + 24) % 24 ))
            color="${palette[$phase]:-241}"
            frame_str+=$'\033[38;5;'"$color"'m'"$char"
        done
        frame_str+=$'\033[0m'
        [ -n "$padding_str" ] && frame_str+="$padding_str"
        _SIDEBAR_ANIM_LUT["${sess_id}:${f}"]="$frame_str"
    done
}

sidebar_domain_animation_get_cell() {
    if [ "$#" -ge 3 ]; then
        local -n _get_cell_out_ref="$1"
        local sess_id="$2"
        local frame_idx="${3:-0}"
        local frame_bounded=$(( ((frame_idx % 24) + 24) % 24 ))
        _get_cell_out_ref="${_SIDEBAR_ANIM_LUT["${sess_id}:${frame_bounded}"]:-}"
    else
        local sess_id="$1"
        local frame_idx="${2:-0}"
        local frame_bounded=$(( ((frame_idx % 24) + 24) % 24 ))
        printf '%s\n' "${_SIDEBAR_ANIM_LUT["${sess_id}:${frame_bounded}"]:-}"
    fi
}

sidebar_domain_animation_resolve_timeout() {
    local active_count="${1:-0}"
    local idle_seconds="${2:-0}"
    local cooldown_active="${3:-false}"

    case "$active_count" in
        ''|*[!0-9]*) active_count=0 ;;
    esac

    if [ "$active_count" -gt 0 ]; then
        # 30 FPS active wave (33.3ms)
        printf '0.033\n'
    elif [ "$cooldown_active" = "true" ]; then
        # 10 FPS decay cooldown (100ms)
        printf '0.100\n'
    else
        # True sleep / 1.0s quiescent idle
        printf '1.0\n'
    fi
}

sidebar_domain_animation_invalidate() {
    local sess_id="$1"
    local f
    for ((f = 0; f < 24; f++)); do
        unset '_SIDEBAR_ANIM_LUT["${sess_id}:${f}"]'
    done
}

sidebar_domain_animation_clear_all() {
    _SIDEBAR_ANIM_LUT=()
}
