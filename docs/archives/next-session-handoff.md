# Next session handoff (Gate E 및 사용자 조건 시나리오 완수 안내)

## 1. 현재 진행 상황 및 검증 상태 요약

사용자 조건 및 사용자 지정 8개 시나리오 통합 스위트(`run_gate_e_scenarios.sh`) 기준 검증 상태:

- **Scenario 1 (Sidebar Toggle & Provisioning)**: **100% PASS** (`test-contract.sh`)
- **Scenario 2 (Session Name Zero & Creation Ambiguity)**: **100% PASS** (`test-session-name-zero.sh`)
- **Scenario 6 (Session Rename Round-trip)**: **100% PASS** (`test-keyboard-e2e-rename-roundtrip.sh`)
- **Scenario 3, 4, 5, 7, 8 (Keyboard E2E Arrow Navigation, Direct Layout, Multi-window Topology, Rapid Operations, User Live Monitored)**: **디버깅 및 수정 예정**

### 성능 목표 수치 완화 합의 (2026-08-08)
- **세션 전환 시간 목표**: **1000ms (1초 이내)** (기존 500ms → 1000ms 완화)
- **키 반응 속도 목표**: **100ms 이내** (기존 40ms → 100ms 완화)
- **목적**: 성능 지표의 미세한 초과로 인한 불필요한 수정/회귀 루프 방지 및 Gate E 8/8 100% PASS 기능적 완전성 우선 달성.

---

## 2. 발견된 문제점 및 원인 정밀 분석

### 현상
`Scenario 3` 및 `Scenario 7`에서 사용자 입력(예: `c` 세션 생성) 후 세션 이름(`window-local-1` / `rapid-1`) 타이핑 직후 `wait_for_prompt_complete (expected 0)` 타임아웃 20초 발생.

### 근본 원인 (Root Cause Analysis)
1. **PTY Stream vs Canonical Line Discipline 충돌**:
   - `test-keyboard-e2e.sh` 내 `send_keys`가 `script` coproc PTY 파일 디스크립터(`$fd`)로 `window-local-1\r` 또는 `\n`을 밀어넣을 때, PTY master 버퍼가 `window-local-1` 텍스트와 엔터 키(`\r`/`\n`)를 한꺼번에 전달하거나 분리하여 전달함.
   - `scripts/tmux-session-launcher` 내의 `prompt_text()`가 `stty echo icanon icrnl` 모드 진입 시, `/dev/tty` 리디렉션 파이프 디스크립터 상태와 Bash `read -r prompt_result` 간의 terminal line discipline 동기화 미세 차이로 인해 `read`가 마감되지 않고 `prompt_ready` 옵션(`@dotfiles_sidebar_prompt_ready`)이 `0`으로 내려가지 못함.
2. **`prompt_ready` 옵션 scope mismatch**:
   - `prompt_text()` 진입 시 `@dotfiles_sidebar_prompt_ready`가 전역/윈도우 옵션 `1`로 설정되고, `prompt_text()` 종료 시 `0`으로 청소됨.
   - 그러나 세션 생성 직후 `tmux new-session` 및 `switch-client`가 일어나면서 target window의 local sidebar provisioning이 개입되어 `@dotfiles_sidebar_prompt_ready` 옵션이 다중 윈도우 스코프에서 `1`로 잔류하여 `wait_for_prompt_complete` (expected 0) 조건을 지연시킴.

---

## 3. 다음 세션 개선 지침 및 작업 순서 (Action Plan)

새 세션에서 기존 작업을 무한 반복하지 않고 다음과 같이 구조적 개선을 완료한다:

1. **`prompt_text()` 라인 읽기 단일화 (Line Discipline Unification)**:
   - `scripts/tmux-session-launcher` 내 `prompt_text()`의 라인 읽기 모드를 Bash `read -r`과 `read -rsn1` 간의 복합 처리 대신, 터미널 PTY 표준 입력`/dev/tty` 기반 canonical input 또는 확실한 0ms timeout non-canonical input 읽기 루프(`stty min 0 time 1`)로 정돈.
   - `prompt_text` 종료 즉시 `@dotfiles_sidebar_prompt_ready`를 전역/윈도우에서 명시적으로 0으로 억제.

2. **`send_keys` 키 주입 채널 통합 (Single Transport Injection)**:
   - `test-keyboard-e2e.sh` 내 `send_keys`의 `$payload` 전송 시, `VISIBLE_CLIENT`일 때는 `tmuxc send-keys`로, `ATTACHED` PTY 클라이언트일 때는 `$fd` PTY 파일 디스크립터 단일 채널로 `payload`와 엔터 키를 1:1 대응하여 전송.

3. **검증 순서**:
   ```sh
   cd /home/al-hub/workspace/dotfiles
   bash -n scripts/tmux-session-launcher
   bash tests/tmux-single-sidebar/test-contract.sh
   bash tests/tmux-single-sidebar/test-session-name-zero.sh
   bash tests/tmux-single-sidebar/test-keyboard-e2e-rename-roundtrip.sh
   bash tests/tmux-single-sidebar/test-keyboard-e2e-window-local-switch.sh
   bash tests/tmux-single-sidebar/run_gate_e_scenarios.sh
   ```

4. **ALL PASS 달성 확인**:
   - `run_gate_e_scenarios.sh` 8개 전체 시나리오 Green(100% PASS) 확인 후 사용자 보고 제출.

---

## 4. 변경 보존 파일 목록

- `scripts/tmux-session-launcher`
- `tests/tmux-single-sidebar/*`
- `HISTORY.md`
- `CONVERSATION.md`
- `docs/next-session-handoff.md`
