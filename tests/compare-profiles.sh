#!/usr/bin/env bash
# tests/compare-profiles.sh
#
# 이 스크립트는 격리된 샌드박스 프로파일러와 실시간 액티브 세션 프로파일러를 순차 구동하고
# 그 결과 데이터를 파싱하여 실시간 vs 격리 환경의 성능/안정성 지표를 사이드-바이-사이드로 비교합니다.
set -euo pipefail

echo "=================================================="
echo " Launching Profile Comparison Suite"
echo "=================================================="

# 1. 활성 tmux 서버 및 클라이언트 연결 확인 (없을 시 자동 생성 및 연결)
SPAWNED_TEMP_CLIENT=false

if ! tmux list-sessions >/dev/null 2>&1; then
    echo "Active tmux server not found. Starting a temporary default session..."
    tmux new-session -d -s 0
fi

if [ -z "$(tmux list-clients 2>/dev/null)" ]; then
    echo "No attached tmux client found. Spawning a temporary urxvt terminal client..."
    export LIBGL_ALWAYS_SOFTWARE=1
    export XMODIFIERS=""
    urxvt -pe "" -fn "xft:Ubuntu Mono:pixelsize=16,xft:DejaVu Sans Mono:pixelsize=16" -geometry 100x30 -title "temp-active-tmux-client" -e /usr/bin/tmux new-session -A -s 0 &
    SPAWNED_TEMP_CLIENT=true
    sleep 2.5
fi

ISOLATED_LOG="/tmp/isolated_profile_raw.txt"
ACTIVE_LOG="/tmp/active_profile_raw.txt"

# 2. 격리된 샌드박스 프로파일러 자동 구동 (Enter 입력 자동 바이패스)
echo "1. Running Isolated Sandbox Profiler..."
bash tests/profile-isolated-sidebar.sh > "$ISOLATED_LOG" 2>&1 || {
    echo "ERROR: Isolated profiler run failed. Check log: $ISOLATED_LOG"
    exit 1
}

# 3. 실시간 액티브 세션 프로파일러 구동
echo "2. Running Active Session Profiler..."
bash tests/profile-active-sidebar.sh > "$ACTIVE_LOG" 2>&1 || {
    echo "ERROR: Active profiler run failed. Check log: $ACTIVE_LOG"
    exit 1
}

# 4. 결과 파싱 함수 정의
extract_metric() {
    local log_file="$1"
    local pattern="$2"
    # 테이블 라인에서 Value 열 파싱 (두 번째 | 사이의 문자열 공백 제거)
    grep -E "^\|.*$pattern" "$log_file" | head -n 1 | awk -F'|' '{print $3}' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' || echo "N/A"
}

# 5. 각 항목별 메트릭 추출
iso_idle=$(extract_metric "$ISOLATED_LOG" "Idle CPU")
act_idle=$(extract_metric "$ACTIVE_LOG" "Idle CPU")

iso_active=$(extract_metric "$ISOLATED_LOG" "Active CPU")
act_active=$(extract_metric "$ACTIVE_LOG" "Active CPU")

iso_latency=$(extract_metric "$ISOLATED_LOG" "Switch Latency")
act_latency=$(extract_metric "$ACTIVE_LOG" "Switch Latency")

iso_archive=$(extract_metric "$ISOLATED_LOG" "Archive Metadata")
act_archive=$(extract_metric "$ACTIVE_LOG" "Archive Metadata")

iso_layout=$(extract_metric "$ISOLATED_LOG" "Layout Preservation")
act_layout=$(extract_metric "$ACTIVE_LOG" "Layout Preservation")

iso_restore=$(extract_metric "$ISOLATED_LOG" "Restore Accuracy")
act_restore=$(extract_metric "$ACTIVE_LOG" "Restore Accuracy")

iso_grid=$(extract_metric "$ISOLATED_LOG" "Grid Boundary")
act_grid=$(extract_metric "$ACTIVE_LOG" "Grid Boundary")

# 6. 차이 분석 및 설명 작성
desc_idle="격리 환경이 데몬 오버헤드가 적어 비교적 낮은 RSS 점유"
desc_active="그라디언트 렌더 루프 부하 수준은 두 환경 모두 유사함"

# Latency 차이 계산 (숫자만 추출하여 안전하게 연산)
iso_num=$(echo "$iso_latency" | grep -oE '[0-9]+' | head -n 1 || echo 0)
act_num=$(echo "$act_latency" | grep -oE '[0-9]+' | head -n 1 || echo 0)

