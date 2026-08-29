#!/usr/bin/env bash
# ==============================================================================
# setup.sh - dotfiles Workspace Orchestrator
# https://github.com/al-hub/dotfiles
#
# Responsibility: decide WHICH components are installed, in WHAT order, at WHAT
# version. Component behaviour (e.g. tmux configuration) belongs to the module
# owner. Upstream modules are driven only through their public setup.sh CLI.
# ==============================================================================
set -euo pipefail

DOTFILES_STABLE_VERSION="v0.8.0"
DOTFILES_VERSION="${DOTFILES_VERSION:-master}"
REPO_RAW_BASE_URL="${REPO_RAW_BASE_URL:-https://raw.githubusercontent.com/al-hub/dotfiles}"
REPO_RAW_URL="${REPO_RAW_URL:-}"
INSTALL_TOML_URL="${INSTALL_TOML_URL:-}"
STATE_DIR="${STATE_DIR:-$HOME/.dotfiles-install}"
BACKUP_DIR="$STATE_DIR/backups"
MANIFEST_FILE="$STATE_DIR/manifest.tsv"
# When <DEV_ROOT>/<module>/setup.sh exists, that checkout is used instead of cloning.
DOTFILES_DEV_ROOT="${DOTFILES_DEV_ROOT:-$HOME/workspace}"
SKIP_UPSTREAM="${SKIP_UPSTREAM:-0}"

CONFIG_FILE=""
ITEMS_FILE=""
PURGE=0

# Item record layout (pipe separated, produced by load_config):
#   name|enabled|hidden|type|source|target|repo|dir|min_version|post_install|commands|packages|depends|description
ITEM_FIELDS="name enabled hidden mtype source target repo dir min_version post_install commands packages depends description"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}${BOLD}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}${BOLD}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}${BOLD}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}${BOLD}[ERROR]${NC} $*" >&2; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

