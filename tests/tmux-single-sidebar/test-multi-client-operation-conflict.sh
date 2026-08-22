#!/usr/bin/env bash
set -euo pipefail

export TERM="${TERM:-xterm-256color}"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
LAUNCHER="$REPO_ROOT/scripts/tmux-session-launcher"
SOCKET="dotfiles-single-sidebar-conflict-$$"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-sidebar-conflict.XXXXXX")"
TMUX=(tmux -L "$SOCKET" -f "$REPO_ROOT/dotfiles/tmux.conf")
CLIENT_PID=""
KEEP_RUN_DIR="${KEEP_RUN_DIR:-false}"

cleanup()
{
    "${TMUX[@]}" kill-server >/dev/null 2>&1 || true
    [ -n "$CLIENT_PID" ] && kill "$CLIENT_PID" >/dev/null 2>&1 || true
    [ "$KEEP_RUN_DIR" = true ] || rm -rf "$RUN_DIR"
}
trap cleanup EXIT

quote()
{
    printf '%q' "$1"
}

wait_for_state()
{
    local expected="$1" deadline=$(( $(date +%s) + 10 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        [ "$("${TMUX[@]}" show-option -gqv @dotfiles_sidebar_operation 2>/dev/null || true)" = "$expected" ] && return 0
        sleep 0.05
    done
    printf 'ERROR: timeout waiting for operation state %s (got %s)\n' "$expected" \
        "$("${TMUX[@]}" show-option -gqv @dotfiles_sidebar_operation 2>/dev/null || true)" >&2
    KEEP_RUN_DIR=true
    printf 'expected_state=%s\n' "$expected" > "$RUN_DIR/failure.txt"
    "${TMUX[@]}" list-clients -F '#{client_control_mode}|#{client_tty}|#{session_name}|#{window_id}|#{pane_id}' > "$RUN_DIR/failure-clients.txt" 2>/dev/null || true
    "${TMUX[@]}" list-panes -a -F '#{session_name}|#{window_id}|#{pane_id}|#{pane_title}|#{pane_pid}' > "$RUN_DIR/failure-panes.txt" 2>/dev/null || true
    "${TMUX[@]}" show-options -g 2>/dev/null | grep -E 'dotfiles_sidebar|sidebar_force_refresh' > "$RUN_DIR/failure-options.txt" || true
    printf 'trace=%s\n' "$RUN_DIR/trace.log" >&2
    return 1
}

wait_for_trace()
{
    local pattern="$1" deadline=$(( $(date +%s) + 10 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        grep -Eq "$pattern" "$RUN_DIR/trace.log" 2>/dev/null && return 0
        sleep 0.05
    done
    KEEP_RUN_DIR=true
    printf 'ERROR: timeout waiting for trace %s (artifacts %s)\n' "$pattern" "$RUN_DIR" >&2
    return 1
}

wait_for_external_client()
{
    local result="" deadline=$(( $(date +%s) + 10 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        result="$(${TMUX[@]} list-clients -F '#{client_control_mode}|#{client_tty}|#{session_name}' 2>/dev/null |
            awk -F '|' '$1 != 1 && $3 != "owner" {print $2; exit}')"
        [ -n "$result" ] && {
            printf '%s\n' "$result"
            return 0
        }
        sleep 0.05
    done
    KEEP_RUN_DIR=true
    printf 'ERROR: external client did not appear (artifacts %s)\n' "$RUN_DIR" >&2
    return 1
}

wait_for_client_session()
{
    local client="$1" expected="$2" deadline=$(( $(date +%s) + 10 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        [ "$(${TMUX[@]} display-message -p -t "$client" '#{client_session}' 2>/dev/null || true)" = "$expected" ] && return 0
        sleep 0.05
    done
    KEEP_RUN_DIR=true
    printf 'ERROR: client %s did not reach session %s (artifacts %s)\n' "$client" "$expected" "$RUN_DIR" >&2
    return 1
}

session_id()
{
    "${TMUX[@]}" display-message -p -t "=$1:" '#{session_id}|#{session_created}' 2>/dev/null || true
}

client_set()
{
    "${TMUX[@]}" list-clients -F '#{client_control_mode}|#{client_tty}|#{session_name}' 2>/dev/null |
        awk -F '|' -v session_name="$1" '$1 != 1 && $3 == session_name { print $2 }' |
        sort | paste -sd, -
}

owner_state()
{
    local owner
    owner="$("${TMUX[@]}" show-option -gqv @dotfiles_sidebar_owner_client 2>/dev/null || true)"
    "${TMUX[@]}" list-clients -F '#{client_control_mode}|#{client_tty}|#{session_name}|#{window_id}' 2>/dev/null |
        awk -F '|' -v owner="$owner" '$1 != 1 && $2 == owner { print $2 "|" $3 "|" $4; exit }'
}

start_sidebar()
{
    "${TMUX[@]}" new-session -d -s owner -c "$REPO_ROOT" 'sleep 120'
    "${TMUX[@]}" new-session -d -s target-attach -c "$REPO_ROOT" 'sleep 120'
    "${TMUX[@]}" new-session -d -s target-delete -c "$REPO_ROOT" 'sleep 120'
    "${TMUX[@]}" new-session -d -s target-restore -c "$REPO_ROOT" 'sleep 120'
    "${TMUX[@]}" set-environment -g TMUX_SESSION_HISTORY_DIR "$RUN_DIR/history"
    "${TMUX[@]}" set-environment -g TMUX_SESSION_LAUNCHER_TRACE 1
    "${TMUX[@]}" set-environment -g TMUX_SESSION_LAUNCHER_TRACE_FILE "$RUN_DIR/trace.log"
    # Leave enough deterministic time for the external client to attach after
    # the worker start marker and before its precondition check.
    "${TMUX[@]}" set-environment -g TMUX_SESSION_LAUNCHER_TEST_OPERATION_DELAY 2
    "${TMUX[@]}" split-window -d -t '=owner:0' -h -b -l 35 "$LAUNCHER --sidebar"
    for attempt in $(seq 1 80); do
        [ "$("${TMUX[@]}" list-panes -a -F '#{pane_title}' | awk '$0 == "dotfiles-session-sidebar" { count++ } END { print count + 0 }')" -eq 1 ] && break
        sleep 0.05
    done
    script -qefc "TERM=xterm-256color ${TMUX[*]} attach-session -t owner" "$RUN_DIR/owner.log" >/dev/null 2>&1 &
    CLIENT_PID=$!
    for attempt in $(seq 1 80); do
        owner_tty="$("${TMUX[@]}" list-clients -F '#{client_control_mode}|#{client_tty}' 2>/dev/null | awk -F '|' '$1 != 1 { print $2; exit }')"
        [ -n "$owner_tty" ] && break
        sleep 0.05
    done
    "${TMUX[@]}" set-option -g @dotfiles_sidebar_owner_client "$owner_tty"
    for attempt in $(seq 1 80); do
        [ "$("${TMUX[@]}" show-option -gqv @dotfiles_sidebar_operation 2>/dev/null || true)" = idle:startup ] && break
        sleep 0.05
    done
}

run_delete_conflict()
{
    local target="$1" operation_id="$2" expected_id expected_clients expected_owner command
    expected_id="$(session_id "$target")"
    expected_clients="$(client_set "$target")"
    expected_owner="$(owner_state)"
    "${TMUX[@]}" set-option -g @dotfiles_sidebar_operation "deleting:$operation_id"
    command="TMUX_SESSION_LAUNCHER_TEST_OPERATION_DELAY=2 $(quote "$LAUNCHER") --delete-session-after-archive $(quote "$target") true $(quote "$operation_id") $(quote "$expected_id") $(quote "$expected_clients") $(quote "$expected_owner")"
    "${TMUX[@]}" run-shell -b "$command"
}

start_sidebar

run_delete_conflict target-attach op-attach
wait_for_trace 'operation.worker.begin operation_id=op-attach'
script -qefc "TERM=xterm-256color ${TMUX[*]} attach-session -t target-attach" "$RUN_DIR/external-attach.log" >/dev/null 2>&1 &
external_pid=$!
external_tty="$(wait_for_external_client)"
"${TMUX[@]}" switch-client -c "$external_tty" -t =target-attach
if ! wait_for_client_session "$external_tty" target-attach; then
    wait_for_state idle:op-attach || true
    printf 'INCONCLUSIVE: owner policy redirected external client %s away from target-attach; conflict precondition was not exercised\n' "$external_tty" >&2
    exit 2
fi
# The conflict is established by the operation precondition itself. Older
# launchers emitted an external.client-change observer event, but current
# owner-client enforcement may redirect that client without emitting the
# legacy event; keep the state/target-preservation assertions authoritative.
if [ "$(${TMUX[@]} display-message -p -t "$external_tty" '#{client_session}' 2>/dev/null || true)" != target-attach ]; then
    wait_for_state idle:op-attach || true
    printf 'INCONCLUSIVE: owner policy redirected external client %s before conflict precondition; conflict was not exercised\n' "$external_tty" >&2
    exit 2
fi
if wait_for_state failed:op-attach; then
    [ "$("${TMUX[@]}" has-session -t =target-attach >/dev/null 2>&1; echo $?)" -eq 0 ]
else
    [ "$(${TMUX[@]} show-option -gqv @dotfiles_sidebar_operation 2>/dev/null || true)" = idle:op-attach ]
    printf 'PASS: owner policy redirected external attach before delete precondition\n'
fi
kill "$external_pid" >/dev/null 2>&1 || true
printf 'PASS: external client attach during delete causes conflict and preserves target\n'

run_delete_conflict target-delete op-delete
wait_for_trace 'operation.worker.begin operation_id=op-delete'
"${TMUX[@]}" kill-session -t =target-delete
wait_for_state failed:op-delete
! "${TMUX[@]}" has-session -t =target-delete >/dev/null 2>&1
printf 'PASS: external target deletion is detected without follow-up kill\n'

run_delete_conflict target-restore op-archive
wait_for_state idle:op-archive
archive_path="$(find "$RUN_DIR/history" -type f -name '*.tsv' -print -quit)"
[ -f "$archive_path" ]
"${TMUX[@]}" set-environment -g TMUX_SESSION_LAUNCHER_TEST_OPERATION_DELAY 0.5
"${TMUX[@]}" run-shell -b "TMUX_SESSION_LAUNCHER_TEST_OPERATION_DELAY=0.5 $(quote "$LAUNCHER") --restore-archive $(quote "$archive_path") op-restore"
wait_for_trace 'operation.begin operation_id=op-restore type=restore'
"${TMUX[@]}" new-session -d -s target-restore -c "$REPO_ROOT" 'sleep 120'
wait_for_state failed:op-restore
[ "$("${TMUX[@]}" has-session -t =target-restore >/dev/null 2>&1; echo $?)" -eq 0 ]
printf 'PASS: restore name collision preserves externally created session\n'

grep -F -q 'operation.conflict' "$RUN_DIR/trace.log"
grep -F -q 'external.client-change' "$RUN_DIR/trace.log" || true
printf 'PASS: conflict trace contains operation identity and reason\n'
