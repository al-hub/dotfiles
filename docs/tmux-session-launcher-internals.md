# tmux-session-launcher 핵심 로직 문서

> 이 문서는 `scripts/tmux-session-launcher`의 핵심 아키텍처를 설명한다.
> AI CLI가 이 파일을 먼저 읽으면, 4000줄 코드를 전부 분석하지 않고도
> 문제 영역을 빠르게 찾을 수 있다.

## 아키텍처 개요

sidebar는 **세션당 하나의 bash 프로세스**로 동작하며, 각 프로세스는 독립적인
이벤트 루프(`run_tui`)를 돌린다. 세션 전환 시 사용자 화면은 target 세션으로
이동하지만, 소스 세션의 sidebar 프로세스도 background에서 계속 동작한다.

```
┌─────────────────────────────────────────────────┐
│ tmux server                                      │
│  ├─ session "A"                                  │
│  │   ├─ pane %1 (sidebar bash) ← run_tui 루프    │
│  │   └─ pane %2 (work zsh)                       │
│  ├─ session "B"                                  │
│  │   ├─ pane %3 (sidebar bash) ← run_tui 루프    │
│  │   └─ pane %4 (work zsh)                       │
│  └─ client (attached to session "B")             │
└─────────────────────────────────────────────────┘
```

## 핵심 변수 (프로세스 로컬)

| 변수 | 용도 | 업데이트 시점 |
|---|---|---|
| `current_session` | `*` 표시 기준. tmux가 현재 어떤 세션에 attached인지 | `collect_sessions()` 내 `tmux display-message -p '#S'` |
| `selected_session` | `>` 표시 기준 세션 이름 | 방향키 이동, enter, force_refresh 시 |
| `selected_index` | `>` 표시 기준 배열 인덱스 | `move_selection()`, `align_selection_to_session()` |
| `sidebar_session_cached` | 이 sidebar pane이 속한 세션 이름 (불변) | 최초 1회 `sidebar_session_name()` |
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

**위치**: 라인 871-951

```
switch_session(session_name):
  1. ensure_session_sidebar(session_name)   ← target에 sidebar pane 보장
  2. tmux set-option -g "@sidebar_force_refresh_$session_name" 1
     ↑ target sidebar에 갱신 신호 (IPC)
  3. client_tty 찾기
  4. tmux switch-client -t "=$session_name"  ← 실제 전환
  5. tmux set-option -g "@sidebar_force_refresh_$session_name" 1
     ↑ 한번 더 (race condition 방어)
  6. current_session = session_name   ← 로컬 변수 즉시 갱신
  7. selected_session = session_name  ← 로컬 변수 즉시 갱신
```

### 전환 후 소스 sidebar 처리 (라인 3674-3677)
```
enter 핸들러:
  switch_session("$selected_session")  ← 전환
  collect_sessions(false, "$selected_session")  ← 소스 sidebar 갱신
  render_full()  ← 소스 sidebar 다시 그리기 (background)
```

### 전환 후 target sidebar 처리 — IPC polling

target sidebar는 **force_refresh 플래그**를 polling으로 감지한다:

```
maintenance tick (1초마다):
  if 5초 경과 since last check:
    force_refresh = tmux show-option -gqv "@sidebar_force_refresh_$my_session"
    if force_refresh == "1":
      collect_sessions()
      align_selection_to_session("$my_session")  ← > 커서를 자기 세션으로
      render_full()
      tmux set-option -g "$flag" 0  ← 플래그 리셋
```

**이 5초 polling이 `>` 커서 지연의 근본 원인이다.**

## IPC 메커니즘

sidebar 프로세스 간 통신은 tmux 글로벌 옵션을 이용한다:

| 옵션 | 용도 | 설정 | 읽기 |
|---|---|---|---|
| `@sidebar_force_refresh_<session>` | 세션 전환 시 target sidebar 갱신 신호 | `switch_session()` 라인 914,940 | 메인 루프 라인 3776 |
| `@dotfiles-session-work-layout` | 작업 영역 레이아웃 저장/복구 | `save_work_layout()` | `restore_work_layout()` |

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