usage() {
    cat <<EOF
${BOLD}dotfiles - Workspace Orchestrator (${DOTFILES_STABLE_VERSION})${NC}

${BOLD}Usage:${NC} $0 [COMMAND] [OPTIONS]

${BOLD}Commands:${NC}
  ${CYAN}install${NC}       Install enabled modules (file modules copied, upstream modules delegated)
  ${CYAN}update${NC}        Pull dotfiles, update upstream modules, reinstall enabled modules
  ${CYAN}uninstall${NC}     Restore manifest-recorded files; delegate upstream uninstall to owners
  ${CYAN}purge${NC}         uninstall + remove backups, state and upstream checkouts
  ${CYAN}status${NC}        Show module table (state, commands, managed, version)
  ${CYAN}doctor${NC}        Verify required commands and upstream module versions

${BOLD}Options:${NC}
  --v, --version VER   Target a release tag of this repo (e.g. ${DOTFILES_STABLE_VERSION})
  --latest             Target master (default)
  --all                Install all enabled modules (default behaviour)
  --skip-upstream      Do not install/update upstream modules (alias: --no-dock)
  -h, --help           Show this help

${BOLD}Environment:${NC}
  DOTFILES_DEV_ROOT    Directory holding local upstream checkouts (default: ~/workspace)
  STATE_DIR            Installer state directory (default: ~/.dotfiles-install)

${BOLD}Note:${NC} the upstream tmux-session-dock uninstaller terminates the running tmux
server. Run uninstall/purge from outside tmux.
EOF
    exit 0
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
    awk -F '\t' -v t="$target_path" '$2 != t' "$MANIFEST_FILE" > "$tmp_manifest" || true
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
        if [ "$source_name" = "upstream" ]; then
            uninstall_upstream_module "$name" "$target_path"
            continue
        fi
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
    function reset_item() {
        name = ""; enabled = "false"; hidden = "false"; mtype = "file"
        source = ""; target = ""; repo = ""; dir = ""; min_version = ""; description = ""
        post_install[0] = 0; commands[0] = 0; packages[0] = 0; depends[0] = 0
    }
    function flush_item() {
        if (name != "") {
            print name "|" enabled "|" hidden "|" mtype "|" source "|" target "|" repo "|" dir "|" min_version "|" join_array(post_install) "|" join_array(commands) "|" join_array(packages) "|" join_array(depends) "|" description
        }
        reset_item()
    }
    BEGIN { reset_item() }
    /^[ \t]*\[\[dotfiles\]\]/ { flush_item(); next }
    /^[ \t]*name[ \t]*=/         { name = unquote(substr($0, index($0, "=") + 1)); next }
    /^[ \t]*enabled[ \t]*=/      { enabled = trim(substr($0, index($0, "=") + 1)); next }
    /^[ \t]*hidden[ \t]*=/       { hidden = trim(substr($0, index($0, "=") + 1)); next }
    /^[ \t]*type[ \t]*=/         { mtype = unquote(substr($0, index($0, "=") + 1)); next }
    /^[ \t]*source[ \t]*=/       { source = unquote(substr($0, index($0, "=") + 1)); next }
    /^[ \t]*target[ \t]*=/       { target = unquote(substr($0, index($0, "=") + 1)); next }
    /^[ \t]*repo[ \t]*=/         { repo = unquote(substr($0, index($0, "=") + 1)); next }
    /^[ \t]*dir[ \t]*=/          { dir = unquote(substr($0, index($0, "=") + 1)); next }
    /^[ \t]*min_version[ \t]*=/  { min_version = unquote(substr($0, index($0, "=") + 1)); next }
    /^[ \t]*description[ \t]*=/  { description = unquote(substr($0, index($0, "=") + 1)); next }
    /^[ \t]*post_install[ \t]*=/ { parse_array(substr($0, index($0, "=") + 1), post_install); next }
    /^[ \t]*commands[ \t]*=/     { parse_array(substr($0, index($0, "=") + 1), commands); next }
    /^[ \t]*packages[ \t]*=/     { parse_array(substr($0, index($0, "=") + 1), packages); next }
    /^[ \t]*depends[ \t]*=/      { parse_array(substr($0, index($0, "=") + 1), depends); next }
    END { flush_item() }
    ' "$CONFIG_FILE" > "$ITEMS_FILE"
}

# Print the item record for one module name (empty if absent).
find_item() {
    awk -F '|' -v n="$1" '$1 == n { print; exit }' "$ITEMS_FILE"
}

# -----------------------------------------------------------------------------
# Upstream Module Adapter (public CLI contract: setup.sh install|update|uninstall|purge|status)
# -----------------------------------------------------------------------------

resolve_upstream_dir() {
    name="$1"
    dir="$2"
    if [ -x "$DOTFILES_DEV_ROOT/$name/setup.sh" ]; then
        printf '%s\n' "$DOTFILES_DEV_ROOT/$name"
    else
        expand_path "$dir"
    fi
}

