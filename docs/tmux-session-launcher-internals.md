# tmux-session-launcher 핵심 로직 문서

> 이 문서는 `scripts/tmux-session-launcher`의 핵심 아키텍처를 설명한다.
> AI CLI가 이 파일을 먼저 읽으면, 4000줄 코드를 전부 분석하지 않고도
> 문제 영역을 빠르게 찾을 수 있다.

## 아키텍처 개요

`feature/single-sidebar`의 sidebar는 **tmux server당 하나의 pane과 하나의
bash process**로 동작한다. session 전환 시 process를 respawn하지 않고 기존
pane을 target session의 active window로 `move-pane`한다. `master`의 이전
per-session 구조와 구분되는 branch 전용 동작이다.

```
┌─────────────────────────────────────────────────┐
│ tmux server                                      │
│  ├─ session "A"                                  │
│  │   └─ work panes                               │
│  ├─ session "B"                                  │
│  │   ├─ pane %1 (sidebar bash) ← run_tui 루프    │
│  │   └─ work panes                               │
│  └─ client (attached to session "B")             │
└─────────────────────────────────────────────────┘
```

## 핵심 변수 (프로세스 로컬)

| 변수 | 용도 | 업데이트 시점 |
|---|---|---|
| `current_session` | `*` 표시 기준. tmux가 현재 어떤 세션에 attached인지 | `collect_sessions()` 내 `tmux display-message -p '#S'` |
| `selected_session` | `>` 표시 기준 세션 이름 | 방향키 이동, enter, force_refresh 시 |
| `selected_index` | `>` 표시 기준 배열 인덱스 | `move_selection()`, `align_selection_to_session()` |
| `sidebar_session_cached` | 이 sidebar pane의 현재 owner session | pane 이동 감지 시 `collect_sessions()` |
| `snapshot_signature` | 세션 목록 변경 감지용 시그니처 | `collect_sessions()` |

## 행 표시 마크 결정 로직

```
row_mark_value(index):
  name = session_names[index]
  if index == selected_index AND name == current_session → ">*"
  elif index == selected_index                           → "> "
  elif name == current_session                           → " *"
  else                                                   → "  "
```
**위치**: 라인 2107-2121

## 이벤트 루프 (run_tui)

**위치**: 라인 3599-3835

```
while true:
  1. read_key(timeout)          ← 키 입력 대기
  2. key dispatch:
     - up/down → move_selection()     ← 즉시 render_selection_pair
     - enter   → switch_session()     ← 세션 전환
                  collect_sessions()   ← 상태 갱신
                  render_full()        ← 전체 다시 그리기
     - create/rename/delete → 해당 동작 후 collect + render
  3. full_render_required check → render_full() if true
  4. maintenance tick (1초 간격):
     a. render_age_cells()              ← 시간 셀만 갱신
     b. force_refresh 체크 (5초 간격)   ← IPC 수신
     c. state_refresh_due (5초 간격)    ← 상태 변경 감지
  5. animation tick                     ← AI 활동 애니메이션
```

### 타이밍 파라미터

| 변수 | 기본값 | 역할 |
|---|---|---|
| `SIDEBAR_POLL_TIMEOUT` | 0.15s | read_key 기본 타임아웃 |
| `SIDEBAR_ADAPTIVE_IDLE_TIMEOUT` | 1.0s | 애니메이션 없을 때 read 타임아웃 |
| `SIDEBAR_ANIMATION_INTERVAL` | 0.25s | 애니메이션 중 read 타임아웃 |
| `SIDEBAR_FORCE_REFRESH_CHECK_SECONDS` | 5s | force_refresh 플래그 체크 간격 |
| `SIDEBAR_STATE_REFRESH_SECONDS` | 5s | 주기적 상태 갱신 간격 |
| `SIDEBAR_KEY_MAINTENANCE_COOLDOWN_MS` | 250ms | 키 입력 후 maintenance 유예 |

## 세션 전환 흐름 (switch_session)

**위치**: `switch_session()` 및 `tmux-sidebar-controller`

```
switch_session(session_name):
  1. global sidebar pane과 owner session을 resolve
  2. owner session의 client tty를 명시적으로 resolve
  3. source work layout 저장
  4. target active window/work pane 검증
  5. 기존 sidebar pane을 target으로 move-pane
  6. 명시적 client에 switch-client 실행
  7. 동일 pane process에 refresh signal 전송
  8. 실패 시 pane rollback 및 source layout 복구
```

### 전환 후 surviving sidebar 처리
```
enter 핸들러:
  switch_session("$selected_session")  ← pane 이동 + client 전환
  collect_sessions(false, "$selected_session")
  render_full()
```

### 전환 후 target sidebar 처리 — signal + polling fallback

sidebar는 SIGUSR2를 받으면 refresh pending 상태를 기록하고 다음 event-loop
경계에서 자기 pane의 현재 owner session을 다시 확인한다. pane 이동으로 owner가
바뀌면 sessions view로 재정렬하고 history view 상태를 초기화한다. signal이
유실되거나 startup race가 발생하면 force-refresh flag polling이 fallback으로
동작한다:

```
SIGUSR2:
  refresh_signal_pending = true
  event loop 다음 경계에서 재개
  my_session = sidebar_session_name()  ← pane ID로 owner 재탐색
  collect_sessions(false, "$my_session")
  align_selection_to_session("$my_session")
  render_full()

fallback maintenance tick:
  if 1초 경과 since last check:
    force_refresh = tmux show-option -gqv "@sidebar_force_refresh_$my_session"
    if force_refresh == "1":
      collect_sessions(false, "$my_session")
      align_selection_to_session("$my_session")
      render_full()
      tmux set-option -g "$flag" 0
```