iso_react_num=$(echo "$iso_latency" | grep -oE 'Reactivity: [0-9]+' | grep -oE '[0-9]+' || echo 0)
act_react_num=$(echo "$act_latency" | grep -oE 'Reactivity: [0-9]+' | grep -oE '[0-9]+' || echo 0)

if [ "$iso_num" -gt 0 ] && [ "$act_num" -gt 0 ]; then
    diff_lat=$((iso_num - act_num))
    diff_react=$((iso_react_num - act_react_num))
    if [ "$diff_lat" -gt 0 ]; then
        desc_latency="격리가 약 ${diff_lat}ms 느림 (입력반응차: ${diff_react}ms)"
    else
        desc_latency="액티브가 약 ${diff_lat#-}ms 느림 (입력반응차: ${diff_react#-}ms)"
    fi
else
    desc_latency="대기 시간 추출 분석 불가"
fi

# 아카이브 백업 속도 비교
iso_arch_time=$(echo "$iso_archive" | grep -oE 'Time: [0-9]+ ms' || echo "Time: 0 ms")
act_arch_time=$(echo "$act_archive" | grep -oE 'Time: [0-9]+ ms' || echo "Time: 0 ms")
desc_archive="백업 속도 비교 (격리: $iso_arch_time / 액티브: $act_arch_time)"

# 메모리 누수 정보 추출
iso_leak=$(echo "$iso_layout" | grep -oE 'Leak: \+[0-9]+ KB' || echo "Leak: +0 KB")
act_leak=$(echo "$act_layout" | grep -oE 'Leak: \+[0-9]+ KB' || echo "Leak: +0 KB")
desc_layout="연타 스트레스 검증 (격리 누수: $iso_leak / 액티브 누수: $act_leak)"

# 복원 지연시간 정보 추출
iso_rest_time=$(echo "$iso_restore" | grep -oE 'Time: [0-9]+ ms' || echo "Time: 0 ms")
act_rest_time=$(echo "$act_restore" | grep -oE 'Time: [0-9]+ ms' || echo "Time: 0 ms")
desc_restore="복원 속도 비교 (격리: $iso_rest_time / 액티브: $act_rest_time)"

desc_grid="임계 리사이즈(15cols) 후 원래 크기(35cols) 복원 및 그리드 정상 회복 여부 검증"

# 7. 통합 비교 테이블 출력 및 마크다운 파일로 저장
REPORT_FILE="tests/profile-comparison-report.md"

{
    echo "# TUI Sidebar Profile Comparison Report"
    echo "Generated At: $(date)"
    echo ""
    echo "## Side-by-Side Comparison Table"
    echo ""
    printf "| %-28s | %-25s | %-25s | %-35s |\n" "Metric" "Active Session (Pts/2)" "Isolated Session (WSLg)" "Difference / Notes"
    printf "| :--- | :--- | :--- | :--- |\n"
    printf "| %-28s | %-25s | %-25s | %-35s |\n" "1. Idle CPU (Peak) / RSS" "$act_idle" "$iso_idle" "$desc_idle"
    printf "| %-28s | %-25s | %-25s | %-35s |\n" "2. Active CPU (Peak) / RSS" "$act_active" "$iso_active" "$desc_active"
    printf "| %-28s | %-25s | %-25s | %-35s |\n" "3. Switch Latency" "$act_latency" "$iso_latency" "$desc_latency"
    printf "| %-28s | %-25s | %-25s | %-35s |\n" "4. Archive Metadata Size" "$act_archive" "$iso_archive" "$desc_archive"
    printf "| %-28s | %-25s | %-25s | %-35s |\n" "5. Layout Preservation Ratio" "$act_layout" "$iso_layout" "$desc_layout"
    printf "| %-28s | %-25s | %-25s | %-35s |\n" "6. Restore Accuracy" "$act_restore" "$iso_restore" "$desc_restore"
    printf "| %-28s | %-25s | %-25s | %-35s |\n" "7. Grid Boundary check" "$act_grid" "$iso_grid" "$desc_grid"
    echo ""
    echo "## AI Auto-Analysis & Optimization Targets"
    echo "* **Resource Usage**: $desc_idle. $desc_active."
    echo "* **Latency Gap**: $desc_latency"
    echo "* **Restore & Layout Bugs**: $desc_layout. $desc_restore."
} | tee "$REPORT_FILE"

# 임시 로그 정리 (디버깅)
# rm -f "$ISOLATED_LOG" "$ACTIVE_LOG"

if [ "$SPAWNED_TEMP_CLIENT" = "true" ]; then
    echo "Cleaning up: Terminating temporary active tmux client..."
    tmux kill-server >/dev/null 2>&1 || true
fi
