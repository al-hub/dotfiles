#!/usr/bin/env bash
# tests/profile-active-sidebar.sh
# 
# 이 스크립트는 실제 사용자 attached 터미널 환경을 자동 감지하여 7가지 성능/안정성 시나리오를
# 실시간으로 재현하고, 각 시나리오별 수치화된 정량 지표를 도표로 출력합니다.
set -euo pipefail

echo "=================================================="
echo " Starting Active Sidebar TUI 7-Scenario Profiler"
echo "=================================================="

# 1. 활성 attached 클라이언트 TTY 및 세션 자동 감지
client_tty=$(tmux list-clients -F '#{client_tty}' 2>/dev/null | head -n 1 || true)
attached_session=""
if [ -n "$client_tty" ]; then
    attached_session=$(tmux list-clients -F '#{client_tty} #{session_name}' 2>/dev/null | grep "$client_tty" | head -n 1 | awk '{print $2}' || true)
fi

if [ -z "$client_tty" ] || [ -z "$attached_session" ]; then
    echo "ERROR: No active attached client detected (client_tty='$client_tty', attached_session='$attached_session'). Please run this inside an attached tmux session (e.g. run 'tmux attach' first)."
    exit 1
fi

echo "Detected Client  : $client_tty"
echo "Attached Session : $attached_session"

# 테스트용 12개 세션 생성 (session-long-name-1 ~ session-long-name-12)
echo "Populating tmux sessions..."
for i in {1..12}; do
    tmux has-session -t "session-long-name-$i" 2>/dev/null || tmux new-session -d -s "session-long-name-$i"
done
sleep 1.0

# 2. 사이드바 pane ID 및 PID 획득
sidebar_pane=$(tmux list-panes -s -t "$attached_session" -F '#{pane_id} #{pane_title}' | awk '$2 == "dotfiles-session-sidebar" {print $1}' | head -n 1)
if [ -z "$sidebar_pane" ]; then
    echo "ERROR: Sidebar is not open in the attached session. Opening it first..."
    tmux run-shell -t "$attached_session" "~/.local/bin/tmux-session-launcher --open-sidebar"
    sleep 1
    sidebar_pane=$(tmux list-panes -s -t "$attached_session" -F '#{pane_id} #{pane_title}' | awk '$2 == "dotfiles-session-sidebar" {print $1}' | head -n 1)
fi

sidebar_pid=$(tmux display-message -p -t "$sidebar_pane" '#{pane_pid}' 2>/dev/null || echo "")
echo "Sidebar PID      : $sidebar_pid (Pane: $sidebar_pane)"

# ==================================================
# [시나리오 1] Idle CPU & RSS 측정 (샘플 수 확대 & Peak 값 추가)
# ==================================================
echo "Running Scenario 1: Idle CPU & Memory profiling..."
idle_samples=()
for i in {1..10}; do
    stats=$(ps -p "$sidebar_pid" -o %cpu,rss= 2>/dev/null || true)
    if [ -n "$stats" ]; then
        idle_samples+=("$stats")
    fi
    sleep 0.4
done
avg_idle_cpu=$(echo "${idle_samples[@]}" | awk '{sum+=$1} END {printf "%.1f%%", sum/NR}')
max_idle_cpu=$(echo "${idle_samples[@]}" | awk 'BEGIN{max=0} {if($1>max) max=$1} END {printf "%.1f%%", max}')
avg_idle_rss=$(echo "${idle_samples[@]}" | awk '{sum+=$2} END {printf "%d KB", sum/NR}')

# ==================================================
# [시나리오 2] Active (Gradient Animation) CPU & RSS 측정 (샘플 수 확대 & Peak 값 추가)
# ==================================================
echo "Running Scenario 2: Active (Gradient Sweep) profiling..."

# session-long-name-2의 작업 패널 찾기
target_work_session="session-long-name-2"
work_pane=$(tmux list-panes -s -t "$target_work_session" -F '#{pane_id} #{pane_title}' 2>/dev/null | awk '$2 != "dotfiles-session-sidebar" {print $1; exit}' || true)

