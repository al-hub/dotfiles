#!/usr/bin/env bash
set -euo pipefail

# End-to-end keyboard scenario. The attached tmux client is backed by a real
# PTY and receives the same byte stream a terminal would send: Ctrl+a prefix,
# arrow escape sequences, printable prompt text, and Enter.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-single-sidebar-keyboard-$$"
RUN_DIR="${TMPDIR:-/tmp}/dotfiles-single-sidebar-keyboard-$$"
HOME_DIR="$RUN_DIR/home"
HISTORY_DIR="$RUN_DIR/history"
CLIENT_LOG="$RUN_DIR/client.log"
INPUT_LOG="$RUN_DIR/input.log"
BRIDGE_LOG="$RUN_DIR/pty-bridge.log"
SYSCALL_LOG="$RUN_DIR/syscall"
INTERPOSER_LOG="$RUN_DIR/interposer.log"
INTERPOSER_SRC="$TEST_DIR/pty-interposer.c"
TEST_TRACE="$RUN_DIR/test-trace.log"
CLIENT_PID=""
ATTACHED_PID=""
OBSERVER_PID=""
OBSERVER_LOG_PID=""
OBSERVER_FD=""
KEEP_RUN_DIR="${KEEP_RUN_DIR:-false}"
TEST_TRACE_VERBOSE="${TEST_TRACE_VERBOSE:-false}"
INPUT_SEQUENCE=0
# forkpty is the acceptance transport. Set TMUX_KEYBOARD_E2E_TRANSPORT=script
# only when comparing the legacy script(1) handoff behavior.
TRANSPORT="${TMUX_KEYBOARD_E2E_TRANSPORT:-bridge}"
SYSCALL_TRACE="${TMUX_KEYBOARD_E2E_SYSCALL_TRACE:-auto}"
SCENARIO="${TMUX_KEYBOARD_E2E_SCENARIO:-full}"
SPLIT_DIRECTION="${TMUX_KEYBOARD_E2E_SPLIT_DIRECTION:-horizontal}"

tmuxc() { HOME="$HOME_DIR" tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf" "$@"; }

test_log()
{
    printf '%s %s\n' "$(date '+%F %T.%3N')" "$*" >> "$TEST_TRACE"
}

client_telemetry()
{
    tmuxc list-clients -F 'control=#{client_control_mode} client=#{client_name} tty=#{client_tty} session=#{session_name} window=#{window_id} pane=#{pane_id} activity=#{client_activity} key_table=#{client_key_table} prefix=#{client_prefix}' 2>/dev/null |
        awk '$1 !~ /^control=1$/ { print; exit }'
}

observer_read_loop()
{
    while IFS= read -r observer_line; do
        case "$observer_line" in
            %output\ *|%extended-output\ *) continue ;;
        esac
        test_log "tmux.control $observer_line"
    done <&"${OBSERVER_FD}"
}

input_log_tail_hex()
{
    [ -f "$INPUT_LOG" ] || {
        printf 'none\n'
        return 0
    }
    tail -c 64 "$INPUT_LOG" | od -An -tx1 | tr -d ' \n'
}

cleanup()
{
    tmuxc kill-server >/dev/null 2>&1 || true
    if [ -n "${ATTACHED_PID:-}" ]; then
        kill "$ATTACHED_PID" >/dev/null 2>&1 || true
        wait "$ATTACHED_PID" 2>/dev/null || true
    fi
    if [ -n "${CLIENT_PID:-}" ]; then
        kill "$CLIENT_PID" >/dev/null 2>&1 || true
        wait "$CLIENT_PID" 2>/dev/null || true
    fi
    if [ -n "${OBSERVER_LOG_PID:-}" ]; then
        kill "$OBSERVER_LOG_PID" >/dev/null 2>&1 || true
        wait "$OBSERVER_LOG_PID" 2>/dev/null || true
    fi
    if [ -n "${OBSERVER_PID:-}" ]; then
        kill "$OBSERVER_PID" >/dev/null 2>&1 || true
        wait "$OBSERVER_PID" 2>/dev/null || true
    fi
    if [ -n "${OBSERVER_FD:-}" ]; then
        eval "exec ${OBSERVER_FD}<&-" 2>/dev/null || true
    fi
    [ "$KEEP_RUN_DIR" = true ] || rm -rf "$RUN_DIR"
}
trap cleanup EXIT INT TERM

mkdir -p "$HOME_DIR/.local/bin" "$HISTORY_DIR"
ln -sfn "$LAUNCHER" "$HOME_DIR/.local/bin/tmux-session-launcher"
ln -sfn "$REPO_ROOT/scripts/tmux-sidebar-tmux-adapter" "$HOME_DIR/.local/bin/tmux-sidebar-tmux-adapter"
ln -sfn "$REPO_ROOT/scripts/tmux-sidebar-controller" "$HOME_DIR/.local/bin/tmux-sidebar-controller"

case "$SYSCALL_TRACE" in
    auto)
        if command -v strace >/dev/null 2>&1; then
            TRACE_MODE=strace
        elif command -v cc >/dev/null 2>&1; then
            TRACE_MODE=preload
        else
            TRACE_MODE=none
        fi
        ;;
    0) TRACE_MODE=none ;;
    1)
        if command -v strace >/dev/null 2>&1; then
            TRACE_MODE=strace
        elif command -v cc >/dev/null 2>&1; then
            TRACE_MODE=preload
        else
            printf 'ERROR: syscall tracing requested but strace and cc are unavailable\n' >&2
            exit 2
        fi
        ;;
    *)
        printf 'TMUX_KEYBOARD_E2E_SYSCALL_TRACE must be auto, 0, or 1\n' >&2
        exit 2
        ;;
esac
case "$SCENARIO" in
    full|minimal|split-cycle|direct-layout|rapid-operations|arbitrary-topology|multi-window-topology) ;;
    *)
        printf 'TMUX_KEYBOARD_E2E_SCENARIO must be full, minimal, split-cycle, direct-layout, rapid-operations, arbitrary-topology, or multi-window-topology\n' >&2
        exit 2
        ;;
esac
case "$SPLIT_DIRECTION" in
    horizontal|vertical) ;;
    *)
        printf 'TMUX_KEYBOARD_E2E_SPLIT_DIRECTION must be horizontal or vertical\n' >&2
        exit 2
        ;;
esac
test_log "transport.config name=$TRANSPORT syscall_trace=$SYSCALL_TRACE trace_mode=$TRACE_MODE scenario=$SCENARIO"

PTY_BRIDGE_BIN="$RUN_DIR/pty-bridge"
INTERPOSER_BIN="$RUN_DIR/pty-interposer.so"
if [ "$TRANSPORT" = bridge ]; then
    cc -O2 -Wall -Wextra "$TEST_DIR/pty-bridge.c" -lutil -o "$PTY_BRIDGE_BIN"
