#!/usr/bin/env bash
# ==============================================================================
# tests/lib/test_artifact_helper.sh
#
# 테스트 실패 시 진단 아티팩트(pane 메타데이터, 레이아웃, 화면 덤프, 로그)를
# 자동으로 캡처하여 지정된 디렉터리에 보존하는 공통 헬퍼입니다.
# ==============================================================================

dump_test_failure_artifacts() {
    local socket="${1:-}"
    local run_dir="${2:-/tmp}"
    local artifact_dir="${run_dir}/failure_artifacts"
    
    mkdir -p "${artifact_dir}"
    echo "Dumping failure artifacts to ${artifact_dir}..." >&2

    if [ -n "${socket}" ] && command -v tmux >/dev/null 2>&1; then
        tmux -L "${socket}" list-panes -a -F 'session=#{session_name}|window=#{window_id}|pane=#{pane_id}|title=#{pane_title}|width=#{pane_width}|height=#{pane_height}|left=#{pane_left}|top=#{pane_top}|active=#{pane_active}' > "${artifact_dir}/panes.txt" 2>/dev/null || true
        tmux -L "${socket}" list-windows -a -F 'session=#{session_name}|window=#{window_id}|layout=#{window_layout}' > "${artifact_dir}/windows_layout.txt" 2>/dev/null || true
        tmux -L "${socket}" list-clients -F 'tty=#{client_tty}|session=#{session_name}|window=#{window_id}|control=#{client_control_mode}' > "${artifact_dir}/clients.txt" 2>/dev/null || true
        
        # 각 pane별 capture-pane 화면 덤프 수집
        while IFS='|' read -r s_name w_id p_id p_title _; do
            [ -n "${p_id}" ] || continue
            tmux -L "${socket}" capture-pane -p -t "${p_id}" > "${artifact_dir}/capture_${p_id//%/pane_}.txt" 2>/dev/null || true
        done < <(tmux -L "${socket}" list-panes -a -F '#{session_name}|#{window_id}|#{pane_id}|#{pane_title}' 2>/dev/null || true)
    fi

    # HOME 디렉터리 내 launcher 로그 및 state 파일 복사
    if [ -d "${run_dir}/home" ]; then
        cp -r "${run_dir}/home/.local/state" "${artifact_dir}/state_backup" 2>/dev/null || true
    fi
}
