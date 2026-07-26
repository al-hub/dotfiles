#!/usr/bin/env bash
set -euo pipefail
SCENARIO_NAME=pane-reorder
export SCENARIO_NAME
source "$(dirname -- "$BASH_SOURCE")/test-interactive-common.sh"

setup_interactive_test
create_session reorder-target
select_session_by_name reorder-target

for key in '|' '_' '|' ; do
  focus_sidebar
  send_keys $'\001'"$key"
  sleep 0.2
done
wait_until "four panes" "pane_count_at_least reorder-target 4"

slot=0
while IFS='|' read -r pane_id title; do
  [ "$title" = dotfiles-session-sidebar ] && continue
  tmuxc select-pane -t "$pane_id" -T "reorder-slot-$slot"
  slot=$((slot + 1))
done < <(tmuxc list-panes -t '=reorder-target:' -F '#{pane_id}|#{pane_title}')
[ "$slot" -ge 3 ]

pane_snapshot() {
  tmuxc list-panes -t '=reorder-target:' -F '#{pane_title}|#{pane_left}|#{pane_top}|#{pane_width}|#{pane_height}' |
    awk -F'|' '$1 ~ /^reorder-slot-/ {print}' | sort
}

focus_sidebar
send_keys $'\001o'
send_keys $'\033[1;3C'
send_keys $'\033[1;3D'
send_keys $'\033[1;3A'
sleep 0.3
before_snapshot="$(pane_snapshot)"
[ -n "$before_snapshot" ]

focus_sidebar
select_session_by_name interactive-peer
select_session_by_name reorder-target
after_snapshot="$(pane_snapshot)"
[ "$before_snapshot" = "$after_snapshot" ]
[ "$(count_sidebars)" = 1 ]
echo "PASS: attached-PTY pane reorder survives session switch round-trip"
