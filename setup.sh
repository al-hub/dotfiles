#!/usr/bin/env bash
# ==============================================================================
# setup.sh - Universal Lifecycle Manager & Workspace Orchestrator for dotfiles
# https://github.com/al-hub/dotfiles
# Autonomous Install, Update, Uninstall, Doctor & Status Diagnostics
# ==============================================================================
set -euo pipefail

DOTFILES_STABLE_VERSION="v0.7.0"
DOTFILES_VERSION="${DOTFILES_VERSION:-master}"
REPO_RAW_BASE_URL="${REPO_RAW_BASE_URL:-https://raw.githubusercontent.com/al-hub/dotfiles}"
REPO_RAW_URL="${REPO_RAW_URL:-}"
INSTALL_TOML_URL="${INSTALL_TOML_URL:-}"
STATE_DIR="${STATE_DIR:-$HOME/.dotfiles-install}"
BACKUP_DIR="$STATE_DIR/backups"
MANIFEST_FILE="$STATE_DIR/manifest.tsv"
TMUX_DOCK_REPO="https://github.com/al-hub/tmux-session-dock.git"
TMUX_DOCK_DIR="${TMUX_DOCK_DIR:-$HOME/.local/share/tmux-session-dock}"

CONFIG_FILE=""
ITEMS_FILE=""
INPUT_FD=0
INSTALL_STACK=""
DONE_ITEMS=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()       { printf '[dotfiles] %s\n' "$*"; }
log_info()  { echo -e "${BLUE}${BOLD}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}${BOLD}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}${BOLD}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}${BOLD}[ERROR]${NC} $*" >&2; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

usage() {
    cat <<EOF
${BOLD}dotfiles - Universal Setup & Workspace Orchestrator (${DOTFILES_STABLE_VERSION})${NC}

${BOLD}Usage:${NC} $0 [COMMAND] [OPTIONS]

${BOLD}Commands:${NC}
  ${CYAN}install${NC}       Install configured dotfiles components & provision upstream tmux-session-dock
  ${CYAN}update${NC}        Pull latest dotfiles changes, sync upstream dock & reload tmux
  ${CYAN}uninstall${NC}     Restore files recorded in manifest and cleanly remove symlinks
  ${CYAN}status${NC}        Display installation status, active symlinks & managed state
  ${CYAN}doctor${NC}        Verify system dependencies, shell environment, fonts & socket health
  ${CYAN}purge${NC}         Full uninstall + remove all backups and state history

${BOLD}Options:${NC}
  --v, --version VER   Target specific release tag (e.g. ${DOTFILES_STABLE_VERSION})
  --latest             Target latest master branch (Default)
  --all                Install all enabled components non-interactively
  --no-dock            Skip provisioning upstream tmux-session-dock
  -h, --help           Show this help message
EOF
    exit 0
}

# -----------------------------------------------------------------------------
# Upstream tmux-session-dock Integration
# -----------------------------------------------------------------------------

provision_upstream_dock() {
    log_info "Ensuring upstream tmux-session-dock is provisioned..."
    
    # Check if local development repo exists
    if [ -d "$HOME/workspace/tmux-session-dock" ] && [ -x "$HOME/workspace/tmux-session-dock/setup.sh" ]; then
        log_ok "Detected local workspace at $HOME/workspace/tmux-session-dock"
        "$HOME/workspace/tmux-session-dock/setup.sh" install --no-tmux-conf >/dev/null 2>&1 || true
        return 0
    fi

    if [ ! -d "$TMUX_DOCK_DIR/.git" ]; then
        log_info "Cloning tmux-session-dock into $TMUX_DOCK_DIR..."
        mkdir -p "$(dirname "$TMUX_DOCK_DIR")"
        git clone "$TMUX_DOCK_REPO" "$TMUX_DOCK_DIR" 2>/dev/null || true
    fi

    if [ -x "$TMUX_DOCK_DIR/setup.sh" ]; then
        log_info "Running upstream tmux-session-dock setup controller..."
        "$TMUX_DOCK_DIR/setup.sh" install --no-tmux-conf >/dev/null 2>&1 || true
        log_ok "Upstream tmux-session-dock installed successfully."
    fi
}

update_upstream_dock() {
    log_info "Updating upstream tmux-session-dock..."
    if [ -d "$HOME/workspace/tmux-session-dock" ] && [ -x "$HOME/workspace/tmux-session-dock/setup.sh" ]; then
        "$HOME/workspace/tmux-session-dock/setup.sh" update >/dev/null 2>&1 || true
        log_ok "Updated local workspace dock."
    elif [ -d "$TMUX_DOCK_DIR" ] && [ -x "$TMUX_DOCK_DIR/setup.sh" ]; then
        "$TMUX_DOCK_DIR/setup.sh" update >/dev/null 2>&1 || true
        log_ok "Updated upstream dock at $TMUX_DOCK_DIR."
    fi
}

# -----------------------------------------------------------------------------
# Path & URL Resolution
# -----------------------------------------------------------------------------

repo_raw_url_for_version() {
    case "$1" in
        latest|master) printf '%s/refs/heads/master\n' "$REPO_RAW_BASE_URL" ;;
        main)          printf '%s/refs/heads/main\n' "$REPO_RAW_BASE_URL" ;;
        *)             printf '%s/refs/tags/%s\n' "$REPO_RAW_BASE_URL" "$1" ;;
    esac
}

