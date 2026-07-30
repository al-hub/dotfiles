#!/usr/bin/env bash
set -euo pipefail

# Runs the core live suite in a temporary visible window of the user's tmux.
# Prefix keys are intentionally covered by the attached-PTY suite separately.
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd -P)"
LAUNCHER="${TMUX_USER_LIVE_LAUNCHER:-$HOME/.local/bin/tmux-session-launcher}"
CLIENT_TTY="${TMUX_USER_LIVE_CLIENT:-$(tmux list-clients -F '#{client_control_mode}|#{client_tty}' | awk -F '|' '$1 != 1 {print $2; exit}')}"
RUN_ID="${TMUX_USER_LIVE_RUN_ID:-user-live-$(date +%s)-$$}"
RUN_DIR="${TMUX_USER_LIVE_RUN_DIR:-${TMPDIR:-/tmp}/dotfiles-user-live-$RUN_ID}"
EVENT_LOG="$RUN_DIR/events.log"; RESULT_LOG="$RUN_DIR/results.tsv"; HISTORY_DIR="$RUN_DIR/history"
ORIGINAL_SESSION=""; ORIGINAL_WINDOW=""; TEST_WINDOW_ID=""; SIDEBAR_PANE=""; TEST_SESSIONS=(); EVENT_SEQUENCE=0; INPUT_SEQUENCE=0; FAILURES=0; INITIAL_PANES=""; ORIGINAL_SIDEBAR_ENABLED=""; ORIGINAL_SIDEBAR_MANAGED=""; CLIENT_CAPTURE_PID=""; CLIENT_STREAM_OFFSET=0
ERROR_PATTERN='ensure-sidebar-window.*returned 1|--ensure-sidebar-window.*returned 1|session[[:space:]]+switch.*failed'
mkdir -p "$HISTORY_DIR"; : > "$EVENT_LOG"; : > "$RESULT_LOG"
tmuxc() { tmux -L default "$@"; }
now_ms() { perl -MTime::HiRes=time -e 'printf "%.3f", time * 1000'; }
log() { EVENT_SEQUENCE=$((EVENT_SEQUENCE + 1)); printf 'ts_wall=%s ts_mono_ms=%s run_id=%s event_seq=%s input_seq=%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%S%z')" "$(now_ms)" "$RUN_ID" "$EVENT_SEQUENCE" "$INPUT_SEQUENCE" "$*" >> "$EVENT_LOG"; }
client_field() { tmuxc list-clients -F "#{client_tty}|#{${1}}" 2>/dev/null | awk -F '|' -v tty="$CLIENT_TTY" '$1 == tty {print $2; exit}'; }
refresh_sidebar() { SIDEBAR_PANE="$(tmuxc list-panes -t "$(client_field window_id)" -F '#{pane_id}|#{pane_title}' 2>/dev/null | awk -F '|' '$2 == "dotfiles-session-sidebar" {print $1; exit}')"; [ -n "$SIDEBAR_PANE" ]; }
snapshot() { local n="$EVENT_SEQUENCE"; log "event=snapshot session=$(client_field session_name || true) window=$(client_field window_id || true) pane=$(client_field pane_id || true) owner=$(tmuxc show-options -gqv @dotfiles_sidebar_owner_client 2>/dev/null || true)"; tmuxc list-clients -F 'control=#{client_control_mode}|tty=#{client_tty}|session=#{session_name}|window=#{window_id}|pane=#{pane_id}|prefix=#{client_prefix}' > "$RUN_DIR/clients-$n.tsv" 2>/dev/null || true; tmuxc list-panes -a -F 'session=#{session_name}|window=#{window_id}|pane=#{pane_id}|title=#{pane_title}|pid=#{pane_pid}|active=#{pane_active}|geometry=#{pane_left},#{pane_top},#{pane_width},#{pane_height}' > "$RUN_DIR/panes-$n.tsv" 2>/dev/null || true; }
capture() { local label="$1"; refresh_sidebar || return 0; tmuxc capture-pane -e -p -J -t "$SIDEBAR_PANE" > "$RUN_DIR/capture-$label.log" 2>/dev/null || true; tmuxc list-panes -t "$(client_field window_id)" -F '#{pane_id}|#{pane_title}|#{pane_left},#{pane_top},#{pane_width},#{pane_height}|#{pane_pid}|#{pane_active}' > "$RUN_DIR/layout-$label.tsv" 2>/dev/null || true; log "event=observation label=$label sidebar=$SIDEBAR_PANE"; }
scan_live_panes() {
    local label="$1" pane title session window current scroll normalized matches found=0
    while IFS='|' read -r pane title session window; do
        [ -n "$pane" ] || continue
        [ "$title" = dotfiles-session-sidebar ] && continue
        current="$RUN_DIR/pane-$pane-$label-current.log"
        scroll="$RUN_DIR/pane-$pane-$label-scrollback.log"
        normalized="$RUN_DIR/pane-$pane-$label-normalized.log"
        tmuxc capture-pane -p -J -t "$pane" > "$current" 2>/dev/null || true
        tmuxc capture-pane -p -J -S -1000 -t "$pane" > "$scroll" 2>/dev/null || true
        {
            cat "$current" 2>/dev/null || true
            cat "$scroll" 2>/dev/null || true
        } | perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\e\][^\a]*\a//g; s/\r//g' > "$normalized"
        if grep -Ein -- "$ERROR_PATTERN" "$normalized" > "$RUN_DIR/pane-$pane-$label-matches.log" 2>/dev/null; then
            found=1
            {
                printf 'ts_wall=%s ts_mono_ms=%s pane=%s title=%s session=%s window=%s label=%s\n' \
                    "$(date -u '+%Y-%m-%dT%H:%M:%S%z')" "$(now_ms)" "$pane" "$title" "$session" "$window" "$label"
                cat "$RUN_DIR/pane-$pane-$label-matches.log"
            } >> "$RUN_DIR/error-matches.log"
            log "event=error-observed source=pane pane=$pane session=$session window=$window label=$label"
        fi
    done < <(tmuxc list-panes -a -F '#{pane_id}|#{pane_title}|#{session_name}|#{window_id}' 2>/dev/null)
    return "$found"
}
scan_client_stream() {
    local label="$1" normalized raw size bytes
    normalized="$RUN_DIR/client-$label-normalized.log"
    [ -s "$RUN_DIR/client.log" ] || return 1
    size="$(wc -c < "$RUN_DIR/client.log" 2>/dev/null || printf 0)"
    bytes=$((size - CLIENT_STREAM_OFFSET))
    [ "$bytes" -gt 0 ] || return 1
    raw="$RUN_DIR/client-$label-delta.raw"
    dd if="$RUN_DIR/client.log" of="$raw" iflag=skip_bytes,count_bytes \
        skip="$CLIENT_STREAM_OFFSET" count="$bytes" status=none 2>/dev/null || return 1
    perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\e\][^\a]*\a//g; s/\r//g' \
        "$raw" > "$normalized"
    CLIENT_STREAM_OFFSET="$size"
    if grep -Ein -- "$ERROR_PATTERN" "$normalized" > "$RUN_DIR/client-$label-matches.log" 2>/dev/null; then
        {
            printf 'ts_wall=%s ts_mono_ms=%s source=client label=%s\n' \
                "$(date -u '+%Y-%m-%dT%H:%M:%S%z')" "$(now_ms)" "$label"
            cat "$RUN_DIR/client-$label-matches.log"
        } >> "$RUN_DIR/error-matches.log"
        log "event=error-observed source=client-stream label=$label"
        return 0
    fi
    return 1
}
fail() { FAILURES=$((FAILURES + 1)); log "event=assertion result=FAIL reason=$*"; snapshot; capture "failure-$FAILURES"; }
initial_pane() { case " $INITIAL_PANES " in *" $1 "*) return 0;; esac; return 1; }
remove_test_sidebars() { local pane found; for _ in $(seq 1 100); do found=0; while IFS='|' read -r pane title; do [ "$title" = dotfiles-session-sidebar ] || continue; initial_pane "$pane" && continue; found=1; tmuxc kill-pane -t "$pane" >/dev/null 2>&1 || true; done < <(tmuxc list-panes -a -F '#{pane_id}|#{pane_title}' 2>/dev/null); [ "$found" -eq 0 ] && return 0; sleep 0.05; done; }
wait_for() { local description="$1" command_name="$2" start="$(now_ms)" deadline=$(( $(date +%s) + 20 )); shift 2; log "event=wait.begin description=$description"; while [ "$(date +%s)" -lt "$deadline" ]; do if "$command_name" "$@" 2>/dev/null; then log "event=wait.end description=$description result=PASS duration_ms=$(awk -v s="$start" -v e="$(now_ms)" 'BEGIN{print e-s}')"; return 0; fi; sleep 0.05; done; log "event=wait.end description=$description result=TIMEOUT"; fail "timeout=$description"; return 1; }
sidebar_text() { refresh_sidebar && tmuxc capture-pane -p -t "$SIDEBAR_PANE" 2>/dev/null | grep -Fq -- "$1"; }
session_exists() { tmuxc has-session -t "=$1" 2>/dev/null; }
selected_name() { refresh_sidebar || return 1; tmuxc capture-pane -p -t "$SIDEBAR_PANE" 2>/dev/null | sed $'s/\033\\[[0-9;]*m//g' | awk '$1 == ">" { if ($2 == "*") print $3; else print $2; exit }'; }
row_for() { local name="$1"; refresh_sidebar || return 1; tmuxc capture-pane -p -t "$SIDEBAR_PANE" 2>/dev/null | sed $'s/\033\\[[0-9;]*m//g' | nl -ba | awk -v n="$name" 'index($0,n)>0 {print $1; exit}'; }
send_tui() { local payload="$1"; refresh_sidebar || return 1; INPUT_SEQUENCE=$((INPUT_SEQUENCE + 1)); log "event=input.begin bytes=$(printf '%b' "$payload" | od -An -tx1 | tr -d ' \n') pane=$SIDEBAR_PANE"; case "$payload" in $'\033[B') tmuxc send-keys -t "$SIDEBAR_PANE" Down;; $'\033[A') tmuxc send-keys -t "$SIDEBAR_PANE" Up;; $'\r') tmuxc send-keys -t "$SIDEBAR_PANE" Enter;; *$'\r') tmuxc send-keys -t "$SIDEBAR_PANE" -l "${payload%$'\r'}"; tmuxc send-keys -t "$SIDEBAR_PANE" Enter;; *) tmuxc send-keys -t "$SIDEBAR_PANE" -l "$(printf '%b' "$payload")";; esac; log "event=input.end pane=$SIDEBAR_PANE"; scan_live_panes "input-$INPUT_SEQUENCE" || true; scan_client_stream "input-$INPUT_SEQUENCE" || true; }
move_selection_to() { local target="$1" current i; for i in $(seq 1 30); do current="$(selected_name || true)"; [ "$current" = "$target" ] && return 0; send_tui $'\033[B' || return 1; wait_for "selection-step-$target-$i" selected_name || return 1; done; log "event=selection.end target=$target result=FAIL selected=$(selected_name || true)"; return 1; }
create_session() { local name="$1" start="$(now_ms)" prompt enter ready total result; send_tui c; wait_for "prompt-$name" sidebar_text New: || return 1; prompt="$(now_ms)"; send_tui "$name"; send_tui $'\r'; enter="$(now_ms)"; wait_for "session-$name" session_exists "$name" || return 1; ready="$(now_ms)"; total="$(awk -v s="$start" -v r="$ready" 'BEGIN{print r-s}')"; result="$(awk -v t="$total" 'BEGIN{print(t>1000)?"FAIL":"PASS"}')"; printf 'create\t%s\t%s\t%s\n' "$name" "$total" "$result" >> "$RESULT_LOG"; log "event=session.create name=$name c_to_prompt_ms=$(awk -v s="$start" -v p="$prompt" 'BEGIN{print p-s}') enter_to_session_ms=$(awk -v e="$enter" -v r="$ready" 'BEGIN{print r-e}') total_ms=$total result=$result"; capture "create-$name"; [ "$result" = PASS ] || fail "create-latency-$name"; }
switch_once() { local index="$1" before="$(client_field session_name)" target start current after duration result before_sidebar after_sidebar duplicate_count identity_result; target="${TEST_SESSIONS[$(((index - 1) % ${#TEST_SESSIONS[@]}))]}"; [ "$target" = "$before" ] && target="${TEST_SESSIONS[$((index % ${#TEST_SESSIONS[@]}))]}"; refresh_sidebar || true; before_sidebar="$SIDEBAR_PANE"; log "event=session.switch.target iteration=$index from=$before target=$target"; move_selection_to "$target" || { fail "selection-$index-target-$target"; return 1; }; start="$(now_ms)"; log "event=session.switch.enter iteration=$index target=$target"; send_tui $'\r'; current="$before"; for _ in $(seq 1 200); do current="$(client_field session_name || true)"; [ "$current" = "$target" ] && break; sleep 0.05; done; refresh_sidebar || true; after_sidebar="$SIDEBAR_PANE"; duplicate_count="$(tmuxc list-panes -a -F '#{pane_title}' | awk '$0=="dotfiles-session-sidebar"{n++} END{print n+0}')"; after="$(now_ms)"; duration="$(awk -v s="$start" -v e="$after" 'BEGIN{print e-s}')"; identity_result="$([ "$before_sidebar" = "$after_sidebar" ] && echo PASS || echo FAIL)"; result="$(awk -v d="$duration" -v c="$([ "$current" = "$target" ] && echo 1 || echo 0)" -v i="$([ "$identity_result" = PASS ] && echo 1 || echo 0)" -v n="$duplicate_count" 'BEGIN{print(!c||d>500||!i||n!=1)?"FAIL":"PASS"}')"; printf 'switch\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$index" "$before" "$current" "$result" "$before_sidebar" "$after_sidebar" "$duplicate_count" >> "$RESULT_LOG"; log "event=session.switch iteration=$index from=$before target=$target to=$current duration_ms=$duration sidebar_before=$before_sidebar sidebar_after=$after_sidebar duplicate_sidebars=$duplicate_count identity=$identity_result result=$result"; [ "$result" = PASS ] || fail "switch-$index"; }
cleanup() { local status=$?; set +e; log "event=cleanup.begin status=$status"; tmuxc switch-client -c "$CLIENT_TTY" -t "$ORIGINAL_WINDOW" >/dev/null 2>&1 || true; for name in "${TEST_SESSIONS[@]:-}"; do tmuxc kill-session -t "=$name" >/dev/null 2>&1 || true; done; [ -n "$TEST_WINDOW_ID" ] && tmuxc kill-window -t "$TEST_WINDOW_ID" >/dev/null 2>&1 || true; tmuxc set-option -w -t "$ORIGINAL_WINDOW" @dotfiles_sidebar_enabled 0 >/dev/null 2>&1 || true; remove_test_sidebars; tmuxc switch-client -c "$CLIENT_TTY" -t "$ORIGINAL_WINDOW" >/dev/null 2>&1 || true; sleep 0.5; remove_test_sidebars; if [ -n "$ORIGINAL_SIDEBAR_ENABLED" ]; then tmuxc set-option -w -t "$ORIGINAL_WINDOW" @dotfiles_sidebar_enabled "$ORIGINAL_SIDEBAR_ENABLED" >/dev/null 2>&1 || true; else tmuxc set-option -uw -t "$ORIGINAL_WINDOW" @dotfiles_sidebar_enabled >/dev/null 2>&1 || true; fi; if [ -n "$ORIGINAL_SIDEBAR_MANAGED" ]; then tmuxc set-option -w -t "$ORIGINAL_WINDOW" @dotfiles_sidebar_managed "$ORIGINAL_SIDEBAR_MANAGED" >/dev/null 2>&1 || true; else tmuxc set-option -uw -t "$ORIGINAL_WINDOW" @dotfiles_sidebar_managed >/dev/null 2>&1 || true; fi; if [ -n "$CLIENT_CAPTURE_PID" ]; then kill "$CLIENT_CAPTURE_PID" >/dev/null 2>&1 || true; wait "$CLIENT_CAPTURE_PID" 2>/dev/null || true; fi; snapshot; log "event=cleanup.end status=$status failures=$FAILURES"; exit "$status"; }

normalize_test_window_sidebar() {
  local panes primary pane
  for _ in $(seq 1 40); do
    panes="$(tmuxc list-panes -t "$TEST_WINDOW_ID" -F '#{pane_id}|#{pane_title}' 2>/dev/null |
      awk -F '|' '$2 == "dotfiles-session-sidebar" {print $1}')"
    primary="$(printf '%s\n' "$panes" | sed -n '1p')"
    if [ -n "$primary" ]; then
      while IFS= read -r pane; do
        [ -n "$pane" ] && [ "$pane" != "$primary" ] && tmuxc kill-pane -t "$pane" >/dev/null 2>&1 || true
      done <<EOF
$panes
EOF
      tmuxc respawn-pane -k -t "$primary" "$sidebar_command" >/dev/null 2>&1 || true
      SIDEBAR_PANE="$primary"
      return 0
    fi
    sleep 0.05
  done
  return 1
}
trap cleanup EXIT INT TERM
[ -n "$CLIENT_TTY" ] || { echo 'ERROR: no attached user client' >&2; exit 2; }
ORIGINAL_SESSION="$(client_field session_name)"; ORIGINAL_WINDOW="$(client_field window_id)"; INITIAL_PANES="$(tmuxc list-panes -a -F '#{pane_id}')"; ORIGINAL_SIDEBAR_ENABLED="$(tmuxc show-options -wqv -t "$ORIGINAL_WINDOW" @dotfiles_sidebar_enabled 2>/dev/null || true)"; ORIGINAL_SIDEBAR_MANAGED="$(tmuxc show-options -wqv -t "$ORIGINAL_WINDOW" @dotfiles_sidebar_managed 2>/dev/null || true)"; log "event=test.start socket=default client=$CLIENT_TTY original_session=$ORIGINAL_SESSION original_window=$ORIGINAL_WINDOW initial_panes=$INITIAL_PANES original_sidebar_enabled=$ORIGINAL_SIDEBAR_ENABLED"; snapshot
command -v script >/dev/null 2>&1 || { echo 'ERROR: script(1) is required for user tmux client stream capture' >&2; exit 2; }
script -qefc "TERM=xterm tmux -L default attach-session -t =$ORIGINAL_SESSION" --log-out "$RUN_DIR/client.log" >/dev/null 2>&1 & CLIENT_CAPTURE_PID=$!; log "event=client-capture.start pid=$CLIENT_CAPTURE_PID session=$ORIGINAL_SESSION"; sleep 0.2
tmuxc run-shell "env TMUX_SESSION_LAUNCHER_TRACE=1 TMUX_SESSION_LAUNCHER_TRACE_FILE='$RUN_DIR/trace.log' TMUX_SESSION_LAUNCHER_DEBUG=1 TMUX_SESSION_LAUNCHER_DEBUG_FILE='$RUN_DIR/debug.log' '$LAUNCHER' --install-sidebar-hooks" >/dev/null 2>&1 || true
TEST_WINDOW_ID="$(tmuxc new-window -d -t "=$ORIGINAL_SESSION:" -n codex-live -c "$REPO_ROOT" -P -F '#{window_id}' 'sleep 300')"; tmuxc switch-client -c "$CLIENT_TTY" -t "$TEST_WINDOW_ID"; log "event=test-window.created window=$TEST_WINDOW_ID"
sidebar_command="env TMUX_SESSION_HISTORY_DIR='$HISTORY_DIR' TMUX_SESSION_LAUNCHER_TRACE=1 TMUX_SESSION_LAUNCHER_TRACE_FILE='$RUN_DIR/trace.log' TMUX_SESSION_LAUNCHER_DEBUG=1 TMUX_SESSION_LAUNCHER_DEBUG_FILE='$RUN_DIR/debug.log' '$LAUNCHER' --sidebar"; tmuxc run-shell "env TMUX_SESSION_HISTORY_DIR='$HISTORY_DIR' TMUX_SESSION_LAUNCHER_TRACE=1 TMUX_SESSION_LAUNCHER_TRACE_FILE='$RUN_DIR/trace.log' TMUX_SESSION_LAUNCHER_DEBUG=1 TMUX_SESSION_LAUNCHER_DEBUG_FILE='$RUN_DIR/debug.log' '$LAUNCHER' --ensure-current-sidebar" >/dev/null 2>&1 || true; normalize_test_window_sidebar || { fail 'sidebar-create'; exit 1; }; refresh_sidebar; tmuxc select-pane -t "$SIDEBAR_PANE"; wait_for sidebar-ready sidebar_text sessions || true; capture initial
for index in 1 2 3; do name="live-${RUN_ID##*-}$index"; TEST_SESSIONS+=("$name"); create_session "$name" || true; done
for index in 1 2 3 4 5 6; do switch_once "$index" || true; done
for direction in horizontal vertical; do current="$(client_field session_name || true)"; window_id="$(tmuxc display-message -p -t "=$current:" '#{window_id}' 2>/dev/null || true)"; work="$(tmuxc list-panes -t "$window_id" -F '#{pane_id}|#{pane_title}' | awk -F '|' '$2 != "dotfiles-session-sidebar" {print $1; exit}')"; before="$RUN_DIR/layout-$direction-before.tsv"; after="$RUN_DIR/layout-$direction-after.tsv"; tmuxc list-panes -t "$window_id" -F '#{pane_id}|#{pane_title}|#{pane_left},#{pane_top},#{pane_width},#{pane_height}' > "$before"; if [ -n "$work" ]; then [ "$direction" = horizontal ] && tmuxc split-window -h -t "$work" -c "$REPO_ROOT" || tmuxc split-window -v -t "$work" -c "$REPO_ROOT"; tmuxc list-panes -t "$window_id" -F '#{pane_id}|#{pane_title}|#{pane_left},#{pane_top},#{pane_width},#{pane_height}' > "$after"; log "event=layout direction=$direction before=$before after=$after"; else fail "work-pane-$direction"; fi; done
scan_live_panes final || true
scan_client_stream final || true
if grep -aEin -- "$ERROR_PATTERN" "$RUN_DIR/trace.log" "$RUN_DIR/debug.log" 2>/dev/null >> "$RUN_DIR/error-matches.log" || [ -s "$RUN_DIR/error-matches.log" ]; then fail known-launcher-error; else log 'event=error-scan result=PASS source=trace-debug-and-pane-history matches=0'; fi
if [ "$FAILURES" -eq 0 ]; then echo 'PASS: user tmux required live suite'; else echo "FAIL: user tmux required live suite failures=$FAILURES" >&2; exit 1; fi