elif [ "$TRACE_MODE" = preload ]; then
    cc -O2 -Wall -Wextra -shared -fPIC "$INTERPOSER_SRC" -ldl -o "$INTERPOSER_BIN"
fi

count_sessions()
{
    tmuxc list-sessions -F '#{session_name}' 2>/dev/null | wc -l | tr -d ' '
}

count_sidebars()
{
    tmuxc list-panes -a -F '#{pane_title}' 2>/dev/null |
        awk '$0 == "dotfiles-session-sidebar" { count++ } END { print count + 0 }'
}

tmux_state_snapshot()
{
    {
        printf 'clients\n'
        tmuxc list-clients -F 'control=#{client_control_mode} client=#{client_name} tty=#{client_tty} session=#{session_name} window=#{window_index} pane=#{pane_id} activity=#{client_activity} key_table=#{client_key_table} prefix=#{client_prefix}' 2>&1 || true
        printf 'panes\n'
        tmuxc list-panes -a -F 'session=#{session_name} window=#{window_index} pane=#{pane_id} title=#{pane_title} active=#{pane_active} dead=#{pane_dead}' 2>&1 || true
        printf 'options input_ready=%s prompt_ready=%s generation=%s\n' "$(input_ready)" "$(prompt_ready)" "$(action_generation)"
        printf 'active\n'
        sidebar_is_active
    } | tr '\n' ';' | sed 's/;$//'
}

count_archives()
{
    find "$HISTORY_DIR" -maxdepth 1 -type f -name '*.tsv' -print 2>/dev/null | wc -l | tr -d ' '
}

client_session()
{
    tmuxc list-clients -F '#{client_control_mode}|#{session_name}' 2>/dev/null |
        awk -F '|' '$1 != 1 { print $2; exit }'
}

sidebar_is_active()
{
    local sidebar_pane client_tty active_pane
    sidebar_pane="$(tmuxc list-panes -a -F '#{pane_id}|#{pane_title}' 2>/dev/null |
        awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }')"
    client_tty="$(tmuxc list-clients -F '#{client_control_mode}|#{client_tty}' 2>/dev/null |
        awk -F '|' '$1 != 1 { print $2; exit }')"
    active_pane="$(tmuxc display-message -p -t "$client_tty" '#{pane_id}' 2>/dev/null || true)"
    if [ -n "$sidebar_pane" ] && [ "$active_pane" = "$sidebar_pane" ]; then
        printf 'true\n'
    else
        printf 'false\n'
    fi
}

sidebar_pane_id()
{
    tmuxc list-panes -a -F '#{pane_id}|#{pane_title}' 2>/dev/null |
        awk -F '|' '$2 == "dotfiles-session-sidebar" { print $1; exit }'
}

wait_until()
{
    local description="$1" expected="$2" command_name="$3" deadline=$(( $(date +%s) + 20 ))
    shift 3
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if [ "$($command_name "$@" 2>/dev/null || true)" = "$expected" ]; then
            return 0
        fi
        sleep 0.05
    done
    test_log "wait.timeout description=$description expected=$expected state=$(tmux_state_snapshot)"
    printf 'ERROR: timeout waiting for %s (expected %s)\n' "$description" "$expected" >&2
    return 1
}

