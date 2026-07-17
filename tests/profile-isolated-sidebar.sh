#!/usr/bin/env bash
# tests/profile-isolated-sidebar.sh
# 
# 이 스크립트는 완전히 격리된 별도의 urxvt 터미널 창을 생성하여 tmux 서버를 가동하고,
# 사이드바 및 10개 이상의 세션들을 자동으로 생성하여 7대 시나리오 테스트를 수행합니다.
# 테스트가 완료되면 격리된 tmux 서버와 터미널 창을 모두 안전하게 종료 및 정리합니다.
set -euo pipefail

# WSLg GPU 가속 버그 및 입력기(XIM) 대기 버그 우회 설정
export LIBGL_ALWAYS_SOFTWARE=1
export XMODIFIERS=""

# 매개변수 파싱 (대기 프롬프트 제어)
INTERACTIVE=false
if [ "${1:-}" = "--interactive" ] || [ "${1:-}" = "-i" ]; then
    INTERACTIVE=true
fi

echo "=================================================="
echo " Starting Isolated Terminal Sidebar Profiler"
echo "=================================================="

SOCKET="profile-isolated-$$"
LAUNCHER="$HOME/.local/bin/tmux-session-launcher"
HISTORY_DIR="$HOME/.cache/dotfiles/tmux-session-history"

# 1. 격리된 urxvt 터미널 및 tmux 서버 기동 (윈도우 크기 100x30 지정)
echo "1. Spawning isolated urxvt terminal running tmux..."
urxvt -pe "" -fn "xft:Ubuntu Mono:pixelsize=16,xft:DejaVu Sans Mono:pixelsize=16" -geometry 100x30 -title "tmux-sidebar-profiler-sandbox" -e /usr/bin/tmux -L "$SOCKET" new-session -s session-long-name-1 &
sleep 2.0

# 2. 클라이언트 연결 및 TTY 확인
client_tty=$(tmux -L "$SOCKET" list-clients -F '#{client_tty}' 2>/dev/null | head -n 1 || echo "")
if [ -z "$client_tty" ]; then
    echo "ERROR: Failed to initialize isolated terminal client."
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    exit 1
fi
echo "Isolated Client TTY: $client_tty"

# 3. 테스트용 세션들 생성 (session-long-name-2 ~ session-long-name-12)
echo "2. Populating isolated tmux sessions..."
for i in {2..12}; do
    tmux -L "$SOCKET" new-session -d -s "session-long-name-$i"
done

# 4. 사이드바 오픈 (직접 split-window 실행)
echo "3. Opening sidebar in the isolated session..."
sidebar_pane=$(tmux -L "$SOCKET" split-window -d -P -F '#{pane_id}' -t "session-long-name-1:0" -h -b -l 35 "$LAUNCHER --sidebar")
tmux -L "$SOCKET" select-pane -t "$sidebar_pane" -T "dotfiles-session-sidebar"
sleep 1.5
sidebar_pid=$(tmux -L "$SOCKET" display-message -p -t "$sidebar_pane" '#{pane_pid}' 2>/dev/null || echo "")

if [ -z "$sidebar_pane" ] || [ -z "$sidebar_pid" ]; then
    echo "ERROR: Failed to locate sidebar pane or PID."
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    exit 1
fi
echo "Sidebar PID: $sidebar_pid (Pane: $sidebar_pane)"

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
work_pane=$(tmux -L "$SOCKET" list-panes -s -t "$target_work_session" -F '#{pane_id} #{pane_title}' 2>/dev/null | awk '$2 != "dotfiles-session-sidebar" {print $1; exit}' || true)

if [ -n "$work_pane" ]; then
    # claude 바이너리 모킹
    pkill -f claude || true
    mkdir -p ~/.gemini/antigravity-cli
    rm -f ~/.gemini/antigravity-cli/claude
    cp /bin/bash ~/.gemini/antigravity-cli/claude
    
    # tick 출력을 반복하는 claude 구동
    tmux -L "$SOCKET" send-keys -t "$work_pane" "~/.gemini/antigravity-cli/claude -c 'while true; do echo \"tick \$RANDOM\"; sleep 0.5; done'" C-m
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
    tmux -L "$SOCKET" send-keys -t "$work_pane" C-c
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