if [ -n "$work_pane" ]; then
    # claude 바이너리 모킹
    pkill -f claude || true
    mkdir -p ~/.gemini/antigravity-cli
    rm -f ~/.gemini/antigravity-cli/claude
    cp /bin/bash ~/.gemini/antigravity-cli/claude
    
    # tick 출력을 반복하는 claude 구동
    tmux send-keys -t "$work_pane" "~/.gemini/antigravity-cli/claude -c 'while true; do echo \"tick \$RANDOM\"; sleep 0.5; done'" C-m
    sleep 2.5
    
    active_samples=()
    for i in {1..10}; do
        stats=$(ps -p "$sidebar_pid" -o %cpu,rss= 2>/dev/null || true)
        if [ -n "$stats" ]; then
            active_samples+=("$stats")
        fi
        sleep 0.4
    done
    avg_active_cpu=$(echo "${active_samples[@]}" | awk '{sum+=$1} END {printf "%.1f%%", sum/NR}')
    max_active_cpu=$(echo "${active_samples[@]}" | awk 'BEGIN{max=0} {if($1>max) max=$1} END {printf "%.1f%%", max}')
    avg_active_rss=$(echo "${active_samples[@]}" | awk '{sum+=$2} END {printf "%d KB", sum/NR}')
    
    # 정리
    tmux send-keys -t "$work_pane" C-c
    rm -f ~/.gemini/antigravity-cli/claude
else
    avg_active_cpu="ERROR"
    max_active_cpu="ERROR"
    avg_active_rss="ERROR"
fi

# ==================================================
# [시나리오 3] 세션 전환 지연시간 (Switch Latency) 측정
# ==================================================
echo "Running Scenario 3: Session Switch Latency..."
# session-long-name-1 <-> session-long-name-2 간의 물리적 스위칭 속도 측정
# Python 스크립트로 세션 리스트 맵 파싱 후 동적 j/k 키 카운트 계산하여 전송

