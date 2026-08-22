#!/usr/bin/env bash
set -euo pipefail
SCENARIO_NAME=rename-roundtrip
export SCENARIO_NAME
source "$(dirname -- "$BASH_SOURCE")/test-interactive-common.sh"

setup_interactive_test
create_session rename-target
create_session rename-peer
select_session_by_name rename-target
before_sidebar="$(sidebar_pane_id)"

send_keys r
wait_prompt Rename:
send_keys 'renamed-target'
send_keys $'\r'
wait_until "renamed-target" "wait_session_exists 'renamed-target'"
wait_until "old name removed" "wait_session_absent rename-target"
wait_until "renamed sidebar entry" "wait_capture 'renamed-target'"

select_session_by_name rename-peer
select_session_by_name 'renamed-target'
wait_until "renamed session remains available" "wait_session_exists 'renamed-target'"
wait_until "renamed session selected after switch" "wait_session 'renamed-target'"
wait_until "sidebar after rename switch" sidebar_present
[ "$(sidebar_pane_id)" = "$before_sidebar" ]
echo "PASS: attached-PTY session rename survives switch round-trip"