signal 경로는 세션 전환 직후 target을 갱신하고, polling은 startup/race와
signal 유실을 보장하는 fallback이다.

history restore의 async 경로도 bounded transition polling을 사용한다. restore
작업은 target session, sidebar owner, attached client가 일치하고 sidebar pane이
선택될 때까지 짧게 기다린 후 다음 입력을 처리한다. 이때 sidebar owner가
변경되어도 history view/index는 유지한다. 반복 restore 입력에 대한 PTY focus
race는 `tests/tmux-single-sidebar/test-keyboard-e2e.sh`에서 추적한다.

## IPC 메커니즘

sidebar controller와 sidebar process 간 통신은 tmux 글로벌 옵션과 signal을
이용한다. tmux command의 server/pane/window 경계는
`scripts/tmux-sidebar-tmux-adapter`가 담당하고 lifecycle 전이는
`scripts/tmux-sidebar-controller`가 담당한다:

| 옵션 | 용도 | 설정 | 읽기 |
|---|---|---|---|
| `@sidebar_force_refresh_<session>` | pane 이동 후 refresh fallback 상태 | `switch_session()` 및 toggle 경로 | main loop |
| `@dotfiles-session-work-layout` | 작업 영역 레이아웃 저장/복구 | `save_work_layout()` | `restore_work_layout()` |
| `SIGUSR2` | surviving sidebar process 즉시 refresh 요청 | controller/switch 경로 | `handle_refresh_signal()` |

## 데이터 수집 (collect_sessions)

**위치**: 라인 1467-2002

### 최적화 경로

1. **전체 스캔** (`force_scan=true`): 모든 세션+pane 재조회. 세션 생성/삭제 후 사용.
2. **대상 스캔** (`requested_scan_session` 지정):
   - `row_cache_reusable=true`: 세션 시그니처 불변 시 배열 구조 재사용, 대상 행만 갱신
   - `incremental_pane_scan=true`: `tmux list-panes`를 대상 세션만 조회
3. **캐시**: `cached_session_panes_snapshot`, `cached_session_cli_state` 등으로 반복 조회 회피

### collect_sessions 내 세션 전환 감지

```
old_current_session = current_session
current_session = tmux display-message -p '#S'

session_switch_occurred = (current_session != old_current_session)
client_switch_occurred = (client_sessions != old_client_sessions)

if client_switch_occurred AND client_session == my_session:
  selected_session = my_session   ← > 커서를 자기 세션으로 정렬
  full_render_required = true
```

## 렌더링 계층

### 전체 렌더 (render_full)
**위치**: 라인 2485-2515

subshell에서 전체 출력을 `$buffer`에 모아놓고 `printf '%s' "$buffer"`로
한 번에 출력. 화면 깜박임(flicker) 방지의 핵심.

```
render_full():
  buffer = $(
    printf '\033[H\033[2J'   ← 화면 초기화
    hide_cursor              ← 커서 숨김
    render_header
    render_visible_rows      ← 각 행에 format_row 호출
    render_footer
  )
  printf '%s' "$buffer"      ← 단일 write로 출력
```

### 선택적 렌더

| 함수 | 렌더링 범위 | 호출 시점 |
|---|---|---|
| `render_selection_pair(old, new)` | 이전/현재 선택 행 2줄만 | 방향키 이동 |
| `render_age_cells()` | 시간 셀(우측 10칸)만 | 1초 tick |
| `render_animated_name_cells()` | 애니메이션 대상 이름 셀만 | idle tick |
| `render_animation_state_changes()` | 상태 변경 행만 | state_refresh 후 |

### ANSI 커서 포지셔닝

모든 선택적 렌더는 `\033[line;colH`로 정확한 좌표에 쓰기를 하고,
`\033[2K`로 해당 줄만 지운다. 화면 전체를 지우지 않으므로 flicker 없음.

```
format_row(index):
  line = 2 + index - scroll_offset
  printf -v result '\033[%s;1H\033[2K%s %s %s ' "$line" "$mark" "$name" "$age"
```

## 안정 갱신을 위한 방어 메커니즘

### 1. maintenance cooldown (라인 2727-2736)
키 입력 후 250ms 이내에는 maintenance(age갱신, force체크, state갱신)를 건너뜀.
→ 빠른 방향키 연타 시 IPC 지연이 렌더링에 영향주지 않음.

### 2. 버퍼링된 출력
`render_full`은 subshell 캡처 후 단일 `printf`로, 선택적 렌더는
`printf -v`로 변수에 모아서 한 번에 출력.

### 3. 커서 숨김 (라인 1457-1465)
`\033[?25l`로 터미널 커서를 숨겨서 ANSI 포지셔닝 중 커서 점프가 보이지 않음.

### 4. AI fingerprint 안정화 (라인 1870-1872)
세션 전환/리사이즈/클라이언트 전환 시 AI fingerprint를 이전 값으로 유지하여
일시적인 상태 변경이 애니메이션을 불필요하게 트리거하지 않음.

### 5. 시그니처 기반 변경 감지
`snapshot_signature`가 이전과 동일하면 렌더링을 완전히 건너뜀.
세션 목록이 변하지 않은 idle 상태에서 CPU 사용을 최소화.
