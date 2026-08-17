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