latency=$(python3 -c "
import time, subprocess, sys

# 1. 현재 사이드바의 세션 목록과 커서 위치 캡처
out = subprocess.check_output(['tmux', 'capture-pane', '-p', '-t', '$sidebar_pane']).decode().strip().split('\n')
sessions = []
cursor_idx = -1
target_idx = -1

for line in out:
    if line.startswith('sessions') or line.startswith('j/k') or not line.strip():
        continue
    # 세션명 추출
    parts = line.strip().split()
    if not parts:
        continue
    sname = parts[1] if (parts[0] in ['>', '>*'] and len(parts) >= 2) else parts[0]
    sessions.append(sname)
    if parts[0] in ['>', '>*']:
        cursor_idx = len(sessions) - 1
    if sname == 'session-long-name-2':
        target_idx = len(sessions) - 1

if cursor_idx == -1 or target_idx == -1:
    print('ERROR')
    sys.exit(1)

# j/k 계산
keys = []
delta = target_idx - cursor_idx
if delta > 0:
    keys = ['j'] * delta
else:
    keys = ['k'] * abs(delta)
keys.append('C-m')

# 2. 첫 번째 입력 반응속도(Input Reactivity) 실측
t0 = time.time()
if keys:
    first_key = keys[0]
    subprocess.run(['tmux', 'send-keys', '-t', '$sidebar_pane', first_key])
    while True:
        try:
            curr_pane = subprocess.check_output(['tmux', 'capture-pane', '-p', '-t', '$sidebar_pane']).decode().strip().split('\n')
        except subprocess.CalledProcessError:
            curr_pane = []
        curr_cursor_idx = -1
        curr_sessions = []
        for line in curr_pane:
            if line.startswith('sessions') or line.startswith('j/k') or not line.strip():
                continue
            parts = line.strip().split()
            if not parts:
                continue
            curr_sname = parts[1] if (parts[0] in ['>', '>*'] and len(parts) >= 2) else parts[0]
            curr_sessions.append(curr_sname)
            if parts[0] in ['>', '>*']:
                curr_cursor_idx = len(curr_sessions) - 1
        if curr_cursor_idx != -1 and curr_cursor_idx != cursor_idx:
            break
        time.sleep(0.005)
t1 = time.time()
reactivity_ms = int((t1 - t0) * 1000)

# 3. 나머지 키 전송 및 최종 세션 스위칭 속도 측정
remaining_keys = keys[1:]
if remaining_keys:
    subprocess.run(['tmux', 'send-keys', '-t', '$sidebar_pane'] + remaining_keys)

t_switch_start = time.time()
while True:
    try:
        client_out = subprocess.check_output(['tmux', 'list-clients', '-F', '#{client_tty} #{session_name}']).decode()
    except subprocess.CalledProcessError:
        client_out = ''
    active_session = None
    for line in client_out.strip().split('\n'):
        if not line.strip():
            continue
        if '$client_tty' in line:
            active_session = line.split()[1]
            break
    if active_session == 'session-long-name-2':
        break
    time.sleep(0.01)
t_switch_end = time.time()
switch_ms = int((t_switch_end - t_switch_start) * 1000)

print(f'{reactivity_ms},{switch_ms}')
" || echo "ERROR")

# s1 세션으로 다시 원상 복구
sleep 1
new_sidebar_pane=$(tmux list-panes -s -t session-long-name-2 -F '#{pane_id} #{pane_title}' | awk '$2 == "dotfiles-session-sidebar" {print $1}' | head -n 1)
if [ -n "$new_sidebar_pane" ]; then
    tmux send-keys -t "$new_sidebar_pane" k k k k C-m
    sleep 1
fi

# ==================================================
# [시나리오 4] 아카이브 메타데이터 파일 크기 측정
# ==================================================
echo "Running Scenario 4: Archive File Size profiling..."

HISTORY_DIR="$HOME/.cache/dotfiles/tmux-session-history"
# 테스트용 임시 세션 생성 후 삭제
dummy_sess="session-to-archive-test"
tmux new-session -d -s "$dummy_sess"
sleep 0.5
# CLI를 통해 세션을 아카이브와 함께 안전하게 직접 삭제 (시간 측정)
t_arch_start=$(date +%s%N)
~/.local/bin/tmux-session-launcher --delete-session-after-archive "$dummy_sess" true
t_arch_end=$(date +%s%N)
arch_duration=$(( (t_arch_end - t_arch_start) / 1000000 ))
sleep 1.5

archive_file=$(find "$HISTORY_DIR" -type f -name "*$dummy_sess*" | sort | tail -n 1)
if [ -n "$archive_file" ] && [ -f "$archive_file" ]; then
    archive_size=$(wc -c < "$archive_file" | awk -v dur="$arch_duration" '{printf "%.2f KB / Time: %d ms", $1/1024, dur}')
else
    archive_size="ERROR"
fi

# ==================================================
# [시나리오 5] 레이아웃 일치율 (Layout Preservation Ratio)
# ==================================================
echo "Running Scenario 5: Layout Preservation profiling..."

# 사이드바 닫기
tmux send-keys -t "$sidebar_pane" q
sleep 0.8
layout_closed=$(tmux display-message -p '#{window_layout}')

# 메모리 누수 측정을 위한 초기 RSS 획득
rss_before=$(ps -p "$sidebar_pid" -o rss= 2>/dev/null | awk '{print $1}' || echo 0)

# [추가] 윈도우 리사이즈 및 연타 스트레스 테스트 시뮬레이션
echo "Simulating rapid toggle stress (3 times)..."
for j in {1..3}; do
    tmux run-shell -t "$attached_session" "~/.local/bin/tmux-session-launcher --open-sidebar"
    sleep 0.15
done
sleep 0.8

# 사이드바 재오픈
tmux run-shell -t "$attached_session" "~/.local/bin/tmux-session-launcher --open-sidebar"
sleep 1
# 사이드바 다시 닫기
new_sidebar_pane_s5=$(tmux list-panes -s -t "$attached_session" -F '#{pane_id} #{pane_title}' | awk '$2 == "dotfiles-session-sidebar" {print $1}' | head -n 1)
tmux send-keys -t "$new_sidebar_pane_s5" q
sleep 0.8
layout_reopened=$(tmux display-message -p '#{window_layout}')

# 원래 복구 상태(사이드바 열린 상태)로 원상 복구
tmux run-shell -t "$attached_session" "~/.local/bin/tmux-session-launcher --open-sidebar"
sleep 1
# 새로운 사이드바 pane ID 재갱신
sidebar_pane=$(tmux list-panes -s -t "$attached_session" -F '#{pane_id} #{pane_title}' | awk '$2 == "dotfiles-session-sidebar" {print $1}' | head -n 1)
sidebar_pid=$(tmux display-message -p -t "$sidebar_pane" '#{pane_pid}' 2>/dev/null || echo "")

# 메모리 누수 측정을 위한 최종 RSS 획득
rss_after=$(ps -p "$sidebar_pid" -o rss= 2>/dev/null | awk '{print $1}' || echo 0)
leak_kb=$((rss_after - rss_before))
leak_msg=""
if [ "$leak_kb" -gt 0 ]; then
    leak_msg=" / Leak: +${leak_kb} KB"
else
    leak_msg=" / Leak: +0 KB"
fi

if [ "$layout_closed" = "$layout_reopened" ]; then
    layout_preservation_score="100% (Matched)${leak_msg}"
else
    layout_preservation_score="Mismatched${leak_msg}"
fi

# ==================================================
# [시나리오 6] 히스토리 복원 정확도 (Restore Path/Layout/Structure Accuracy)
# ==================================================
echo "Running Scenario 6: Restore Structure & Path Accuracy profiling..."

restore_accuracy="ERROR"
if [ -n "$archive_file" ] && [ -f "$archive_file" ]; then
    # 아카이브에 기록된 PWD와 세션 구조(Pane, Window 개수) 추출
    expected_pwd=$(awk -F'\t' '$1 == "pane" {print $3; exit}' "$archive_file")
    expected_pane_count=$(grep -c "^pane" "$archive_file")
    expected_window_count=$(grep -c "^window" "$archive_file")
    
    # 히스토리 복원 지시 (시간 측정 시작)
    t_rest_start=$(date +%s%N)
    tmux send-keys -t "$sidebar_pane" o
    sleep 0.5
    # 히스토리 창에서 Space로 선택하고 Enter로 복원
    tmux send-keys -t "$sidebar_pane" Space Enter
    
    # 세션 복원 감지 루프 (최대 3초 대기)
    for attempt in {1..30}; do
        if tmux has-session -t "=$dummy_sess" 2>/dev/null; then
            break
        fi
        sleep 0.1
    done
    t_rest_end=$(date +%s%N)
    rest_duration=$(( (t_rest_end - t_rest_start) / 1000000 ))
    
    # 복원된 세션 검증
    if tmux has-session -t "=$dummy_sess" 2>/dev/null; then
        restored_pwd=$(tmux list-panes -s -t "$dummy_sess" -F '#{pane_current_path}' | head -n 1)
        restored_pane_count=$(tmux list-panes -s -t "$dummy_sess" | wc -l)
        restored_window_count=$(tmux list-windows -t "$dummy_sess" | wc -l)
        
        if [ "$expected_pwd" = "$restored_pwd" ] && [ "$expected_pane_count" -eq "$restored_pane_count" ] && [ "$expected_window_count" -eq "$restored_window_count" ]; then
            restore_accuracy="100% (Integrity Verified) / Time: ${rest_duration} ms"
        else
            restore_accuracy="Mismatched / Time: ${rest_duration} ms (Path: $restored_pwd vs $expected_pwd / Panes: $restored_pane_count vs $expected_pane_count)"
        fi
        # 더미 세션 정리
        tmux kill-session -t "$dummy_sess"
    else
        restore_accuracy="Restore Failed / Time: ${rest_duration} ms"
    fi
fi

# ==================================================
# [시나리오 7] 그리드 경계 및 시각적 렌더링 무결성 검사 (Visual Snapshot Validation)
# ==================================================
echo "Running Scenario 7: Visual Snapshot & Grid Boundary checks..."

# [추가] 임계 크기 리사이즈 스트레스 및 복원성 검증 (Threshold Resize Resiliency)
echo "Testing extreme geometry threshold resize resiliency..."
tmux resize-pane -t "$sidebar_pane" -x 15
sleep 0.3
tmux resize-pane -t "$sidebar_pane" -x 35
sleep 0.5

tmux capture-pane -p -t "$sidebar_pane" > /tmp/sidebar_grid_check.txt

# 1. 가로폭 검사
max_line_len=$(awk '{ if (length($0) > max) max = length($0) } END { print max }' /tmp/sidebar_grid_check.txt)
max_line_len=${max_line_len:-0}
expected_width=35 # 기본 넓이

# 2. ANSI 이스케이프 유출 검사 (렌더링 깨짐 확인)
ansi_escapes_found=$(grep -E -c '\x1b\[|\033\[' /tmp/sidebar_grid_check.txt || true)

# 3. 커서 포인터 정합성 검사 (커서가 정확히 1개 존재해야 함)
cursor_valid=$(grep -E -c '^\s*>\s|^\s*>\*' /tmp/sidebar_grid_check.txt || true)

visual_integrity="Normal"
if [ "$ansi_escapes_found" -gt 0 ]; then
    visual_integrity="ANSI Leak ($ansi_escapes_found lines)"
elif [ "$cursor_valid" -ne 1 ]; then
    visual_integrity="Cursor Count Error ($cursor_valid)"
fi

if [ "$max_line_len" -le "$expected_width" ] && [ "$visual_integrity" = "Normal" ]; then
    grid_truncate_score="$max_line_len cols / Visual: $visual_integrity"
else
    overflow=$((max_line_len - expected_width))
    grid_truncate_score="Overflow by $overflow cols / Visual: $visual_integrity"
fi
rm -f /tmp/sidebar_grid_check.txt

# ==================================================
# 결과 출력 테이블 생성
# ==================================================
echo ""
echo "=================================================="
echo " PROFILED BASELINE METRICS (7-Scenario Summary)"
echo "=================================================="
printf "| %-30s | %-20s |\n" "Metric" "Value"
printf "|-%-30s-|-%-20s-|\n" "------------------------------" "--------------------"
printf "| %-30s | %-20s |\n" "1. Idle CPU (Peak) / RSS" "$avg_idle_cpu ($max_idle_cpu) / $avg_idle_rss"
printf "| %-30s | %-20s |\n" "2. Active CPU (Peak) / RSS" "$avg_active_cpu ($max_active_cpu) / $avg_active_rss"
if [ "$latency" = "ERROR" ]; then
    printf "| %-30s | %-20s |\n" "3. Switch Latency" "ERROR"
else
    reactivity_ms=$(echo "$latency" | awk -F',' '{print $1}')
    switch_ms=$(echo "$latency" | awk -F',' '{print $2}')
    printf "| %-30s | %-20s |\n" "3. Switch Latency" "${switch_ms} ms (Reactivity: ${reactivity_ms} ms)"
fi
printf "| %-30s | %-20s |\n" "4. Archive Metadata Size" "$archive_size"
printf "| %-30s | %-20s |\n" "5. Layout Preservation Ratio" "$layout_preservation_score"
printf "| %-30s | %-20s |\n" "6. Restore Accuracy" "$restore_accuracy"
printf "| %-30s | %-20s |\n" "7. Grid Boundary check" "$grid_truncate_score"
echo "=================================================="

# 테스트 종료 후 tmux 서버 종료
echo "Cleaning up: Terminating the tmux server..."
tmux kill-server
