#!/usr/bin/env bash
# Session Archive Serialization & File Service Module
set -euo pipefail

sidebar_archive_format_line() {
    local created="${1:-}" session="${2:-}" path="${3:-}" window_count="${4:-}" active_window="${5:-}" layout="${6:-}" width="${7:-}" height="${8:-}" active_pane="${9:-}" cmd="${10:-}" flags="${11:-}"
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$created" "$session" "$path" "$window_count" "$active_window" "$layout" "$width" "$height" "$active_pane" "$cmd" "$flags"
}

sidebar_archive_save_atomic() {
    local target_file="${1:-}" content="${2:-}"
    [ -n "$target_file" ] || return 1
    local target_dir
    target_dir="$(dirname "$target_file")"
    if [ ! -d "$target_dir" ]; then
        mkdir -p "$target_dir"
    fi
    local tmp_file="${target_file}.tmp.$$"
    printf '%s\n' "$content" > "$tmp_file"
    mv -f "$tmp_file" "$target_file"
}

sidebar_archive_validate_path() {
    local archive_path="${1:-}"
    [ -n "$archive_path" ] && [ -r "$archive_path" ] && [ -s "$archive_path" ]
}

sidebar_archive_set_batch_busy() {
    local val="${1:-1}"
    if command -v tmux >/dev/null 2>&1; then
        tmux set-option -gq "@tmux_batch_busy" "$val" 2>/dev/null || true
        tmux set-option -gq "@dotfiles_sidebar_restore_topology" "$val" 2>/dev/null || true
    fi
}

sidebar_archive_is_batch_busy() {
    if command -v tmux >/dev/null 2>&1; then
        [ "$(tmux show-option -gqv "@tmux_batch_busy" 2>/dev/null || true)" = "1" ] || \
        [ "$(tmux show-option -gqv "@dotfiles_sidebar_restore_topology" 2>/dev/null || true)" = "1" ]
    else
        return 1
    fi
}

sidebar_archive_mark_window_lazy() {
    local window_target="${1:-}"
    [ -n "$window_target" ] || return 0
    if command -v tmux >/dev/null 2>&1; then
        tmux set-option -wq -t "$window_target" "@dotfiles_sidebar_managed" 1 2>/dev/null || true
        tmux set-option -wq -t "$window_target" "@dotfiles_sidebar_ready" 0 2>/dev/null || true
        tmux set-option -wq -t "$window_target" "@dotfiles_sidebar_provisioning" "lazy" 2>/dev/null || true
    fi
}

# --- Pure Layout Calculations & Checksums ---

sidebar_archive_layout_pane_count()
{
    local layout="$1"
    printf '%s\n' "$layout" |
        awk '{
            count = 0
            while (match($0, /[0-9]+x[0-9]+,[0-9]+,[0-9]+,[0-9]+/)) {
                count++
                $0 = substr($0, RSTART + RLENGTH)
            }
            print count
        }'
}

sidebar_archive_layout_body()
{
    local layout="$1"
    case "$layout" in
        [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F],*) printf '%s\n' "${layout#*,}" ;;
        *) printf '%s\n' "$layout" ;;
    esac
}

sidebar_archive_layout_with_checksum()
{
    local body="$1"
    local checksum=0
    local bytes byte
    bytes="$(printf '%s' "$body" | od -An -tu1 -v)"

    for byte in $bytes; do
        checksum=$((((checksum >> 1) | ((checksum & 1) << 15))))
        checksum=$(((checksum + byte) & 65535))
    done

    printf '%04x,%s\n' "$checksum" "$body"
}

sidebar_archive_layout_with_pane_ids()
{
    local layout="$1"
    local pane_ids="$2"
    local body replaced

    body="$(sidebar_archive_layout_body "$layout")"
    replaced="$(
        printf '%s\n' "$body" |
        awk -v pane_ids="$pane_ids" '
            BEGIN {
                split(pane_ids, ids, " ")
                pane_index = 1
            }
            {
                output = ""
                rest = $0
                while (match(rest, /[0-9]+x[0-9]+,[0-9]+,[0-9]+,[0-9]+/)) {
                    token = substr(rest, RSTART, RLENGTH)
                    replacement = token
                    if (ids[pane_index] != "") {
                        sub(/,[0-9]+$/, "," ids[pane_index], replacement)
                    }
                    output = output substr(rest, 1, RSTART - 1) replacement
                    rest = substr(rest, RSTART + RLENGTH)
                    pane_index++
                }
                print output rest
            }'
    )"

    sidebar_archive_layout_with_checksum "$replaced"
}

# --- Pure Archive Validation (v1, v2, v3) ---

sidebar_archive_validate_file()
{
    local archive_path_value="$1"
    [ -s "$archive_path_value" ] || return 1
    local version="" session_found=0 windows=0 panes=0 ends=0 valid=1
    local record f1 f2 f3 f4 f5 f6 f7 f8 f9 f10
    while IFS=$'\t' read -r record f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 || [ -n "$record" ]; do
        case "$record" in
            version) version="$f1" ;;
            session) [ -n "$f1" ] && session_found=1 ;;
            window)
                windows=$((windows + 1))
                [ -n "$f4" ] || valid=0
                ;;
            pane)
                panes=$((panes + 1))
                if [ "$version" = "2" ] || [ "$version" = "3" ]; then
                    [ -n "$f9" ] || valid=0
                else
                    [ -n "$f2" ] || valid=0
                fi
                ;;
            endwindow) ends=$((ends + 1)) ;;
        esac
    done < "$archive_path_value"

    [ "$version" = "1" ] || [ "$version" = "2" ] || [ "$version" = "3" ] || valid=0
    [ "$session_found" -eq 1 ] || valid=0
    [ "$windows" -gt 0 ] || valid=0
    [ "$panes" -gt 0 ] || valid=0
    [ "$windows" -eq "$ends" ] || valid=0
    [ "$valid" -eq 1 ]
}