is_dev_checkout() {
    case "$1" in
        "$DOTFILES_DEV_ROOT"/*) return 0 ;;
        *) return 1 ;;
    esac
}

upstream_version() {
    git -C "$1" describe --tags --abbrev=0 2>/dev/null || printf 'unknown\n'
}

# version_ge A B : true when A >= B (semver-ish via sort -V)
version_ge() {
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" = "$2" ]
}

check_upstream_version() {
    name="$1"
    path="$2"
    min_version="$3"
    [ -n "$min_version" ] || return 0
    current="$(upstream_version "$path")"
    if [ "$current" = "unknown" ]; then
        log_warn "$name: version unknown (no git tag reachable) - required >= $min_version"
        return 1
    fi
    if version_ge "$current" "$min_version"; then
        log_ok "$name version $current (>= $min_version)"
        return 0
    fi
    log_warn "$name version $current is below required $min_version. Run: $0 update"
    return 1
}

install_upstream_module() {
    name="$1"
    repo="$2"
    dir="$3"
    min_version="$4"

    if [ "$SKIP_UPSTREAM" = "1" ]; then
        log_info "Skipping upstream module $name (--skip-upstream)"
        return 0
    fi

    path="$(resolve_upstream_dir "$name" "$dir")"
    if is_dev_checkout "$path"; then
        log_ok "$name: using local checkout $path"
    elif [ ! -d "$path/.git" ]; then
        log_info "$name: cloning $repo -> $path"
        mkdir -p "$(dirname "$path")"
        if ! git clone --quiet "$repo" "$path" </dev/null; then
            log_error "$name: git clone failed"
            return 1
        fi
    fi

    if [ ! -x "$path/setup.sh" ]; then
        log_error "$name: $path/setup.sh not found or not executable"
        return 1
    fi

    log_info "$name: delegating install to $path/setup.sh"
    if ! "$path/setup.sh" install >/dev/null </dev/null; then
        log_warn "$name: upstream install reported an error"
    fi
    check_upstream_version "$name" "$path" "$min_version" || true
    record_manifest "$name" "$path" "-" "upstream"
    log_ok "Installed $name (upstream) -> $path"
}

update_upstream_module() {
    name="$1"
    dir="$2"
    path="$(resolve_upstream_dir "$name" "$dir")"
    if [ -x "$path/setup.sh" ]; then
        log_info "$name: delegating update to $path/setup.sh"
        "$path/setup.sh" update >/dev/null </dev/null || log_warn "$name: upstream update reported an error"
    fi
}

uninstall_upstream_module() {
    name="$1"
    dir="$2"
    path="$(resolve_upstream_dir "$name" "$dir")"
    if [ -x "$path/setup.sh" ]; then
        if [ "$PURGE" = "1" ]; then
            log_info "$name: delegating purge to $path/setup.sh"
            "$path/setup.sh" purge >/dev/null </dev/null || log_warn "$name: upstream purge reported an error"
        else
            log_info "$name: delegating uninstall to $path/setup.sh"
            "$path/setup.sh" uninstall >/dev/null </dev/null || log_warn "$name: upstream uninstall reported an error"
        fi
    fi
    if [ "$PURGE" = "1" ] && [ -d "$path" ] && ! is_dev_checkout "$path"; then
        rm -rf "$path"
        log_ok "$name: removed checkout $path"
    fi
}

# -----------------------------------------------------------------------------
# File Module Installer
# -----------------------------------------------------------------------------

run_post_install() {
    target="$1"
    hooks="$2"
    target_path="$(expand_path "$target")"
    for hook in $hooks; do
        case "$hook" in
            executable)
                [ -f "$target_path" ] && chmod +x "$target_path"
                ;;
            xrdb-merge)
                if command_exists xrdb && [ -n "${DISPLAY:-}" ]; then
                    xrdb -merge "$target_path" 2>/dev/null || true
                fi
                ;;
            *)
                log_warn "Unknown post_install hook '$hook' for $target"
                ;;
        esac
    done
}

install_file_module() {
    name="$1"
    source="$2"
    target="$3"
    post_install="$4"

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
        if ! curl -fsSL "$source_url" -o "$tmp_file" 2>/dev/null </dev/null; then
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

    run_post_install "$target" "$post_install"
}

# -----------------------------------------------------------------------------
# Installation Engine (type dispatch + dependency walk)
# -----------------------------------------------------------------------------

install_item() {
    # shellcheck disable=SC2086
    IFS='|' read -r $ITEM_FIELDS <<< "$1"

    case "$mtype" in
        upstream)
            install_upstream_module "$name" "$repo" "$dir" "$min_version"
            ;;
        file)
            install_file_module "$name" "$source" "$target" "$post_install"
            ;;
        *)
            log_error "$name: unknown module type '$mtype'"
            return 1
            ;;
    esac

    for dep in $depends; do
        dep_item="$(find_item "$dep")"
        if [ -n "$dep_item" ]; then
            install_item "$dep_item"
        else
            log_warn "$name: dependency '$dep' not defined in install.toml"
        fi
    done
}

do_install_all() {
    log_info "Installing all enabled dotfiles modules..."
    load_config
    while IFS= read -r item; do
        # shellcheck disable=SC2086
        IFS='|' read -r $ITEM_FIELDS <<< "$item"
        if [ "$enabled" = "true" ] && [ "$hidden" != "true" ]; then
            install_item "$item"
        fi
    done < "$ITEMS_FILE"
    log_ok "All enabled modules installed."
}

# -----------------------------------------------------------------------------
# Uninstall / Purge
# -----------------------------------------------------------------------------

do_uninstall() {
    log_info "Uninstalling dotfiles modules..."
    if [ -n "${TMUX:-}" ]; then
        log_warn "Running inside tmux: the upstream tmux-session-dock uninstaller terminates the tmux server."
    fi
    load_config

    if [ -f "$MANIFEST_FILE" ]; then
        restore_from_manifest
    else
        log_info "No manifest found; removing targets defined in install.toml..."
        while IFS= read -r item; do
            # shellcheck disable=SC2086
            IFS='|' read -r $ITEM_FIELDS <<< "$item"
            case "$mtype" in
                upstream)
                    uninstall_upstream_module "$name" "$dir"
                    ;;
                file)
                    [ -n "$target" ] || continue
                    target_path="$(expand_path "$target")"
                    if [ -e "$target_path" ] || [ -L "$target_path" ]; then
                        rm -rf "$target_path"
                        log_ok "Removed $target_path"
                    fi
                    ;;
            esac
        done < "$ITEMS_FILE"
    fi

    log_ok "Uninstallation completed."
}

do_purge() {
    log_warn "Purging all dotfiles modules, backups and state..."
    PURGE=1
    do_uninstall
    rm -rf "$HOME/.cache/dotfiles"   # legacy tmux-zshrc location (pre v0.8.0)
    rm -rf "$STATE_DIR"
    log_ok "Purged ~/.cache/dotfiles and $STATE_DIR"
}

# -----------------------------------------------------------------------------
# Diagnostics
# -----------------------------------------------------------------------------

do_status() {
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    echo -e "  ${BOLD}dotfiles (${DOTFILES_STABLE_VERSION}) - Module Status${NC}"
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    load_config
    printf '%-4s %-9s %-9s %-8s %-10s %-8s %-10s %s\n' "No" "State" "Type" "Target" "Command" "Managed" "Version" "Name"
    printf '%s\n' "----------------------------------------------------------------------"

    idx=1
    while IFS= read -r item; do
        # shellcheck disable=SC2086
        IFS='|' read -r $ITEM_FIELDS <<< "$item"
        [ "$hidden" = "true" ] && continue

        target_state="missing"
        cmd_state="-"
        managed_state="no"
        version_state="-"

        case "$mtype" in
            upstream)
                path="$(resolve_upstream_dir "$name" "$dir")"
                [ -x "$path/setup.sh" ] && target_state="exists"
                version_state="$(upstream_version "$path")"
                ;;
            *)
                [ -e "$(expand_path "$target")" ] && target_state="exists"
                ;;
        esac

        if [ -n "$commands" ]; then
            missing=0
            for c in $commands; do command_exists "$c" || missing=$((missing + 1)); done
            [ "$missing" -eq 0 ] && cmd_state="ok" || cmd_state="missing:$missing"
        fi
        is_managed "$name" && managed_state="yes"

        state_label="disabled"
        [ "$enabled" = "true" ] && state_label="$(echo -e "${GREEN}enabled${NC} ")"
        printf '%-4s %-9b %-9s %-8s %-10s %-8s %-10s %s\n' "$idx" "$state_label" "$mtype" "$target_state" "$cmd_state" "$managed_state" "$version_state" "$name"
        idx=$((idx + 1))
    done < "$ITEMS_FILE"
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
}

do_doctor() {
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    echo -e "  ${BOLD}dotfiles Doctor${NC}"
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    load_config

    # 1. Required commands: union over enabled modules (and their dependencies)
    echo -e "${BOLD}Required commands${NC}"
    all_commands=""
    while IFS= read -r item; do
        # shellcheck disable=SC2086
        IFS='|' read -r $ITEM_FIELDS <<< "$item"
        [ "$enabled" = "true" ] || [ "$hidden" = "true" ] || continue
        all_commands="$all_commands $commands"
    done < "$ITEMS_FILE"
    for c in $(printf '%s\n' $all_commands | sort -u); do
        if command_exists "$c"; then
            echo -e "  [OK]      $c"
        else
            echo -e "  ${YELLOW}[MISSING]${NC} $c"
        fi
    done

    # 2. Upstream modules: version gate + delegated status
    while IFS= read -r item; do
        # shellcheck disable=SC2086
        IFS='|' read -r $ITEM_FIELDS <<< "$item"
        [ "$mtype" = "upstream" ] && [ "$enabled" = "true" ] || continue
        echo
        echo -e "${BOLD}Upstream: $name${NC}"
        path="$(resolve_upstream_dir "$name" "$dir")"
        if [ -x "$path/setup.sh" ]; then
            check_upstream_version "$name" "$path" "$min_version" || true
            "$path/setup.sh" status 2>/dev/null </dev/null | sed 's/^/  /' || true
        else
            echo -e "  ${YELLOW}[MISSING]${NC} $name not installed (Run: $0 install)"
        fi
    done < "$ITEMS_FILE"

    echo -e "${CYAN}${BOLD}======================================================================${NC}"
}

do_update() {
    log_info "Updating dotfiles repository..."
    if [ -d ".git" ]; then
        git pull --ff-only origin master || git pull origin main || true
    fi
    load_config
    if [ "$SKIP_UPSTREAM" != "1" ]; then
        while IFS= read -r item; do
            # shellcheck disable=SC2086
            IFS='|' read -r $ITEM_FIELDS <<< "$item"
            [ "$mtype" = "upstream" ] && [ "$enabled" = "true" ] || continue
            update_upstream_module "$name" "$dir"
        done < "$ITEMS_FILE"
    fi
    do_install_all
}

# -----------------------------------------------------------------------------
# Main Router
# -----------------------------------------------------------------------------

INVOKED_AS="$(basename "$0")"

# Backward compatibility for install.sh / uninstall.sh symlinks
if [ "$INVOKED_AS" = "install.sh" ] && [ $# -eq 0 ]; then
    set -- "install" "--all"
elif [ "$INVOKED_AS" = "uninstall.sh" ] && [ $# -eq 0 ]; then
    set -- "uninstall"
fi

CMD="${1:-}"
case "$CMD" in
    --*) CMD="install" ;;          # curl ... | bash -s -- --v vX.Y.Z  => install
    *)   shift || true ;;
esac

# Global options
while [ $# -gt 0 ]; do
    case "$1" in
        --v|--version)
            DOTFILES_VERSION="${2:-master}"
            shift 2 || shift
            ;;
        --latest)
            DOTFILES_VERSION="master"
            shift
            ;;
        --skip-upstream|--no-dock)
            SKIP_UPSTREAM=1
            shift
            ;;
        --all)
            shift
            ;;
        *)
            shift
            ;;
    esac
done

case "$CMD" in
    install)
        setup_urls
        do_install_all
        ;;
    update)
        setup_urls
        do_update
        ;;
    uninstall|undo|rollback)
        setup_urls
        do_uninstall
        ;;
    purge)
        setup_urls
        do_purge
        ;;
    status)
        setup_urls
        do_status
        ;;
    doctor|check)
        setup_urls
        do_doctor
        ;;
    dump-config)
        # Hidden: print parsed install.toml records (used by tests)
        setup_urls
        load_config
        cat "$ITEMS_FILE"
        ;;
    -h|--help)
        usage
        ;;
    "")
        # curl ... | bash  (no arguments): install everything
        setup_urls
        do_install_all
        ;;
    *)
        log_error "Unknown command: $CMD"
        usage
        ;;
esac