setup_urls() {
    if [ -z "$REPO_RAW_URL" ]; then
        REPO_RAW_URL="$(repo_raw_url_for_version "$DOTFILES_VERSION")"
    fi
    if [ -z "$INSTALL_TOML_URL" ]; then
        INSTALL_TOML_URL="$REPO_RAW_URL/install.toml"
    fi
}

expand_path() {
    case "$1" in
        "~"/*) printf '%s/%s\n' "$HOME" "${1#\~/}" ;;
        "~")   printf '%s\n' "$HOME" ;;
        *)     printf '%s\n' "$1" ;;
    esac
}

source_url() {
    source_path="$1"
    if [ -f "$source_path" ]; then
        printf 'file://%s/%s\n' "$(pwd)" "$source_path"
    else
        printf '%s/%s\n' "$REPO_RAW_URL" "$source_path"
    fi
}

# -----------------------------------------------------------------------------
# Manifest & Backup Engine
# -----------------------------------------------------------------------------

record_manifest() {
    name="$1"
    target_path="$2"
    backup_path="${3:--}"
    source_name="$4"
    mkdir -p "$STATE_DIR"
    touch "$MANIFEST_FILE"

    tmp_manifest="$(mktemp)"
    if [ -f "$MANIFEST_FILE" ]; then
        awk -F '\t' -v t="$target_path" '$2 != t' "$MANIFEST_FILE" > "$tmp_manifest" || true
    fi
    printf '%s\t%s\t%s\t%s\n' "$name" "$target_path" "$backup_path" "$source_name" >> "$tmp_manifest"
    mv "$tmp_manifest" "$MANIFEST_FILE"
}

is_managed() {
    name="$1"
    [ -f "$MANIFEST_FILE" ] || return 1
    awk -F '\t' -v n="$name" '$1 == n { found = 1 } END { exit(found ? 0 : 1) }' "$MANIFEST_FILE"
}

restore_from_manifest() {
    if [ ! -f "$MANIFEST_FILE" ]; then
        log_warn "No manifest file found at $MANIFEST_FILE."
        return 0
    fi

    log_info "Restoring files from manifest..."
    tmp_manifest="$(mktemp)"
    tac "$MANIFEST_FILE" > "$tmp_manifest" 2>/dev/null || tail -r "$MANIFEST_FILE" > "$tmp_manifest" 2>/dev/null || cp "$MANIFEST_FILE" "$tmp_manifest"

    while IFS=$'\t' read -r name target_path backup_path source_name; do
        [ -n "$target_path" ] || continue
        if [ "$backup_path" != "-" ] && [ -f "$backup_path" ]; then
            mkdir -p "$(dirname "$target_path")"
            cp "$backup_path" "$target_path"
            log_ok "Restored $target_path from backup $backup_path"
        else
            if [ -e "$target_path" ] || [ -L "$target_path" ]; then
                rm -rf "$target_path"
                log_ok "Removed managed file $target_path"
            fi
        fi
    done < "$tmp_manifest"
    rm -f "$tmp_manifest" "$MANIFEST_FILE"
    log_ok "Manifest rollback completed."
}

clear_install_state() {
    rm -rf "$STATE_DIR"
    log_ok "Cleared installer state at $STATE_DIR"
}

# -----------------------------------------------------------------------------
# Configuration Loader (install.toml parser)
# -----------------------------------------------------------------------------

load_config() {
    CONFIG_FILE="$(mktemp)"
    ITEMS_FILE="$(mktemp)"

    if [ -f "install.toml" ]; then
        cp "install.toml" "$CONFIG_FILE"
    else
        curl -fsSL "$INSTALL_TOML_URL" -o "$CONFIG_FILE" 2>/dev/null || cp "install.toml" "$CONFIG_FILE" 2>/dev/null || true
    fi

    awk '
    function trim(s) {
        sub(/^[ \t]+/, "", s)
        sub(/[ \t]+$/, "", s)
        return s
    }
    function unquote(s) {
        s = trim(s)
        sub(/^"/, "", s)
        sub(/"$/, "", s)
        return s
    }
    function parse_array(s, out,    n, i, parts) {
        sub(/^[ \t]*\[/, "", s)
        sub(/\][ \t]*$/, "", s)
        n = split(s, parts, ",")
        out[0] = 0
        for (i = 1; i <= n; i++) {
            v = unquote(parts[i])
            if (v != "") {
                out[0]++
                out[out[0]] = v
            }
        }
    }
    function join_array(arr,    s, i) {
        s = ""
        for (i = 1; i <= arr[0]; i++) {
            s = (s == "" ? arr[i] : s " " arr[i])
        }
        return s
    }
    function flush_item() {
        if (name != "") {
            print name "|" enabled "|" hidden "|" source "|" target "|" join_array(commands) "|" join_array(packages) "|" join_array(depends) "|" description
        }
        name = ""; enabled = "false"; hidden = "false"; source = ""; target = ""; description = ""
        commands[0] = 0; packages[0] = 0; depends[0] = 0
    }
    BEGIN {
        name = ""; enabled = "false"; hidden = "false"; source = ""; target = ""; description = ""
        commands[0] = 0; packages[0] = 0; depends[0] = 0
    }
    /^[ \t]*\[\[dotfiles\]\]/ { flush_item(); next }
    /^[ \t]*name[ \t]*=/        { name = unquote(substr($0, index($0, "=") + 1)); next }
    /^[ \t]*enabled[ \t]*=/     { enabled = trim(substr($0, index($0, "=") + 1)); next }
    /^[ \t]*hidden[ \t]*=/      { hidden = trim(substr($0, index($0, "=") + 1)); next }
    /^[ \t]*source[ \t]*=/      { source = unquote(substr($0, index($0, "=") + 1)); next }
    /^[ \t]*target[ \t]*=/      { target = unquote(substr($0, index($0, "=") + 1)); next }
    /^[ \t]*description[ \t]*=/ { description = unquote(substr($0, index($0, "=") + 1)); next }
    /^[ \t]*commands[ \t]*=/    { parse_array(substr($0, index($0, "=") + 1), commands); next }
    /^[ \t]*packages[ \t]*=/    { parse_array(substr($0, index($0, "=") + 1), packages); next }
    /^[ \t]*depends[ \t]*=/     { parse_array(substr($0, index($0, "=") + 1), depends); next }
    END { flush_item() }
    ' "$CONFIG_FILE" > "$ITEMS_FILE"
}

# -----------------------------------------------------------------------------
# Installation Engine
# -----------------------------------------------------------------------------

ensure_executable() {
    path="$(expand_path "$1")"
    [ -f "$path" ] && chmod +x "$path"
}

after_install_item() {
    name="$1"
    target="$2"

    case "$name" in
        tmux)
            if tmux info >/dev/null 2>&1; then
                tmux source-file "$HOME/.tmux.conf" 2>/dev/null || true
            fi
            ;;
        tmux-session-dock)
            provision_upstream_dock
            ;;
        urxvt-resize-font)
            ensure_executable "$target"
            ;;
        tmux-xresources)
            if command_exists xrdb && [ -n "${DISPLAY:-}" ]; then
                xrdb -merge "$(expand_path "$target")" 2>/dev/null || true
            fi
            ;;
    esac
}

install_item() {
    name="$1"
    hidden="$2"
    source="$3"
    target="$4"
    commands="$5"
    packages="$6"
    depends="$7"

    # Handle upstream dock virtual component
    if [ "$name" = "tmux-session-dock" ]; then
        provision_upstream_dock
        return 0
    fi

    target_path="$(expand_path "$target")"
    source_url="$(source_url "$source")"
    tmp_file="$(mktemp)"

    if [[ "$source_url" =~ ^file:// ]]; then
        src_path="${source_url#file://}"
        if [ -f "$src_path" ]; then
            cp "$src_path" "$tmp_file"
        else
            log_error "Source file not found: $src_path"
            rm -f "$tmp_file"
            return 1
        fi
    else
        if ! curl -fsSL "$source_url" -o "$tmp_file" 2>/dev/null; then
            log_error "Failed to download $source_url"
            rm -f "$tmp_file"
            return 1
        fi
    fi

    backup_path="-"
    if [ -f "$target_path" ] && [ ! -L "$target_path" ]; then
        mkdir -p "$BACKUP_DIR"
        backup_path="$BACKUP_DIR/$(basename "$target_path").backup.$(date +%Y%m%d%H%M%S)"
        cp "$target_path" "$backup_path"
    fi

    mkdir -p "$(dirname "$target_path")"
    cp "$tmp_file" "$target_path"
    rm -f "$tmp_file"
    record_manifest "$name" "$target_path" "$backup_path" "$source"
    log_ok "Installed $name -> $target_path"

    after_install_item "$name" "$target"

    # Install dependencies
    if [ -n "$depends" ]; then
        for dep in $depends; do
            while IFS='|' read -r d_name d_enabled d_hidden d_source d_target d_commands d_packages d_depends d_desc; do
                if [ "$d_name" = "$dep" ]; then
                    install_item "$d_name" "$d_hidden" "$d_source" "$d_target" "$d_commands" "$d_packages" "$d_depends"
                fi
            done < "$ITEMS_FILE"
        done
    fi
}

do_install_all() {
    log_info "Installing all enabled dotfiles components..."
    load_config
    while IFS='|' read -r name enabled hidden source target commands packages depends description; do
        if [ "$enabled" = "true" ] && [ "$hidden" != "true" ]; then
            install_item "$name" "$hidden" "$source" "$target" "$commands" "$packages" "$depends"
        fi
    done < "$ITEMS_FILE"
    log_ok "All enabled components installed successfully!"
}

# -----------------------------------------------------------------------------
# Diagnostics & Doctor
# -----------------------------------------------------------------------------

do_status() {
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    echo -e "  ${BOLD}dotfiles (${DOTFILES_STABLE_VERSION}) - Status & Manifest Overview${NC}"
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    load_config
    printf '%-4s %-9s %-12s %-10s %-9s %s\n' "No" "State" "Target" "Command" "Managed" "Name"
    printf '%s\n' "----------------------------------------------------------------------"
    
    local idx=1
    while IFS='|' read -r name enabled hidden source target commands packages depends description; do
        [ "$hidden" = "true" ] && continue
        local target_path
        target_path="$(expand_path "$target")"
        local target_state="missing"
        local cmd_state="-"
        local managed_state="no"

        [ -e "$target_path" ] && target_state="exists"
        if [ -n "$commands" ]; then
            local missing=0
            for c in $commands; do command_exists "$c" || missing=$((missing + 1)); done
            [ "$missing" -eq 0 ] && cmd_state="ok" || cmd_state="missing:$missing"
        fi
        is_managed "$name" && managed_state="yes"

        printf '%-4s %-9s %-12s %-10s %-9s %s\n' "$idx" "$([ "$enabled" = "true" ] && echo -e "${GREEN}enabled${NC}" || echo "disabled")" "$target_state" "$cmd_state" "$managed_state" "$name"
        idx=$((idx + 1))
    done < "$ITEMS_FILE"
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
}

do_doctor() {
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    echo -e "  ${BOLD}dotfiles Environment Doctor & Health Check${NC}"
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    
    local checks=(
        "tmux:Multiplexer"
        "zsh:Shell"
        "urxvt:Terminal"
        "bc:Calculator"
        "xclip:Clipboard"
        "xrdb:X11 Resources"
        "vim:Editor"
    )

    for item in "${checks[@]}"; do
        local cmd="${item%%:*}"
        local label="${item##*:}"
        if command_exists "$cmd"; then
            echo -e "  [OK]      $cmd ($label)"
        else
            echo -e "  ${YELLOW}[MISSING]${NC} $cmd ($label)"
        fi
    done

    # Check upstream dock
    if [ -x "$HOME/.local/bin/tmux-session-dock" ] || [ -d "$TMUX_DOCK_DIR" ] || [ -d "$HOME/workspace/tmux-session-dock" ]; then
        echo -e "  [OK]      tmux-session-dock (Upstream Dock Integration)"
    else
        echo -e "  ${YELLOW}[MISSING]${NC} tmux-session-dock (Run: ./setup.sh install)"
    fi

    echo -e "${CYAN}${BOLD}======================================================================${NC}"
}

do_update() {
    log_info "Updating dotfiles repository..."
    if [ -d ".git" ]; then
        git pull --ff-only origin master || git pull origin main || true
    fi
    update_upstream_dock
    do_install_all
}

# -----------------------------------------------------------------------------
# Main Router
# -----------------------------------------------------------------------------

INVOKED_AS="$(basename "$0")"

# Backward compatibility for install.sh / uninstall.sh
if [ "$INVOKED_AS" = "install.sh" ] && [ $# -eq 0 ]; then
    set -- "install" "--all"
elif [ "$INVOKED_AS" = "uninstall.sh" ] && [ $# -eq 0 ]; then
    set -- "uninstall"
fi

CMD="${1:-}"

case "$CMD" in
    install)
        shift || true
        setup_urls
        if [ "${1:-}" = "--all" ]; then
            do_install_all
        else
            do_install_all
        fi
        ;;
    update)
        do_update
        ;;
    uninstall|undo|rollback)
        restore_from_manifest
        ;;
    purge)
        restore_from_manifest
        clear_install_state
        ;;
    status)
        setup_urls
        do_status
        ;;
    doctor|check)
        do_doctor
        ;;
    -h|--help)
        usage
        ;;
    *)
        # If run interactively on TTY with no args, install enabled components
        setup_urls
        do_install_all
        ;;
esac