latency=$(python3 -c "
import time, subprocess, sys

# 1. 현재 사이드바의 세션 목록과 커서 위치 캡처
out = subprocess.check_output(['tmux', '-L', '$SOCKET', 'capture-pane', '-p', '-t', '$sidebar_pane']).decode().strip().split('\n')
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
    subprocess.run(['tmux', '-L', '$SOCKET', 'send-keys', '-t', '$sidebar_pane', first_key])
    while True:
        try:
            curr_pane = subprocess.check_output(['tmux', '-L', '$SOCKET', 'capture-pane', '-p', '-t', '$sidebar_pane']).decode().strip().split('\n')
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
    subprocess.run(['tmux', '-L', '$SOCKET', 'send-keys', '-t', '$sidebar_pane'] + remaining_keys)

t_switch_start = time.time()
while True:
    try:
        client_out = subprocess.check_output(['tmux', '-L', '$SOCKET', 'list-clients', '-F', '#{client_tty} #{session_name}']).decode()
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

# ==================================================
# [시나리오 4] 아카이브 메타데이터 파일 크기 측정
# ==================================================
echo "Running Scenario 4: Archive File Size profiling..."

# 임시 세션 삭제를 지시하여 아카이브 생성 (시간 측정)
t_arch_start=$(date +%s%N)
tmux -L "$SOCKET" run-shell "$LAUNCHER --delete-session-after-archive session-long-name-12 true"
t_arch_end=$(date +%s%N)
arch_duration=$(( (t_arch_end - t_arch_start) / 1000000 ))
sleep 1.5

archive_file=$(find "$HISTORY_DIR" -type f -name "*session-long-name-12*" | sort | tail -n 1)
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
new_sidebar_pane=$(tmux -L "$SOCKET" list-panes -s -t "session-long-name-2" -F '#{pane_id} #{pane_title}' | awk '$2 == "dotfiles-session-sidebar" {print $1}' | head -n 1)
tmux -L "$SOCKET" send-keys -t "$new_sidebar_pane" q
sleep 0.8
layout_closed=$(tmux -L "$SOCKET" display-message -t "session-long-name-2" -p '#{window_layout}')

# 메모리 누수 측정을 위한 초기 RSS 획득
rss_before=$(ps -p "$sidebar_pid" -o rss= 2>/dev/null | awk '{print $1}' || echo 0)

# [추가] 윈도우 리사이즈 및 연타 스트레스 테스트 시뮬레이션
echo "Simulating rapid toggle stress (3 times)..."
for j in {1..3}; do
    tmux -L "$SOCKET" split-window -d -P -F '#{pane_id}' -t "session-long-name-2:0" -h -b -l 35 "$LAUNCHER --sidebar" >/dev/null 2>&1 || true
    sleep 0.15
done
sleep 0.8

# 사이드바 재오픈
new_sidebar_pane_s5=$(tmux -L "$SOCKET" split-window -d -P -F '#{pane_id}' -t "session-long-name-2:0" -h -b -l 35 "$LAUNCHER --sidebar")
tmux -L "$SOCKET" select-pane -t "$new_sidebar_pane_s5" -T "dotfiles-session-sidebar"
sleep 1.0
# 사이드바 다시 닫기
tmux -L "$SOCKET" send-keys -t "$new_sidebar_pane_s5" q
sleep 0.8
layout_reopened=$(tmux -L "$SOCKET" display-message -t "session-long-name-2" -p '#{window_layout}')

# 원래대로 재오픈
new_sidebar_pane=$(tmux -L "$SOCKET" split-window -d -P -F '#{pane_id}' -t "session-long-name-2:0" -h -b -l 35 "$LAUNCHER --sidebar")
tmux -L "$SOCKET" select-pane -t "$new_sidebar_pane" -T "dotfiles-session-sidebar"
sleep 1.0
# 새로운 사이드바 pane ID 및 PID 재갱신
sidebar_pid=$(tmux -L "$SOCKET" display-message -p -t "$new_sidebar_pane" '#{pane_pid}' 2>/dev/null || echo "")

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
    
    # 히스토리 창 오픈 (시간 측정 시작)
    t_rest_start=$(date +%s%N)
    tmux -L "$SOCKET" send-keys -t "$new_sidebar_pane" o
    sleep 0.5
    # 최신 아카이브(s12) 선택 및 복원
    tmux -L "$SOCKET" send-keys -t "$new_sidebar_pane" Space Enter
    
    # 세션 복원 감지 루프 (최대 3초 대기)
    for attempt in {1..30}; do
        if tmux -L "$SOCKET" has-session -t "=session-long-name-12" 2>/dev/null; then
            break
        fi
        sleep 0.1
    done
    t_rest_end=$(date +%s%N)
    rest_duration=$(( (t_rest_end - t_rest_start) / 1000000 ))
    
    if tmux -L "$SOCKET" has-session -t "=session-long-name-12" 2>/dev/null; then
        restored_pwd=$(tmux -L "$SOCKET" list-panes -s -t "session-long-name-12" -F '#{pane_current_path}' | head -n 1)
        restored_pane_count=$(tmux -L "$SOCKET" list-panes -s -t "session-long-name-12" | wc -l)
        restored_window_count=$(tmux -L "$SOCKET" list-windows -t "session-long-name-12" | wc -l)
        
        if [ "$expected_pwd" = "$restored_pwd" ] && [ "$expected_pane_count" -eq "$restored_pane_count" ] && [ "$expected_window_count" -eq "$restored_window_count" ]; then
            restore_accuracy="100% (Integrity Verified) / Time: ${rest_duration} ms"
        else
            restore_accuracy="Mismatched / Time: ${rest_duration} ms (Path: $restored_pwd vs $expected_pwd / Panes: $restored_pane_count vs $expected_pane_count)"
        fi
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
tmux -L "$SOCKET" resize-pane -t "$new_sidebar_pane" -x 15
sleep 0.3
tmux -L "$SOCKET" resize-pane -t "$new_sidebar_pane" -x 35
sleep 0.5

tmux -L "$SOCKET" capture-pane -p -t "$new_sidebar_pane" > /tmp/sidebar_grid_check_isolated.txt

# 1. 가로폭 검사
max_line_len=$(awk '{ if (length($0) > max) max = length($0) } END { print max }' /tmp/sidebar_grid_check_isolated.txt)
max_line_len=${max_line_len:-0}
expected_width=35

# 2. ANSI 이스케이프 유출 검사 (렌더링 깨짐 확인)
ansi_escapes_found=$(grep -E -c '\x1b\[|\033\[' /tmp/sidebar_grid_check_isolated.txt || true)

# 3. 커서 포인터 정합성 검사 (커서가 정확히 1개 존재해야 함)
cursor_valid=$(grep -E -c '^\s*>\s|^\s*>\*' /tmp/sidebar_grid_check_isolated.txt || true)

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
rm -f /tmp/sidebar_grid_check_isolated.txt

# ==================================================
# 격리 터미널 및 tmux 서버 정리 (종료)
# ==================================================
if [ "$INTERACTIVE" = "true" ]; then
    echo ""
    echo ">>> [모니터링 대기] 화면에 생성된 urxvt 터미널 창을 통해 사이드바와 세션 동작을 눈으로 직접 모니터링할 수 있습니다."
    read -r -p ">>> 모니터링을 마치고 임시 tmux 서버 및 터미널 창을 종료하려면 [Enter] 키를 누르세요..." dummy_input
fi


echo "Cleaning up: Terminating isolated tmux server..."
tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
sleep 1.0

# ==================================================
# 결과 출력 테이블 생성
# ==================================================
echo ""
echo "=================================================="
echo " ISOLATED SANDBOX BASELINE METRICS (7 Scenarios)"
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