wait_for_sessions()
{
    local expected="$1" description="${2:-session count}" deadline=$(( $(date +%s) + 20 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        [ "$(count_sessions)" = "$expected" ] && return 0
        sleep 0.05
    done
    printf 'ERROR: timeout waiting for %s (got %s, expected %s)\n' \
        "$description" "$(count_sessions)" "$expected" >&2
    return 1
}

action_generation()
{
    tmuxc show-option -gqv '@dotfiles_sidebar_action_generation' 2>/dev/null || true
}

input_ready()
{
    tmuxc show-option -gqv '@dotfiles_sidebar_input_ready' 2>/dev/null || true
}

prompt_ready()
{
    tmuxc show-option -gqv '@dotfiles_sidebar_prompt_ready' 2>/dev/null || true
}

sidebar_input_ready()
{
    if [ "$(count_sidebars)" = 1 ] &&
        [ "$(input_ready)" = 1 ] &&
        [ "$(sidebar_is_active)" = true ]; then
        printf 'true\n'
    else
        printf 'false\n'
    fi
}

wait_for_prompt_ready()
{
    wait_until 'prompt readiness' 1 prompt_ready
}

wait_for_prompt_complete()
{
    wait_until 'prompt completion' 0 prompt_ready
}

wait_for_prompt_text()
{
    local expected="$1" deadline=$(( $(date +%s) + 20 )) capture
    while [ "$(date +%s)" -lt "$deadline" ]; do
        capture="$(tmuxc capture-pane -p -t "$(sidebar_pane_id)" 2>/dev/null || true)"
        printf '%s\n' "$capture" | grep -F --quiet "$expected" && return 0
        sleep 0.05
    done
    test_log "wait.prompt-text.timeout expected=$expected state=$(tmux_state_snapshot)"
    printf 'ERROR: timeout waiting for prompt text (%s)\n' "$expected" >&2
    return 1
}

wait_for_sidebar_input_ready()
{
    wait_until 'sidebar input readiness' true sidebar_input_ready
}

work_pane_count()
{
    local session_name="$1"
    tmuxc list-panes -t "=$session_name:" -F '#{pane_title}' 2>/dev/null |
        awk '$0 != "dotfiles-session-sidebar" { count++ } END { print count + 0 }'
}

session_window_layout()
{
    tmuxc display-message -p -t "=$1:" '#{window_layout}' 2>/dev/null || true
}

session_sidebar_width()
{
    tmuxc list-panes -t "=$1:" -F '#{pane_title}|#{pane_width}' 2>/dev/null |
        awk -F '|' '$1 == "dotfiles-session-sidebar" { print $2; exit }'
}

run_split_cycle_reproduction()
{
    local target_layout_before target_layout_after target_sidebar_width split_key split_label split_input

    if [ "$SPLIT_DIRECTION" = vertical ]; then
        split_key='_'
        split_label='vertical'
    else
        split_key='|'
        split_label='horizontal'
    fi

    # Match the normal user setup: focus the sidebar after the initial pane
    # split so that all following actions are physical PTY keyboard input.
    send_keys $'\001s'
    wait_until 'split-cycle sidebar toggle off' 0 count_sidebars
    send_keys $'\001s'
    wait_until 'split-cycle sidebar toggle on' 1 count_sidebars
    wait_for_sidebar_input_ready

    # Create three sessions exactly as a user does from the sidebar.
    for index in 1 2 3; do
        before_generation="$(action_generation)"
        send_keys 'c'
        wait_for_prompt_ready
        printf -v session_input 'split-cycle-%s' "$index"
        send_keys "$session_input"
        send_keys $'\r'
        wait_for_prompt_complete
        wait_for_action_generation_change "$before_generation"
        wait_for_sessions $((index + 1)) "split-cycle session $index creation"
    done
    wait_for_sessions 4 'split-cycle sessions'

    # The cursor is on split-cycle-3. Move to split-cycle-1 and select it.
    for ignored in 1 2; do
        before_generation="$(action_generation)"
        send_keys $'\033[B'
        wait_for_action_generation_change "$before_generation"
        wait_for_sidebar_input_ready
    done
    before_generation="$(action_generation)"
    send_keys $'\r'
    wait_for_action_generation_change "$before_generation"
    wait_until 'split-cycle target session' split-cycle-1 client_session
    wait_for_sidebar_input_ready

    # The wrapper split is the normal path. direct-layout deliberately uses
    # the raw tmux command path to reproduce a user invoking tmux directly.
    if [ "$SCENARIO" = direct-layout ]; then
        direct_work_pane="$(tmuxc list-panes -t '=split-cycle-1:' -F '#{pane_id}|#{pane_title}' |
            awk -F '|' '$2 != "dotfiles-session-sidebar" { print $1; exit }')"
        if [ "$SPLIT_DIRECTION" = vertical ]; then
            tmuxc split-window -t "$direct_work_pane" -v -c "$REPO_ROOT"
            tmuxc resize-pane -t "$direct_work_pane" -D 2
        else
            tmuxc split-window -t "$direct_work_pane" -h -c "$REPO_ROOT"
            tmuxc resize-pane -t "$direct_work_pane" -R 2
        fi
    else
        split_input=$'\001'"$split_key"
        send_keys "$split_input"
    fi
    wait_until "$split_label split in target session" 2 work_pane_count split-cycle-1
    # The split binding leaves focus in the newly-created work pane. In a
    # real terminal the user returns focus to the sidebar before navigating;
    # the standard tmux prefix-o pane rotation returns focus to the sidebar
    # without using tmux send-keys.
    send_keys $'\001o'
    wait_for_sidebar_input_ready
    target_sidebar_width="$(session_sidebar_width split-cycle-1)"
    target_layout_before="$(session_window_layout split-cycle-1)"
    test_log "split-cycle.after-split session=split-cycle-1 sidebar_width=$target_sidebar_width layout=$target_layout_before"

    # User action: select another session, then return to the split session.
    before_generation="$(action_generation)"
    send_keys $'\033[B'
    wait_for_action_generation_change "$before_generation"
    wait_for_sidebar_input_ready
    before_generation="$(action_generation)"
    send_keys $'\r'
    wait_for_action_generation_change "$before_generation"
    wait_until 'split-cycle second session' split-cycle-2 client_session
    wait_for_sidebar_input_ready

    before_generation="$(action_generation)"
    send_keys $'\033[A'
    wait_for_action_generation_change "$before_generation"
    wait_for_sidebar_input_ready
    before_generation="$(action_generation)"
    send_keys $'\r'
    wait_for_action_generation_change "$before_generation"
    wait_until 'split-cycle return session' split-cycle-1 client_session
    wait_for_sidebar_input_ready

    target_layout_after="$(session_window_layout split-cycle-1)"
    test_log "split-cycle.after-return session=split-cycle-1 sidebar_width=$(session_sidebar_width split-cycle-1) layout=$target_layout_after"
    if [ "$(count_sidebars)" != 1 ] ||
        [ "$(work_pane_count split-cycle-1)" != 2 ] ||
        [ "$(session_sidebar_width split-cycle-1)" != "$target_sidebar_width" ] ||
        [ "$target_layout_after" != "$target_layout_before" ]; then
        printf 'ERROR: split-cycle layout changed after leaving and returning to %s split session\n' "$split_label" >&2
        printf 'before: sidebars=%s work_panes=2 sidebar_width=%s layout=%s\n' \
            "$(count_sidebars)" "$target_sidebar_width" "$target_layout_before" >&2
        printf 'after:  sidebars=%s work_panes=%s sidebar_width=%s layout=%s\n' \
            "$(count_sidebars)" "$(work_pane_count split-cycle-1)" \
            "$(session_sidebar_width split-cycle-1)" "$target_layout_after" >&2
        return 1
    fi
    printf 'PASS: split-cycle preserved %s work split and sidebar geometry\n' "$split_label"
}

pane_identity_snapshot()
{
    tmuxc list-panes -t "=$1:" -F '#{pane_id}|#{pane_pid}|#{pane_current_command}|#{pane_current_path}|#{pane_title}' |
        awk '$5 != "dotfiles-session-sidebar" { print }' | sort
}

focus_sidebar_via_prefix()
{
    local attempt
    for attempt in 1 2 3 4 5 6; do
        if [ "$(sidebar_is_active)" = true ]; then
            return 0
        fi
        send_keys $'\001o'
        sleep 0.1
    done
    if [ "$(sidebar_is_active)" = true ]; then
        return 0
    fi
    return 1
}

run_arbitrary_topology_reproduction()
{
    local before after before_ids after_ids before_pids after_pids before_semantic after_semantic
    local previous_session_count restored_session_count

    # All actions that change the topology or session are sent through the
    # attached PTY, matching a user's prefix, shortcut, and TUI input path.
    send_keys $'\001s'
    wait_until 'arbitrary-topology sidebar toggle off' 0 count_sidebars
    send_keys $'\001s'
    wait_until 'arbitrary-topology sidebar toggle on' 1 count_sidebars
    wait_for_sidebar_input_ready

    for index in 1 2 3; do
        before_generation="$(action_generation)"
        send_keys 'c'
        wait_for_prompt_ready
        send_keys "topology-$index"
        send_keys $'\r'
        wait_for_prompt_complete
        wait_for_action_generation_change "$before_generation"
        wait_for_sessions $((index + 1)) "arbitrary topology session $index"
    done

    # The cursor is on topology-3. Select topology-1.
    for ignored in 1 2; do
        before_generation="$(action_generation)"
        send_keys $'\033[B'
        wait_for_action_generation_change "$before_generation"
        wait_for_sidebar_input_ready
    done
    before_generation="$(action_generation)"
    send_keys $'\r'
    wait_for_action_generation_change "$before_generation"
    wait_until 'arbitrary topology target session' topology-1 client_session
    wait_for_sidebar_input_ready

    # Build a non-linear work topology using the public wrapper bindings:
    # horizontal split, vertical split, then another horizontal split.
    for split_key in '|' '_' '|'; do
        send_keys $'\001'"$split_key"
        sleep 0.2
        focus_sidebar_via_prefix
        wait_for_sidebar_input_ready
    done
    [ "$(work_pane_count topology-1)" -eq 4 ] || {
        printf 'ERROR: arbitrary topology setup created %s work panes\n' "$(work_pane_count topology-1)" >&2
        return 1
    }
    slot=0
    while IFS='|' read -r pane_id pane_title; do
        [ "$pane_title" = "dotfiles-session-sidebar" ] && continue
        slot=$((slot + 1))
        tmuxc select-pane -t "$pane_id" -T "topology-slot-$slot"
    done < <(tmuxc list-panes -t '=topology-1:' -F '#{pane_id}|#{pane_title}')

    before="$(pane_identity_snapshot topology-1)"
    before_ids="$(printf '%s\n' "$before" | cut -d'|' -f1 | sort)"
    before_pids="$(printf '%s\n' "$before" | cut -d'|' -f2 | sort)"
    before_semantic="$(printf '%s\n' "$before" | cut -d'|' -f3-5 | sort)"
    test_log "arbitrary-topology.before panes=$(printf '%s' "$before" | tr '\n' ';')"

    # Leave and return through the sidebar, then archive/delete via d and
    # restore through o, exactly as in the user's workflow.
    before_generation="$(action_generation)"
    send_keys $'\033[B'
    wait_for_action_generation_change "$before_generation"
    wait_for_sidebar_input_ready
    before_generation="$(action_generation)"
    send_keys $'\r'
    wait_for_action_generation_change "$before_generation"
    wait_until 'arbitrary topology second session' topology-2 client_session
    wait_for_sidebar_input_ready
    before_generation="$(action_generation)"
    send_keys $'\033[A'
    wait_for_action_generation_change "$before_generation"
    wait_for_sidebar_input_ready
    before_generation="$(action_generation)"
    send_keys $'\r'
    wait_for_action_generation_change "$before_generation"
    wait_until 'arbitrary topology return session' topology-1 client_session
    wait_for_sidebar_input_ready

    previous_session_count="$(count_sessions)"
    before_generation="$(action_generation)"
    send_keys 'd'
    wait_for_prompt_ready
    send_keys $'y\r'
    wait_for_prompt_complete
    wait_for_action_generation_change "$before_generation"
    wait_for_session_count_below "$previous_session_count"
    wait_for_archives 1
    restored_session_count="$(count_sessions)"

    # Restore through the actual history key and Enter path after the delete
    # focus barrier has reasserted the surviving sidebar.
    wait_for_sidebar_input_ready
    before_generation="$(action_generation)"
    send_keys 'o'
    wait_for_action_generation_change "$before_generation"
    wait_for_sidebar_input_ready
    before_generation="$(action_generation)"
    send_keys $'\r'
    wait_for_action_generation_change "$before_generation"
    wait_for_session_count_above "$restored_session_count"
    wait_for_sidebar_input_ready
    wait_until 'arbitrary topology restored session' topology-1 client_session

    after="$(pane_identity_snapshot topology-1)"
    after_ids="$(printf '%s\n' "$after" | cut -d'|' -f1 | sort)"
    after_pids="$(printf '%s\n' "$after" | cut -d'|' -f2 | sort)"
    after_semantic="$(printf '%s\n' "$after" | cut -d'|' -f3-5 | sort)"
    test_log "arbitrary-topology.after panes=$(printf '%s' "$after" | tr '\n' ';')"
    printf 'INFO: arbitrary topology restored pane records:\n%s\n' "$after"
    [ "$(work_pane_count topology-1)" -eq 4 ] || {
        printf 'ERROR: arbitrary topology work-pane count was not restored\n' >&2
        return 1
    }
    [ "$before_semantic" = "$after_semantic" ] || {
        printf 'FAIL: arbitrary topology semantic pane mapping changed\n'
        printf 'before semantic: %s\n' "$before_semantic"
        printf 'after  semantic: %s\n' "$after_semantic"
        return 1
    }
    printf 'PASS: arbitrary topology preserved semantic pane mapping\n'
    printf 'INFO: physical pane IDs/PIDs were recreated as expected\n'
    printf 'before IDs: %s\n' "$before_ids"
    printf 'after  IDs: %s\n' "$after_ids"
    printf 'before PIDs: %s\n' "$before_pids"
    printf 'after  PIDs: %s\n' "$after_pids"
}

multi_window_count()
{
    tmuxc list-windows -t "=$1:" -F '#{window_index}' 2>/dev/null | wc -l | tr -d ' '
}

multi_window_snapshot()
{
    local session_name="$1"
    {
        printf 'windows\n'
        tmuxc list-windows -t "=$session_name:" -F 'window=#{window_index}|name=#{window_name}|active=#{window_active}|layout=#{window_layout}' 2>/dev/null
        printf 'panes\n'
        tmuxc list-panes -s -t "=$session_name" -F 'window=#{window_index}|name=#{window_name}|pane=#{pane_index}|left=#{pane_left}|top=#{pane_top}|width=#{pane_width}|height=#{pane_height}|active=#{pane_active}|path=#{pane_current_path}|command=#{pane_current_command}|title=#{pane_title}' 2>/dev/null |
            awk '$0 !~ /title=dotfiles-session-sidebar$/ { print }'
        printf 'sidebar\n'
        tmuxc list-panes -s -t "=$session_name" -F 'window=#{window_index}|pane=#{pane_id}|active=#{pane_active}|title=#{pane_title}' 2>/dev/null |
            awk '$0 ~ /title=dotfiles-session-sidebar$/ { print }'
    }
}

label_multi_window_panes()
{
    local session_name="$1" window_index pane_id pane_title slot=-1 last_window=''
    while IFS='|' read -r window_index pane_id pane_title; do
        [ -n "$pane_id" ] || continue
        [ "$pane_title" = dotfiles-session-sidebar ] && continue
        if [ "$window_index" != "$last_window" ]; then
            slot=0
            last_window="$window_index"
        else
            slot=$((slot + 1))
        fi
        tmuxc select-pane -t "$pane_id" -T "multi-window-w${window_index}-slot-${slot}"
    done < <(tmuxc list-panes -s -t "=$session_name" -F '#{window_index}|#{pane_id}|#{pane_title}' 2>/dev/null)
}

current_window_index()
{
    tmuxc display-message -p '#{window_index}' 2>/dev/null || true
}

run_multi_window_topology_reproduction()
{
    local before after before_windows after_windows before_panes after_panes
    local before_windows_semantic after_windows_semantic before_panes_semantic after_panes_semantic
    local before_sidebar after_sidebar archive_file archive_window_count archive_endwindow_count archive_pane_count
    local previous_session_count restored_session_count window_before window_after

    test_log 'multi-window.before.setup'
    send_keys $'\001s'
    wait_until 'multi-window sidebar toggle off' 0 count_sidebars
    send_keys $'\001s'
    wait_until 'multi-window sidebar toggle on' 1 count_sidebars
    wait_for_sidebar_input_ready

    # Keep a peer session available for the real sidebar leave/return path.
    for session_name in multi-window-peer multi-window-topology; do
        before_generation="$(action_generation)"
        send_keys 'c'
        wait_for_prompt_ready
        send_keys "$session_name"
        send_keys $'\r'
        wait_for_prompt_complete
        wait_for_action_generation_change "$before_generation"
    done
    wait_for_sessions 3 'multi-window session setup'

    # The second c leaves the target selected in the sidebar. Enter is still
    # sent through the attached PTY so the selection path is covered too.
    before_generation="$(action_generation)"
    send_keys $'\r'
    wait_for_action_generation_change "$before_generation"
    wait_until 'multi-window target session' multi-window-topology client_session
    wait_for_sidebar_input_ready

    # Window 0: four panes through the public split wrapper bindings.
    for split_key in '|' '_' '|'; do
        send_keys $'\001'"$split_key"
        sleep 0.2
        focus_sidebar_via_prefix
        wait_for_sidebar_input_ready
    done
    [ "$(work_pane_count multi-window-topology)" -eq 4 ] || {
        printf 'ERROR: multi-window window 0 setup created %s work panes\n' "$(work_pane_count multi-window-topology)" >&2
        return 1
    }

    # Ctrl+a c is the configured user shortcut for a new window. The new
    # window starts with one work pane and the managed sidebar is relocated by
    # the runtime hook.
    window_before="$(multi_window_count multi-window-topology)"
    send_keys $'\001c'
    wait_until 'multi-window second window' 2 multi_window_count multi-window-topology
    wait_until 'multi-window current window changed' 1 current_window_index

    # Window 1: a different four-pane topology, including the quote split
    # binding. This intentionally exercises more than one window layout. The
    # single shared sidebar remains in window 0, so these splits deliberately
    # stay in the work pane until we return to that window.
    for split_key in '_' '|' '"'; do
        send_keys $'\001'"$split_key"
        sleep 0.2
    done
    [ "$(work_pane_count multi-window-topology)" -eq 4 ] || {
        printf 'ERROR: multi-window window 1 setup created %s work panes\n' "$(work_pane_count multi-window-topology)" >&2
        return 1
    }
    # Tab is used here to return to window 0 because it is the deterministic
    # two-window cycle. BTab is validated separately below.
    send_keys $'\001\t'
    wait_until 'multi-window return to sidebar window' 0 current_window_index
    focus_sidebar_via_prefix
    wait_for_sidebar_input_ready
    # Give window-name preservation a deterministic semantic identity. This
    # observer-only setup disables tmux automatic rename for the fixture; all
    # topology-changing actions above still came through the attached PTY.
    tmuxc set-window-option -t '=multi-window-topology:0' automatic-rename off
    tmuxc set-window-option -t '=multi-window-topology:1' automatic-rename off
    tmuxc rename-window -t '=multi-window-topology:0' 'multi-window-main'
    tmuxc rename-window -t '=multi-window-topology:1' 'multi-window-alt'
    label_multi_window_panes multi-window-topology
    focus_sidebar_via_prefix
    wait_for_sidebar_input_ready

    before="$(multi_window_snapshot multi-window-topology)"
    before_windows="$(printf '%s\n' "$before" | sed -n '/^windows$/,/^panes$/p')"
    before_panes="$(printf '%s\n' "$before" | sed -n '/^panes$/,/^sidebar$/p')"
    before_windows_semantic="$(printf '%s\n' "$before_windows" | sed -E 's/\|layout=.*$//')"
    before_panes_semantic="$(printf '%s\n' "$before_panes" | sed -E '/^panes$/d; s/\|pane=[^|]*//')"
    before_sidebar="$(printf '%s\n' "$before" | sed -n '/^sidebar$/,$p' | sed -E '/^sidebar$/d; s/\|pane=[^|]*//')"
    test_log "multi-window.before windows=$(printf '%s' "$before_windows" | tr '\n' ';') panes=$(printf '%s' "$before_panes" | tr '\n' ';')"

    # Exercise next/previous window through the actual prefix and configured
    # Tab/BTab shortcuts before changing sessions.
    window_before="$(current_window_index)"
    send_keys $'\001\t'
    wait_until 'multi-window next-window shortcut' 1 current_window_index
    test_log "multi-window.window-next from=$window_before to=$(current_window_index)"
    send_keys $'\001\033[Z'
    wait_until 'multi-window previous-window shortcut' 0 current_window_index
    test_log "multi-window.window-previous to=$(current_window_index)"

    # Leave and return through the sidebar, then archive/delete and restore.
    before_generation="$(action_generation)"
    send_keys $'\033[A'
    wait_for_action_generation_change "$before_generation"
    wait_for_sidebar_input_ready
    before_generation="$(action_generation)"
    send_keys $'\r'
    wait_for_action_generation_change "$before_generation"
    wait_until 'multi-window peer session' multi-window-peer client_session
    test_log 'multi-window.switch-away target=multi-window-peer'
    wait_for_sidebar_input_ready
    before_generation="$(action_generation)"
    send_keys $'\033[B'
    wait_for_action_generation_change "$before_generation"
    before_generation="$(action_generation)"
    send_keys $'\r'
    wait_for_action_generation_change "$before_generation"
    wait_until 'multi-window return session' multi-window-topology client_session
    test_log 'multi-window.switch-back target=multi-window-topology'
    wait_for_sidebar_input_ready

    previous_session_count="$(count_sessions)"
    before_generation="$(action_generation)"
    test_log 'multi-window.archive.begin'
    send_keys 'd'
    wait_for_prompt_ready
    send_keys $'y\r'
    wait_for_prompt_complete
    wait_for_action_generation_change "$before_generation"
    wait_for_session_count_below "$previous_session_count"
    wait_for_archives 1
    archive_file="$(find "$HISTORY_DIR" -maxdepth 1 -type f -name '*.tsv' -print 2>/dev/null | sort | tail -1)"
    archive_window_count="$(awk -F '\t' '$1 == "window" { count++ } END { print count + 0 }' "$archive_file")"
    archive_endwindow_count="$(awk -F '\t' '$1 == "endwindow" { count++ } END { print count + 0 }' "$archive_file")"
    archive_pane_count="$(awk -F '\t' '$1 == "pane" { count++ } END { print count + 0 }' "$archive_file")"
    test_log "multi-window.archive.metadata file=$archive_file windows=$archive_window_count endwindows=$archive_endwindow_count panes=$archive_pane_count"
    [ "$archive_window_count" -eq 2 ] && [ "$archive_endwindow_count" -eq 2 ] && [ "$archive_pane_count" -eq 8 ] || {
        printf 'ERROR: archive did not contain complete multi-window metadata (windows=%s endwindows=%s panes=%s)\n' \
            "$archive_window_count" "$archive_endwindow_count" "$archive_pane_count" >&2
        return 1
    }
    restored_session_count="$(count_sessions)"
    wait_for_sidebar_input_ready
    before_generation="$(action_generation)"
    test_log 'multi-window.restore.begin'
    send_keys 'o'
    wait_for_action_generation_change "$before_generation"
    wait_for_sidebar_input_ready
    before_generation="$(action_generation)"
    send_keys $'\r'
    wait_for_action_generation_change "$before_generation"
    wait_for_session_count_above "$restored_session_count"
    wait_until 'multi-window restored session' multi-window-topology client_session
    wait_for_sidebar_input_ready

    label_multi_window_panes multi-window-topology
    after="$(multi_window_snapshot multi-window-topology)"
    after_windows="$(printf '%s\n' "$after" | sed -n '/^windows$/,/^panes$/p')"
    after_panes="$(printf '%s\n' "$after" | sed -n '/^panes$/,/^sidebar$/p')"
    after_windows_semantic="$(printf '%s\n' "$after_windows" | sed -E 's/\|layout=.*$//')"
    after_panes_semantic="$(printf '%s\n' "$after_panes" | sed -E '/^panes$/d; s/\|pane=[^|]*//')"
    after_sidebar="$(printf '%s\n' "$after" | sed -n '/^sidebar$/,$p' | sed -E '/^sidebar$/d; s/\|pane=[^|]*//')"
    test_log "multi-window.after windows=$(printf '%s' "$after_windows" | tr '\n' ';') panes=$(printf '%s' "$after_panes" | tr '\n' ';')"
    test_log "multi-window.semantic-diff before=$(printf '%s' "$before" | tr '\n' ';') after=$(printf '%s' "$after" | tr '\n' ';')"
    printf 'INFO: multi-window before metadata:\n%s\n' "$before"
    printf 'INFO: multi-window after metadata:\n%s\n' "$after"

    if [ "$before_windows_semantic" != "$after_windows_semantic" ] ||
        [ "$before_panes_semantic" != "$after_panes_semantic" ] ||
        [ "$before_sidebar" != "$after_sidebar" ]; then
        printf 'FAIL: multi-window topology metadata changed across archive/restore\n'
        printf 'before windows semantic:\n%s\n' "$before_windows_semantic"
        printf 'after windows semantic:\n%s\n' "$after_windows_semantic"
        printf 'before panes semantic:\n%s\n' "$before_panes_semantic"
        printf 'after panes semantic:\n%s\n' "$after_panes_semantic"
        printf 'before sidebar semantic:\n%s\n' "$before_sidebar"
        printf 'after sidebar semantic:\n%s\n' "$after_sidebar"
        return 1
    fi
    printf 'PASS: multi-window topology and active-window sidebar metadata preserved\n'
}

wait_for_action_generation_change()
{
    local previous="$1" deadline=$(( $(date +%s) + 20 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        [ "$(action_generation)" != "$previous" ] && return 0
        sleep 0.05
    done
    test_log "wait.action.timeout previous=$previous generation=$(action_generation) input_ready=$(input_ready) prompt_ready=$(prompt_ready) input_log_tail=$(input_log_tail_hex) state=$(tmux_state_snapshot)"
    printf 'ERROR: timeout waiting for action generation change\n' >&2
    return 1
}

wait_for_archives()
{
    local expected="$1" deadline=$(( $(date +%s) + 20 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        [ "$(count_archives)" -ge "$expected" ] && return 0
        sleep 0.05
    done
    printf 'ERROR: timeout waiting for at least %s archives (got %s)\n' "$expected" "$(count_archives)" >&2
    return 1
}

wait_for_session_count_below()
{
    local previous="$1" deadline=$(( $(date +%s) + 20 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        [ "$(count_sessions)" -lt "$previous" ] && return 0
        sleep 0.05
    done
    test_log "wait.sessions.below.timeout previous=$previous current=$(count_sessions) state=$(tmux_state_snapshot)"
    return 1
}

wait_for_session_count_above()
{
    local previous="$1" deadline=$(( $(date +%s) + 20 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        [ "$(count_sessions)" -gt "$previous" ] && return 0
        sleep 0.05
    done
    test_log "wait.sessions.above.timeout previous=$previous current=$(count_sessions) state=$(tmux_state_snapshot)"
    return 1
}

operation_state()
{
    tmuxc show-option -gqv '@dotfiles_sidebar_operation' 2>/dev/null || true
}

wait_for_operation_quiet()
{
    local deadline=$(( $(date +%s) + 20 )) state
    while [ "$(date +%s)" -lt "$deadline" ]; do
        state="$(operation_state)"
        case "$state" in
            idle:*|failed:*) return 0 ;;
        esac
        sleep 0.05
    done
    test_log "wait.operation-quiet.timeout state=$(operation_state)"
    return 1
}

send_keys()
{
    # ATTACHED[1] is the stdin of `script`; script forwards it to the tmux
    # client's controlling PTY, so this is not a tmux send-keys shortcut.
    local payload="$1"
    INPUT_SEQUENCE=$((INPUT_SEQUENCE + 1))
    if [ "$TEST_TRACE_VERBOSE" = true ]; then
        test_log "send.state=$(tmux_state_snapshot)"
    fi
    test_log "input.send.begin seq=$INPUT_SEQUENCE bytes=$(printf '%b' "$payload" | od -An -tx1 | tr -d ' \n') telemetry=$(client_telemetry)"
    printf '%b' "$payload" >&"${ATTACHED[1]}"
    test_log "input.send.end seq=$INPUT_SEQUENCE telemetry=$(client_telemetry)"
}

run_rapid_operations_reproduction()
{
    local iteration before_generation previous_session_count
    local trace_before trace_rejected

    for iteration in 1 2 3; do
        before_generation="$(action_generation)"
        send_keys 'c'
        wait_for_prompt_ready
        send_keys "rapid-$iteration"
        send_keys $'\r'
        wait_for_prompt_complete
        wait_for_action_generation_change "$before_generation"

        previous_session_count="$(count_sessions)"
        trace_before="$(grep -c 'input.rejected.*reason=operation-complete-drain' "$RUN_DIR/trace.log" 2>/dev/null || true)"
        trace_before="${trace_before:-0}"
        before_generation="$(action_generation)"
        send_keys 'd'
        wait_for_prompt_ready
        send_keys $'y\r'
        if [ "$iteration" -eq 2 ]; then
            # A pending navigation must not switch sessions after delete.
            send_keys $'\033[B\r'
        else
            # A pending history request must not restore a stale archive.
            send_keys $'o\033[B\r'
        fi
        wait_for_prompt_complete
        wait_for_session_count_below "$previous_session_count"
        wait_for_operation_quiet
        wait_for_sidebar_input_ready
        trace_rejected="$(grep -c 'input.rejected.*reason=operation-complete-drain' "$RUN_DIR/trace.log" 2>/dev/null || true)"
        trace_rejected="${trace_rejected:-0}"
        [ "$trace_rejected" -gt "$trace_before" ] || {
            printf 'ERROR: rapid delete input was not rejected (iteration %s)\n' "$iteration" >&2
            return 1
        }
        [ "$(count_sidebars)" = 1 ] || {
            printf 'ERROR: rapid delete changed sidebar uniqueness (iteration %s)\n' "$iteration" >&2
            return 1
        }

        before_generation="$(action_generation)"
        send_keys 'o'
        wait_for_action_generation_change "$before_generation"
        previous_session_count="$(count_sessions)"
        before_generation="$(action_generation)"
        send_keys $'\r'
        # Navigation typed while restore is busy is intentionally discarded.
        send_keys $'\033[B\r'
        wait_for_action_generation_change "$before_generation"
        wait_for_session_count_above "$previous_session_count"
        wait_for_operation_quiet
        wait_for_sidebar_input_ready
        [ "$(count_sidebars)" = 1 ] || {
            printf 'ERROR: rapid restore changed sidebar uniqueness (iteration %s)\n' "$iteration" >&2
            return 1
        }
        send_keys $'\033'
        wait_for_sidebar_input_ready
    done

    printf 'PASS: rapid d→o/session navigation input is rejected during delete (3 iterations)\n'
    printf 'PASS: rapid restore→navigation input is rejected during restore (3 iterations)\n'
}

tmuxc new-session -d -s keyboard-anchor -c "$REPO_ROOT" 'sleep 300'
if [ "$SCENARIO" = minimal ]; then
    tmuxc new-session -d -s keyboard-target -c "$REPO_ROOT" 'sleep 300'
fi
tmuxc set-environment -g TMUX_SESSION_HISTORY_DIR "$HISTORY_DIR"
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_DEBUG "${TMUX_SESSION_LAUNCHER_DEBUG:-0}"
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_DEBUG_FILE "$RUN_DIR/debug.log"
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_TRACE "${TMUX_SESSION_LAUNCHER_TRACE:-0}"
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_TRACE_FILE "${TMUX_SESSION_LAUNCHER_TRACE_FILE:-$RUN_DIR/trace.log}"
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_TEST_OPERATION_DELAY "${TMUX_SESSION_LAUNCHER_TEST_OPERATION_DELAY:-0}"
tmuxc split-window -d -t '=keyboard-anchor:' -h -b -l 35 "$LAUNCHER --sidebar"
test_log 'step=sidebar.start'
test_log "transport=$TRANSPORT"
wait_until 'initial sidebar' 1 count_sidebars

# A real attached client is created through the selected transport. Its stdin
# remains writable through the coprocess descriptor.
if [ "$TRANSPORT" = bridge ]; then
    coproc ATTACHED {
        HOME="$HOME_DIR" "$PTY_BRIDGE_BIN" --log "$BRIDGE_LOG" --output "$CLIENT_LOG" -- \
            tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf" attach-session -t keyboard-anchor
    }
else
    coproc ATTACHED {
        if [ "$TRACE_MODE" = strace ]; then
            TERM=xterm strace -ff -ttt -yy -o "$SYSCALL_LOG" \
                -e trace=read,write,ioctl,poll,ppoll,select,pselect6,fcntl,signal,rt_sigaction,rt_sigprocmask,wait4 \
                script -qefc "env -u LD_PRELOAD HOME='$HOME_DIR' tmux -L '$SOCKET' -f '$REPO_ROOT/dotfiles/tmux.conf' attach-session -t keyboard-anchor" \
                --log-in "$INPUT_LOG" --log-out "$CLIENT_LOG" >/dev/null 2>&1
        elif [ "$TRACE_MODE" = preload ]; then
            TMUX_KEYBOARD_INTERPOSER_LOG="$INTERPOSER_LOG" LD_PRELOAD="$INTERPOSER_BIN" \
                TERM=xterm script -qefc "HOME='$HOME_DIR' tmux -L '$SOCKET' -f '$REPO_ROOT/dotfiles/tmux.conf' attach-session -t keyboard-anchor" \
                --log-in "$INPUT_LOG" --log-out "$CLIENT_LOG" >/dev/null 2>&1
        else
            TERM=xterm script -qefc "env -u LD_PRELOAD HOME='$HOME_DIR' tmux -L '$SOCKET' -f '$REPO_ROOT/dotfiles/tmux.conf' attach-session -t keyboard-anchor" \
                --log-in "$INPUT_LOG" --log-out "$CLIENT_LOG" >/dev/null 2>&1
        fi
    }
fi
sleep 0.3

# A control-mode client observes tmux notifications without being treated as
# the user's input client. All client selectors above explicitly exclude it.
coproc TMUX_OBSERVER {
    TERM=xterm HOME="$HOME_DIR" tmux -C -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf" attach-session -t keyboard-anchor
}
OBSERVER_PID="$TMUX_OBSERVER_PID"
exec {OBSERVER_FD}<&"${TMUX_OBSERVER[0]}"
observer_read_loop &
OBSERVER_LOG_PID=$!
sleep 0.1
test_log "observer.started pid=$OBSERVER_PID"

if [ "$SCENARIO" = rapid-operations ]; then
    run_rapid_operations_reproduction
    exit 0
fi

if [ "$SCENARIO" = split-cycle ] || [ "$SCENARIO" = direct-layout ]; then
    run_split_cycle_reproduction
    exit 0
fi

if [ "$SCENARIO" = arbitrary-topology ]; then
    run_arbitrary_topology_reproduction
    exit 0
fi

if [ "$SCENARIO" = multi-window-topology ]; then
    run_multi_window_topology_reproduction
    exit 0
fi

if [ "$SCENARIO" = minimal ]; then
    # Isolate the first post-switch Down from the longer workflow. This must
    # use the attached PTY transport, not tmux send-keys.
    send_keys $'\001s'
    wait_until 'minimal sidebar toggle off' 0 count_sidebars
    send_keys $'\001s'
    wait_until 'minimal sidebar toggle on' 1 count_sidebars
    wait_for_sidebar_input_ready
    before_generation="$(action_generation)"
    send_keys $'\033[B'
    wait_for_action_generation_change "$before_generation"
    send_keys $'\r'
    wait_until 'minimal target session switch' keyboard-target client_session
    before_generation="$(action_generation)"
    send_keys $'\033[B'
    wait_for_action_generation_change "$before_generation"
    printf 'PASS: minimal post-switch Down reached sidebar input (%s transport)\n' "$TRANSPORT"
    exit 0
fi

# Ctrl+a, s: exercise the configured tmux prefix and binding. Since the
# sidebar already exists, this is also the user's normal toggle-off path.
send_keys $'\001s'
wait_until 'sidebar toggle off' 0 count_sidebars
test_log 'step=sidebar.off'

# Ctrl+a, s again: restore the always-on sidebar and leave focus in its TUI.
send_keys $'\001s'
wait_until 'sidebar toggle on' 1 count_sidebars
wait_for_sidebar_input_ready
test_log 'step=sidebar.on'

# c + name + Enter, six times.
for index in 1 2 3 4 5 6; do
    before_generation="$(action_generation)"
    send_keys 'c'
    wait_for_prompt_ready
    printf -v session_input 'keyboard-%s' "$index"
    send_keys "$session_input"
    if [ "$index" -eq 1 ]; then
        prompt_capture="$(tmuxc capture-pane -p -t "$(sidebar_pane_id)")"
        printf '%s\n' "$prompt_capture" | grep -F --quiet "New: $session_input"
        printf 'PASS: c visibly echoes the typed session name\n'
    fi
    send_keys $'\r'
    wait_for_prompt_complete
    wait_for_action_generation_change "$before_generation"
    wait_for_sessions $((index + 1)) "keyboard session $index creation"
done
wait_for_sessions 7 'six keyboard-created sessions plus anchor'
test_log 'step=create.complete sessions=7'
printf 'PASS: Ctrl+a s toggles one sidebar through an attached PTY\n'
printf 'PASS: c creates six named sessions using keyboard input\n'

# After creation the cursor is on keyboard-6. Move twice to keyboard-1, then
# once per target. This avoids treating the anchor self-selection as a switch
# and makes every Enter target explicit.
targets=(keyboard-1 keyboard-2 keyboard-3 keyboard-4 keyboard-5 keyboard-6)
for index in "${!targets[@]}"; do
    moves=1
    [ "$index" -eq 0 ] && moves=2
    for ignored in $(seq 1 "$moves"); do
        before_generation="$(action_generation)"
        send_keys $'\033[B'
        wait_for_action_generation_change "$before_generation"
        wait_for_sidebar_input_ready
    done
    before_generation="$(action_generation)"
    send_keys $'\r'
    wait_for_action_generation_change "$before_generation"
    wait_until "keyboard target ${targets[$index]}" "${targets[$index]}" client_session
    wait_for_sidebar_input_ready
done
printf 'PASS: arrow navigation and Enter switch sessions six times\n'
test_log 'step=switch.complete'

# Re-anchor the client without bypassing the UI. This prevents the deliberate
# current-session delete path (which exits the launcher after client handoff)
# from being mistaken for a keyboard input failure in the bulk-delete phase.
before_generation="$(action_generation)"
send_keys $'\033[B'
wait_for_action_generation_change "$before_generation"
wait_for_sidebar_input_ready
before_generation="$(action_generation)"
send_keys $'\r'
wait_for_action_generation_change "$before_generation"
wait_until 'return to anchor' keyboard-anchor client_session
[ "$(client_session)" = keyboard-anchor ] || {
    printf 'ERROR: could not return to anchor through keyboard selection\n' >&2
    exit 1
}
wait_for_sidebar_input_ready

# Delete the six non-anchor sessions one by one and archive each one. Selection
# can be re-aligned by the TUI after a cross-session move, so keep using the
# same physical Down/d/confirm sequence until only the anchor remains.
delete_attempt=0
while [ "$(count_sessions)" -gt 1 ]; do
    delete_attempt=$((delete_attempt + 1))
    [ "$delete_attempt" -le 12 ] || {
        printf 'ERROR: keyboard deletion made no progress\n' >&2
        exit 1
    }
    previous_session_count="$(count_sessions)"
    wait_for_sidebar_input_ready
    before_generation="$(action_generation)"
    send_keys $'\033[B'
    wait_for_action_generation_change "$before_generation"
    wait_for_sidebar_input_ready
    before_generation="$(action_generation)"
    send_keys 'd'
    wait_for_prompt_ready
    send_keys $'y\r'
    wait_for_prompt_complete
    wait_for_action_generation_change "$before_generation"
    wait_for_session_count_below "$previous_session_count" || {
        printf 'ERROR: keyboard deletion made no progress (attempt %s)\n' "$delete_attempt" >&2
        exit 1
    }
    wait_for_sidebar_input_ready
done
wait_for_sessions 1 'six deleted sessions'
wait_for_archives 6
printf 'PASS: d + y + Enter archives and deletes six sessions\n'
test_log 'step=delete.complete sessions=1 archives=6'

# o enters history. The launcher waits for each async sidebar transition before
# accepting the next action, so six physical Down + Enter pairs restore six
# distinct archives without changing the user's input sequence.
before_generation="$(action_generation)"
send_keys 'o'
wait_for_action_generation_change "$before_generation"
wait_for_sidebar_input_ready
for ignored in 1 2 3 4 5 6; do
    previous_session_count="$(count_sessions)"
    before_generation="$(action_generation)"
    send_keys $'\033[B'
    wait_for_action_generation_change "$before_generation"
    wait_for_sidebar_input_ready
    before_generation="$(action_generation)"
    send_keys $'\r'
    wait_for_action_generation_change "$before_generation"
    wait_for_session_count_above "$previous_session_count" || {
        printf 'ERROR: keyboard restore made no progress (iteration %s)\n' "$ignored" >&2
        exit 1
    }
    wait_for_sidebar_input_ready
done
wait_for_sessions 7 'six restored sessions plus anchor'
printf 'PASS: o plus arrow navigation and Enter restores six archives\n'
test_log 'step=restore.complete sessions=7'

# Restoring keeps the history view open. Return to the session list before
# exercising the final session-level d + All shutdown sequence.
before_generation="$(action_generation)"
send_keys $'\033'
wait_for_action_generation_change "$before_generation"
wait_for_sidebar_input_ready

# d, All, Enter, y, Enter: archive and terminate every remaining session.
send_keys 'd'
wait_for_prompt_ready
send_keys $'All\r'
wait_for_prompt_text 'Save Session?'
send_keys $'y\r'
# The final confirmation terminates the tmux server, so the sidebar option
# disappears before a prompt-complete poll can observe the value 0.
local_deadline=$(( $(date +%s) + 20 ))
while [ "$(date +%s)" -lt "$local_deadline" ]; do
    tmuxc list-sessions >/dev/null 2>&1 || break
    sleep 0.05
done
if tmuxc list-sessions >/dev/null 2>&1; then
    printf 'ERROR: All deletion did not terminate the tmux server\n' >&2
    exit 1
fi
printf 'PASS: d + All + Enter + y + Enter terminates all sessions\n'
