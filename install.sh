#!/usr/bin/env bash
set -euo pipefail

REPO_RAW_URL="${REPO_RAW_URL:-https://raw.githubusercontent.com/al-hub/dotfiles/refs/heads/master}"
INSTALL_TOML_URL="${INSTALL_TOML_URL:-$REPO_RAW_URL/install.toml}"
STATE_DIR="${STATE_DIR:-$HOME/.dotfiles-install}"
BACKUP_DIR="$STATE_DIR/backups"
MANIFEST_FILE="$STATE_DIR/manifest.tsv"

CONFIG_FILE=""
ITEMS_FILE=""
INPUT_FD=0

# -----------------------------------------------------------------------------
# Common utilities
# -----------------------------------------------------------------------------

log() { printf '[dotfiles] %s\n' "$*"; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

setup_input()
{
    input_file="${DOTFILES_INPUT:-/dev/tty}"

    if [ -r "$input_file" ]; then
        exec 3< "$input_file"
    else
        exec 3<&0
    fi

    INPUT_FD=3
}

sudo_cmd()
{
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

confirm()
{
    prompt="$1"
    default="${2:-n}"
    read -r -u "$INPUT_FD" -p "$prompt " answer || return 1
    answer="${answer:-$default}"

    case "$answer" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
}

download_file()
{
    url="$1"
    output="$2"

    if command_exists curl; then
        curl -fsSL "$url" -o "$output"
    elif command_exists wget; then
        wget -qO "$output" "$url"
    else
        log "curl or wget is required."
        exit 1
    fi
}

expand_path()
{
    case "$1" in
        "~") printf '%s\n' "$HOME" ;;
        "~/"*) printf '%s/%s\n' "$HOME" "${1#"~/"}" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

source_url()
{
    case "$1" in
        http://*|https://*|file://*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$REPO_RAW_URL" "$1" ;;
    esac
}

# -----------------------------------------------------------------------------
# TOML loading
# -----------------------------------------------------------------------------

parse_install_toml()
{
    awk '
        function trim(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            return value
        }
        function clean(value) {
            value = trim(value)
            gsub(/^"/, "", value)
            gsub(/"$/, "", value)
            return value
        }
        function clean_array(value) {
            value = trim(value)
            gsub(/^\[/, "", value)
            gsub(/\]$/, "", value)
            gsub(/"/, "", value)
            gsub(/,/, " ", value)
            value = trim(value)
            gsub(/[[:space:]]+/, " ", value)
            return value
        }
        function emit() {
            if (in_item && name != "") {
                hidden = (hidden == "") ? "false" : hidden
                printf "%s|%s|%s|%s|%s|%s|%s|%s|%s\n", name, enabled, hidden, source, target, commands, packages, depends, description
            }
        }
        /^\[\[dotfiles\]\]/ {
            emit()
            in_item = 1
            name = enabled = hidden = source = target = commands = packages = depends = description = ""
            next
        }
        in_item && /^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*=/ {
            key = $0
            sub(/[[:space:]]*=.*/, "", key)
            key = trim(key)
            value = $0
            sub(/^[^=]*=/, "", value)
            value = trim(value)

            if (key == "name") name = clean(value)
            else if (key == "enabled") enabled = value
            else if (key == "hidden") hidden = value
            else if (key == "source") source = clean(value)
            else if (key == "target") target = clean(value)
            else if (key == "commands") commands = clean_array(value)
            else if (key == "packages") packages = clean_array(value)
            else if (key == "depends") depends = clean_array(value)
            else if (key == "description") description = clean(value)
        }
        END { emit() }
    ' "$CONFIG_FILE" > "$ITEMS_FILE"
}

load_config()
{
    mkdir -p "$STATE_DIR" "$BACKUP_DIR"
    CONFIG_FILE="$(mktemp)"
    ITEMS_FILE="$(mktemp)"
    trap 'rm -f "$CONFIG_FILE" "$ITEMS_FILE"' EXIT

    log "Loading install list from $INSTALL_TOML_URL"
    download_file "$INSTALL_TOML_URL" "$CONFIG_FILE"
    cp "$CONFIG_FILE" "$STATE_DIR/install.toml"
    parse_install_toml
}

# -----------------------------------------------------------------------------
# Manifest state
# -----------------------------------------------------------------------------

is_managed()
{
    name="$1"
    [ -f "$MANIFEST_FILE" ] && awk -F '\t' -v name="$name" '$2 == name { found = 1 } END { exit !found }' "$MANIFEST_FILE"
}

record_manifest()
{
    name="$1"
    target="$2"
    backup="$3"
    source="$4"

    mkdir -p "$STATE_DIR"
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$name" "$target" "$backup" "$source" >> "$MANIFEST_FILE"
}

init_from_manifest()
{
    if [ ! -f "$MANIFEST_FILE" ]; then
        log "No manifest found."
        return
    fi

    if ! confirm "Restore/remove files from manifest and clear install state? [y/N]" "n"; then
        return
    fi

    tac "$MANIFEST_FILE" | while IFS="$(printf '\t')" read -r installed_at name target backup source; do
        if [ -n "$backup" ] && [ "$backup" != "-" ] && [ -f "$backup" ]; then
            cp "$backup" "$target"
            log "Restored $target from $backup"
        elif [ -e "$target" ]; then
            rm -f "$target"
            log "Removed $target"
        fi
    done

    rm -f "$MANIFEST_FILE"
    log "Install state initialized."
}

# -----------------------------------------------------------------------------
# Package and command checks
# -----------------------------------------------------------------------------

install_packages()
{
    packages="$1"
    [ -n "$packages" ] || return 0

    if ! command_exists apt-get; then
        log "Missing command dependencies: $packages"
        log "No supported package manager was found. Install them manually."
        return 1
    fi

    log "Installing packages: $packages"
    sudo_cmd apt-get update
    # shellcheck disable=SC2086
    sudo_cmd apt-get install -y $packages
}

ensure_commands()
{
    commands="$1"
    packages="$2"
    [ -n "$commands" ] || return 0

    missing_commands=""
    for command_name in $commands; do
        command_exists "$command_name" || missing_commands="$missing_commands $command_name"
    done

    [ -n "$missing_commands" ] || return 0

    log "Required commands are missing:$missing_commands"
    if confirm "Install package dependencies now? [y/N]" "n"; then
        install_packages "$packages"
        for command_name in $commands; do
            command_exists "$command_name" || return 1
        done
        return
    fi

    return 1
}

# -----------------------------------------------------------------------------
# Install engine
# -----------------------------------------------------------------------------

cleanup_tmux_runtime()
{
    command_exists tmux || return 0

    if tmux has-session >/dev/null 2>&1; then
        log "Stopping existing tmux server so the new tmux config is used."
        tmux kill-server >/dev/null 2>&1 || true
    fi
}

ensure_executable()
{
    target="$1"
    target_path="$(expand_path "$target")"

    [ -f "$target_path" ] || return 0
    chmod +x "$target_path"
}

after_install_item()
{
    name="$1"
    target="$2"

    case "$name" in
        tmux) cleanup_tmux_runtime ;;
        tmux-session-launcher) ensure_executable "$target" ;;
    esac
}

install_dependencies()
{
    depends="$1"
    [ -n "$depends" ] || return 0

    for dependency_name in $depends; do
        install_by_name "$dependency_name"
    done
}

install_item()
{
    name="$1"
    hidden="$2"
    source="$3"
    target="$4"
    commands="$5"
    packages="$6"
    depends="$7"

    target_path="$(expand_path "$target")"
    source_url="$(source_url "$source")"
    tmp_file="$(mktemp)"

    if ! ensure_commands "$commands" "$packages"; then
        log "Skipped $name because required commands are unavailable."
        rm -f "$tmp_file"
        return
    fi

    log "Downloading $source_url"
    download_file "$source_url" "$tmp_file"

    if [ -f "$target_path" ] && cmp -s "$target_path" "$tmp_file"; then
        log "$name is already installed: $target_path"
        rm -f "$tmp_file"
        after_install_item "$name" "$target"
        install_dependencies "$depends"
        return
    fi

    backup_path="-"
    if [ -e "$target_path" ]; then
        if is_managed "$name"; then
            log "Updating managed file: $target_path"
        else
            log "$target_path already exists."
            if ! confirm "Force install $name and backup existing file? [y/N]" "n"; then
                log "Skipped $name."
                rm -f "$tmp_file"
                return
            fi
        fi

        backup_path="$BACKUP_DIR/${name}.$(date +%Y%m%d_%H%M%S)"
        cp "$target_path" "$backup_path"
        log "Backed up $target_path to $backup_path"
    fi

    mkdir -p "$(dirname "$target_path")"
    cp "$tmp_file" "$target_path"
    rm -f "$tmp_file"
    record_manifest "$name" "$target_path" "$backup_path" "$source"
    log "Installed $name to $target_path"
    after_install_item "$name" "$target"
    install_dependencies "$depends"
}

install_by_index()
{
    wanted="$1"
    index=1

    while IFS='|' read -r name enabled hidden source target commands packages depends description; do
        [ "$hidden" = "true" ] && continue

        if [ "$index" = "$wanted" ]; then
            install_item "$name" "$hidden" "$source" "$target" "$commands" "$packages" "$depends"
            return
        fi
        index=$((index + 1))
    done < "$ITEMS_FILE"

    log "Unknown selection: $wanted"
}

install_by_name()
{
    wanted_name="$1"

    while IFS='|' read -r name enabled hidden source target commands packages depends description; do
        if [ "$name" = "$wanted_name" ]; then
            install_item "$name" "$hidden" "$source" "$target" "$commands" "$packages" "$depends"
            return
        fi
    done < "$ITEMS_FILE"

    log "Unknown item: $wanted_name"
}

install_enabled()
{
    while IFS='|' read -r name enabled hidden source target commands packages depends description; do
        if [ "$enabled" = "true" ] && [ "$hidden" != "true" ]; then
            install_item "$name" "$hidden" "$source" "$target" "$commands" "$packages" "$depends"
        fi
    done < "$ITEMS_FILE"
}

# -----------------------------------------------------------------------------
# Interactive UI
# -----------------------------------------------------------------------------

show_items()
{
    printf '\nInstall list\n'
    printf '%-4s %-9s %-12s %-10s %-9s %s\n' "No" "State" "Target" "Command" "Managed" "Name"
    index=1

    while IFS='|' read -r name enabled hidden source target commands packages depends description; do
        [ "$hidden" = "true" ] && continue

        target_path="$(expand_path "$target")"
        target_state="missing"
        command_state="-"
        managed_state="no"

        [ -e "$target_path" ] && target_state="exists"
        if [ -n "$commands" ]; then
            missing_count=0
            for command_name in $commands; do
                command_exists "$command_name" || missing_count=$((missing_count + 1))
            done

            if [ "$missing_count" -eq 0 ]; then
                command_state="exists"
            else
                command_state="missing:$missing_count"
            fi
        fi
        is_managed "$name" && managed_state="yes"

        if [ "$enabled" = "true" ]; then
            state="enabled"
        else
            state="disabled"
        fi

        printf '%-4s %-9s %-12s %-10s %-9s %s' "$index" "$state" "$target_state" "$command_state" "$managed_state" "$name"
        [ -n "$description" ] && printf ' - %s' "$description"
        printf '\n'
        index=$((index + 1))
    done < "$ITEMS_FILE"

    if [ -f "$MANIFEST_FILE" ]; then
        printf '\nType init to restore files recorded in %s.\n' "$MANIFEST_FILE"
    fi
}

handle_selection()
{
    selection="$1"

    case "$selection" in
        ""|all|All|ALL)
            install_enabled
            ;;
        q|Q|quit|QUIT|exit|EXIT|$'\033')
            exit 0
            ;;
        init|INIT)
            init_from_manifest
            ;;
        *)
            normalized="$(printf '%s\n' "$selection" | tr ',' ' ')"
            for number in $normalized; do
                case "$number" in
                    ''|*[!0-9]*) log "Invalid selection: $number" ;;
                    *) install_by_index "$number" ;;
                esac
            done
            ;;
    esac
}

main()
{
    load_config

    while true; do
        show_items
        printf '\nEnter=install enabled, numbers=install selected, init=reset installed files, q=quit\n'
        read -r -u "$INPUT_FD" -p "Select: " selection || exit 0
        handle_selection "$selection"
    done
}

setup_input
main "$@"
