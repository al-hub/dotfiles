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
    full|minimal) ;;
    *)
        printf 'TMUX_KEYBOARD_E2E_SCENARIO must be full or minimal\n' >&2
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

wait_for_sidebar_input_ready()
{
    wait_until 'sidebar input readiness' true sidebar_input_ready
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

tmuxc new-session -d -s keyboard-anchor -c "$REPO_ROOT" 'sleep 300'
if [ "$SCENARIO" = minimal ]; then
    tmuxc new-session -d -s keyboard-target -c "$REPO_ROOT" 'sleep 300'
fi
tmuxc set-environment -g TMUX_SESSION_HISTORY_DIR "$HISTORY_DIR"
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_DEBUG "${TMUX_SESSION_LAUNCHER_DEBUG:-0}"
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_DEBUG_FILE "$RUN_DIR/debug.log"
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_TRACE "${TMUX_SESSION_LAUNCHER_TRACE:-0}"
tmuxc set-environment -g TMUX_SESSION_LAUNCHER_TRACE_FILE "${TMUX_SESSION_LAUNCHER_TRACE_FILE:-$RUN_DIR/trace.log}"
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
    printf -v session_input 'keyboard-%s\r' "$index"
    send_keys "$session_input"
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
wait_for_prompt_complete
wait_for_prompt_ready
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
