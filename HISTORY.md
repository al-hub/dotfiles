# Project History

이 파일은 에이전트와 사용자가 주요 작업 이력을 이어받기 위한 기록입니다.

## 작성 규칙

- 의미 있는 설정 변경, 설치 흐름 변경, 위험한 레거시 동작 정리, 검증 결과를 남깁니다.
- 새 항목은 위에 추가합니다.
- 작은 오타 수정이나 설명만 바뀐 경우는 필요할 때만 기록합니다.
- 각 항목에는 날짜, 요약, 변경 파일, 검증, 후속 주의점을 남깁니다.

## 템플릿

```md
## YYYY-MM-DD - 짧은 제목

요약:
- 무엇을 왜 바꿨는지 1-3줄로 작성

변경 파일:
- `path/to/file`: 변경 내용

검증:
- `command`: 결과

후속 주의:
- 남은 위험, 다음 작업자가 확인할 점
```

## 2026-06-21 - All delete archive 중 sidebar만 닫히는 버그 수정

요약:
- sidebar가 열린 상태에서 `d` -> `All` -> `y` 실행 시, archive 중 sidebar pane이 먼저 닫혀 `kill-server`까지 진행되지 않던 문제를 수정했습니다.
- All delete도 current session archive-delete와 동일하게 tmux `run-shell -b` 독립 프로세스가 archive 후 server 종료를 처리하게 했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: All delete archive/no-archive를 background command로 분리
- `HISTORY.md`, `CONVERSATION.md`: bugfix 기록

검증:
- isolated tmux 서버에서 sidebar + split work pane 상태로 `--delete-all-sessions-after-archive true` 실행 후 모든 session archive 생성 및 server 종료 확인
- isolated tmux 서버에서 `--delete-all-sessions-after-archive false` 실행 후 server 종료 확인

후속 주의:
- archive path는 여전히 live sidebar pane을 닫을 수 있으므로, 다음 리팩토링에서는 archive를 read-only snapshot 방식으로 바꾸는 것이 우선입니다.

## 2026-06-21 - current session delete archive 중 sidebar만 닫히는 버그 수정

요약:
- sidebar가 열린 current session에서 split 후 `d` -> `y` 삭제 시, archive 과정에서 sidebar pane이 먼저 닫혀 session kill까지 진행되지 않던 문제를 수정했습니다.
- current session을 history 저장하며 삭제할 때는 tmux `run-shell -b` 독립 프로세스가 archive와 session/server kill을 이어서 처리하게 했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: current session archive-delete를 background command로 분리
- `HISTORY.md`, `CONVERSATION.md`: bugfix 기록

검증:
- isolated tmux 서버에서 sidebar + split work pane 상태의 current session을 archive-delete 후 fallback session만 남는 것 확인
- isolated tmux 서버에서 마지막 session을 archive-delete 후 tmux server가 종료되는 것 확인

후속 주의:
- current session 삭제의 `Enter` no-history 경로는 기존 직접 kill 흐름을 유지합니다.

## 2026-06-20 - sidebar history restore layout 복원 수정

요약:
- history restore가 저장된 tmux layout의 예전 pane id/checksum을 그대로 재사용해 vertical-only 또는 mixed layout이 잘못 복원되던 문제를 수정했습니다.
- restore 시 새로 생성된 pane id로 layout leaf id를 치환하고 checksum을 다시 계산해 `select-layout`가 실제 저장 배치를 적용하게 했습니다.
- restore 후 sidebar를 열 때 확정된 work layout option을 덮어쓰지 않도록 restore 전용 preserve 경로를 추가했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: archive layout 선택, restored layout id/checksum 재작성, restore 전용 sidebar preserve 처리
- `README.md`: history restore layout 설명 갱신
- `HISTORY.md`, `CONVERSATION.md`: bugfix 기록

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `git diff --check`: 통과
- isolated tmux 서버에서 vertical-only, horizontal-only, mixed 3-pane session을 sidebar 포함 archive/restore 후 방향과 크기 구조가 원본과 일치함을 확인

후속 주의:
- layout 복원은 tmux `window_layout` 기반이므로 실행 중이던 process 자체는 여전히 복원하지 않습니다.

## 2026-06-20 - sidebar history restore prompt 잔상 수정

요약:
- sidebar history에서 session을 복원할 때 새 work pane 상단에 zsh 기본 `%` prompt가 남는 화면 잔상을 제거했습니다.
- 복원 완료 후 sidebar pane은 제외하고 restored session의 work pane들에만 `C-l`과 `clear-history`를 적용해 초기 prompt artifact를 지우도록 했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: restored work pane clear helper 추가 및 restore 완료 후 호출
- `HISTORY.md`, `CONVERSATION.md`: bugfix 기록

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `git diff --check`: 통과
- isolated tmux 서버에서 3-pane session archive/restore 후 각 restored pane의 visible capture가 `%` 없이 `$`만 표시됨을 확인
- restored pane scrollback 근처 capture에서도 `%` 잔상이 제거됨을 확인

후속 주의:
- 복원은 여전히 실행 중이던 process 자체를 되살리지 않고, 새 shell pane과 cwd/layout/history metadata를 재생성합니다.

## 2026-06-20 - sidebar split 경로 표시 회귀 수정

요약:
- sidebar가 열린 상태에서 split wrapper를 실행할 때 새 pane과 sidebar가 잘못된 current path를 공유하지 않도록 target pane의 현재 경로를 직접 읽어 사용하게 했습니다.
- split 중 sidebar를 죽였다가 다시 여는 흐름을 제거하고, 현재 work pane을 tmux 기본 split 방식으로 나누게 했습니다.
- tmux 기본 `%`/`"` split key가 sidebar pane을 직접 split하지 않도록 기존 `|`/`_`와 같은 launcher wrapper로 연결했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: target pane current path helper 추가, split 경로를 sidebar kill/reopen 없이 tmux 기본 split으로 단순화
- `dotfiles/tmux.conf`: `%`/`"` split binding을 sidebar-aware wrapper로 변경
- `HISTORY.md`, `CONVERSATION.md`: bugfix 기록

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `zsh -n dotfiles/tmux.zshrc`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- isolated tmux 서버에서 sidebar open, active pane focus, vertical split 실행 후 새 pane에 `%` 없이 `$` prompt만 표시 확인
- isolated tmux 서버에서 sidebar focus, vertical split 실행 후 새 pane에 `%` 없이 `$` prompt만 표시 확인

후속 주의:
- tmux 기본 split/resize를 직접 실행하는 경우까지 완전히 추적하는 구조는 아닙니다. sidebar 안에서는 launcher wrapper를 쓰는 전제를 유지합니다.

## 2026-06-20 - tmux sidebar layout/delete refactor

요약:
- sidebar를 열기 전 window-local work layout을 저장하고, sidebar를 닫을 때 해당 layout을 복구해 반복 toggle 후 pane 비율이 누적 변형되지 않도록 했습니다.
- sidebar가 열린 상태에서 launcher split wrapper를 쓰면 sidebar를 잠시 제거하고 split 후 새 work layout을 저장한 뒤 sidebar를 다시 여는 흐름으로 정리했습니다.
- current session 삭제를 허용하고, 다른 session이 있으면 전환 후 삭제, 없으면 tmux server 종료로 처리합니다.

변경 파일:
- `scripts/tmux-session-launcher`: work layout 저장/복구, sidebar-free archive layout, current session delete fallback
- `README.md`: `Esc`/delete/layout/restore 설명 갱신
- `AGENTS.md`: 현재 sidebar refactor 상태와 남은 제한 기록
- `HISTORY.md`, `CONVERSATION.md`: 변경 의도와 검증 기록

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- isolated tmux 서버에서 sidebar open/close 2회 후 pane 폭 원복 확인
- isolated tmux 서버에서 sidebar open 상태의 split wrapper 실행 후 sidebar-free work layout 저장 및 close 시 3-pane layout 원복 확인

후속 주의:
- sidebar가 열린 상태에서 tmux 기본 split/resize를 직접 실행해 work 영역을 바꾸는 경우는 layout 저장 지점을 우회할 수 있습니다. sidebar 안에서는 `Ctrl+a |`/`Ctrl+a _` wrapper를 사용해야 합니다.
- shell history는 여전히 공용 tmux zsh history 기반입니다. 이미 섞인 과거 history를 pane/window별로 정확히 재분리하는 것은 이번 범위 밖입니다.

## 2026-06-20 - tmux sidebar 다음 refactor 이슈 기록

요약:
- sidebar toggle/restore/delete 흐름에서 발견된 layout 보존 문제와 session history 복원 한계를 다음 refactoring 대상으로 기록했습니다.
- 현재 동작 코드는 변경하지 않고, 다음 작업자가 우선순위를 잃지 않도록 known issue와 설계 판단만 남겼습니다.

변경 파일:
- `HISTORY.md`: 다음 refactor에서 수정할 sidebar layout/history/delete 이슈 기록
- `CONVERSATION.md`: 사용자 의도, 해석, history 개선 난이도 판단 기록

검증:
- `git diff --check`: 통과

후속 주의:
- sidebar를 반복 toggle할 때 active 영역 pane 폭 비율이 누적 변형되는 문제를 수정해야 합니다.
- session restore 시 active 영역의 pane 크기와 배치가 원본과 동일하게 복원되도록 layout 저장/재생성 방식을 다시 설계해야 합니다.
- restore 결과에 sidebar 모양의 split 또는 sidebar-adjacent vertical split이 섞이는 문제를 점검해야 합니다.
- delete archive 저장 시 sidebar pane/window 정보가 완전히 제외되는지 재검증해야 합니다.
- 현재 shell history는 tmux 공용 `HISTFILE` 기반이라 pane/window별 history가 통합될 수 있습니다. 앞으로의 기록을 분리하는 것은 per-pane/per-window `HISTFILE` 설계로 비교적 명확하지만, 이미 섞인 global history를 과거 pane별로 정확히 되돌리는 것은 쉽지 않습니다.
- active/current session도 delete 대상으로 허용하고, 삭제 시 다른 inactive session으로 전환하거나 남은 session이 없으면 종료하도록 delete flow를 바꿔야 합니다.

## 2026-06-20 - tmux sidebar delete/history 동작 보강

요약:
- `Esc`가 sidebar 자체를 닫지 않도록 수정하고, history view에서는 `Esc`가 history 창만 닫도록 바꿨습니다.
- session 삭제는 `y`일 때만 history를 저장하고, `Enter`는 history 없이 삭제, `Esc`는 삭제 취소로 정리했습니다.
- archive 저장 시 sidebar pane을 제외하고, shell history를 함께 저장/복원하도록 보강했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: prompt ESC 처리, delete 정책 변경, sidebar pane 제외 archive, 동일 이름 restore skip, shell history archive/append
- `dotfiles/tmux.zshrc`: tmux 전용 zsh history 저장 설정 추가
- `README.md`: delete/history/restore semantics 갱신
- `HISTORY.md`, `CONVERSATION.md`: 변경 의도와 결과 기록

검증:
- `bash -n install.sh`: 통과
- `bash -n scripts/tmux-session-launcher`: 통과
- `zsh -n dotfiles/tmux.zshrc`: 통과
- `perl -c dotfiles/urxvt/ext/resize-font`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- isolated tmux 서버에서 `Esc` sidebar 유지, `Enter` 삭제 no-history, `y` 삭제 archive, sidebar pane 제외 archive, 원래 이름 restore, 동일 이름 중복 restore skip, history view `Esc` close, `All` no-history/history 분기 확인

후속 주의:
- shell history는 새 tmux zsh 설정 이후 쌓이는 history file 기준으로 보관합니다. 이미 실행 중이던 process 자체는 복원하지 않습니다.

## 2026-06-20 - tmux sidebar TUI 안정화와 history restore 추가

요약:
- sidebar가 focus 이동 후 active work pane 크기를 기준으로 다시 그려지던 문제를 수정했습니다.
- age column 오른쪽에 한 칸 여백을 두고, footer는 항상 sidebar pane 하단 기준으로 그리도록 고정했습니다.
- session 삭제 시 복원용 history metadata를 저장하고, `h` view에서 복원/영구삭제할 수 있게 했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: self pane 기준 렌더링, mouse-select, delete archive, history view/restore 추가
- `dotfiles/tmux.conf`: MouseDown1Pane wrapper 추가
- `README.md`: mouse, All delete, history restore 설명 추가
- `HISTORY.md`, `CONVERSATION.md`: TUI 안정화와 history 정책 기록

검증:
- `bash -n install.sh`: 통과
- `bash -n scripts/tmux-session-launcher`: 통과
- `perl -c dotfiles/urxvt/ext/resize-font`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- isolated tmux 서버에서 focus 이동 후 sidebar UI 유지, delete archive, history view, restore, history 삭제, `All` archive 후 server 종료 확인
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d -s loadtest`: 통과
- `tmux -L codex-dotfiles-test list-keys -T root MouseDown1Pane`: mouse wrapper 등록 확인

후속 주의:
- history restore는 window/pane layout과 cwd metadata 기반으로 새 session을 재생성합니다. 삭제 당시 실행 중이던 process 자체는 복원하지 않습니다.

## 2026-06-20 - tmux sidebar TUI 전환 계획 실행

요약:
- sidebar session launcher에서 `fzf` 런타임 의존성을 제거하고, bash/tmux 기반 TUI loop로 전환했습니다.
- UI는 좁은 sidebar 폭에 맞춰 선택/current 표시, session name, 생성 후 경과 시간만 보여주도록 줄였습니다.
- busy/idle 상태는 추후 실시간 status cell 확장을 위해 snapshot 구조에만 남기고, 현재 UI에는 표시하지 않습니다.

변경 파일:
- `scripts/tmux-session-launcher`: 자체 TUI render/input loop, partial age update, session action prompt 추가
- `install.toml`: `fzf` commands/packages 제거
- `README.md`: fzf 설명 제거, TUI 키와 표시 항목 설명으로 갱신
- `HISTORY.md`, `CONVERSATION.md`: TUI refactor 의도와 결정 기록

검증:
- `bash -n install.sh`: 통과
- `bash -n scripts/tmux-session-launcher`: 통과
- `perl -c dotfiles/urxvt/ext/resize-font`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- isolated tmux 서버에서 sidebar open, age 표시, session 생성/rename/delete/switch, toggle close 확인

후속 주의:
- v1 TUI는 fuzzy search, mouse/double-click, color/status 표시를 포함하지 않습니다.

## 2026-06-20 - tmux sidebar fzf 구버전 호환성 수정

요약:
- 새 PC에서 `Ctrl+a s` sidebar가 나타났다가 바로 사라지는 문제를 수정했습니다.
- 원인은 distro packaged `fzf 0.29`가 `load:pos(...)` binding을 지원하지 않아 `fzf`가 시작 실패하고 launcher pane이 종료되는 경로였습니다.
- 비필수 `fzf` 옵션 지원 여부를 실행 시 확인하고, 미지원 환경에서는 해당 UI 보조 기능만 비활성화하도록 바꿨습니다.

변경 파일:
- `scripts/tmux-session-launcher`: 비필수 `fzf` 옵션 capability check 추가, startup error 표시 보강
- `README.md`: 오래된 `fzf`에서는 선택 row 위치 복원만 비활성화될 수 있음을 명시
- `HISTORY.md`, `CONVERSATION.md`: 새 PC sidebar 즉시 종료 원인과 호환성 결정 기록

검증:
- `printf 'a\n' | fzf --filter=a --bind='load:pos(1)'`: `fzf 0.29`에서 `unsupported key: load` 재현
- `bash -n scripts/tmux-session-launcher`: 통과

후속 주의:
- 최신 `fzf`에서는 기존 UI 보조 기능이 유지되고, 구버전에서는 sidebar 표시 안정성을 우선합니다.

## 2026-06-20 - v0.2 sidebar follow-up

요약:
- origin/master의 v0.1 버전 설치 지원 커밋 위로 현재 sidebar 변경을 다시 얹었습니다.
- 현재 작업은 v0.2로 기록하되, v0.2 git tag는 아직 만들지 않습니다.
- sidebar TUI 분리는 다음 버전 refactoring 항목으로 남깁니다.

변경 파일:
- `CONVERSATION.md`, `HISTORY.md`: v0.2 작업 노트와 기존 sidebar 기록 병합

검증:
- `git rebase --autostash origin/master`: 완료, autostash 충돌만 남김

후속 주의:
- v0.2 tag는 다음 릴리스에서 생성한다.
- sidebar TUI split은 이번 릴리스 범위 밖으로 둔다.

## 2026-06-19 - v0.1 버전 설치 준비

요약:
- dotfiles 설치 흐름을 `v0.1`부터 tag 기반 버전으로 관리할 수 있게 했습니다.
- 인자 없는 기본 설치는 master 최신 기준으로 두고, `install.sh --v v0.1`, `install.sh --version v0.1`, 또는 `DOTFILES_VERSION=v0.1`로 특정 버전을 설치할 수 있게 했습니다.

변경 파일:
- `install.sh`: 기본 master 설치, `--v`/`--version` 인자 파싱, tag/branch raw URL 계산, 설치 버전 기록 추가
- `README.md`: 버전 설치 사용법과 배포 시 tag 생성 원칙 추가
- `doc/architecture.md`: version model 추가

검증:
- `bash -n install.sh`: 통과
- `bash install.sh --help`: 통과
- `printf '\n' | STATE_DIR=/tmp/dotfiles-version-default REPO_RAW_URL=file:///home/al-hub/workspace/dotfiles-tmp bash install.sh`: 통과, version `master` 확인
- `printf '\n' | STATE_DIR=/tmp/dotfiles-version-v01 REPO_RAW_URL=file:///home/al-hub/workspace/dotfiles-tmp bash install.sh --v v0.1`: 통과, version `v0.1` 확인
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test kill-server`: 통과

후속 주의:
- `v0.1`는 기준 태그로 유지하고, 이후 릴리스 버전은 별도 항목으로 관리합니다.

## 2026-06-20 - tmux sidebar blank 회귀 수정

요약:
- sidebar pane은 생성되지만 내용이 표시되지 않는 회귀를 수정했습니다.
- 원인은 fzf `--listen` + background `curl reload(...)` 기반 1초 갱신 경로로 판단해 해당 live reload binding을 제거했습니다.
- double-click binding 제거는 유지하고, session 목록 자체는 다시 안정적으로 표시되도록 복구했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: fzf `--listen`, `--track`, background reload binding 제거
- `README.md`: elapsed time의 1초 자동 갱신 표현 제거
- `HISTORY.md`, `CONVERSATION.md`: blank 회귀와 복구 기록

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `git diff --check`: 통과
- 테스트 tmux 서버에서 local launcher를 sidebar pane으로 실행 후 `capture-pane`: `* source`, header, `Commands>` prompt 표시 확인

후속 주의:
- fzf 기반으로 row-level partial update는 어렵습니다. 1초 단위 live update가 꼭 필요하면 fzf reload 방식 재시도보다 전용 sidebar TUI로 분리하는 편이 안전합니다.

## 2026-06-20 - tmux sidebar elapsed 표시와 live reload 추가

요약:
- mouse double-click session 선택 바인딩을 제거했습니다.
- sidebar 목록에 running elapsed column을 추가하고 `DAY:HH:MM:SS` 형식으로 표시합니다.
- fzf listen/reload를 사용해 sidebar 목록을 1초마다 갱신하려 했으나, 이후 blank 회귀 때문에 제거했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: fzf double-click binding 제거, elapsed time tracking, 1초 reload, busy start option 추가
- `README.md`: double-click 설명 제거, elapsed/live update 설명 추가
- `HISTORY.md`, `CONVERSATION.md`: 작업 맥락 기록

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `printf 'a\nb\n' | fzf --ansi --sync --track --listen=0 --bind='load:pos(2)' ... --filter=''`: fzf listen/reload option 수용 확인
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d -s source`: 통과
- 테스트 서버에서 `tmux run-shell '... --list-sessions > /tmp/...'`: 선택 표시, session name, elapsed column 출력 확인
- 테스트 서버에서 `busy` session에 `yes >/dev/null` 실행 후 `--list-sessions`: session name ANSI red, elapsed `0:00:00:00` 출력 확인

후속 주의:
- fzf는 row 단위 partial update API를 제공하지 않으므로 내부적으로는 `reload(...)`로 list를 갱신합니다. `--track`으로 선택 위치를 유지해 전체 재시작보다 덜 거칠게 보이도록 했습니다.
- red/elapsed 표시는 `session_activity`와 `pane_current_command` 기반 heuristic입니다.

## 2026-06-20 - tmux sidebar 폭 유지와 session activity 표시

요약:
- 사용자가 조정한 sidebar 폭을 저장해 session 이동 후 target sidebar에도 같은 폭을 적용합니다.
- sidebar 목록을 선택 표시와 session name 두 컬럼으로 줄였습니다.
- 최근 activity가 있고 foreground command가 shell이 아닌 session은 red로 표시하도록 했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: sidebar width 기억/복원, compact list, ANSI red busy 표시 추가
- `README.md`: sidebar 폭 유지, red activity 표시 설명 추가
- `HISTORY.md`, `CONVERSATION.md`: 작업 맥락 기록

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `perl -c dotfiles/urxvt/ext/resize-font`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `printf 'a\nb\n' | fzf --ansi --sync --bind='load:pos(2)' --filter=''`: fzf option 수용 확인
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d -s source`: 통과
- `tmux -L codex-dotfiles-test list-keys -T prefix s`: `--open-sidebar` 바인딩 확인
- 테스트 서버에서 local launcher `--open-sidebar`: width 35 sidebar 생성 확인
- 테스트 서버에서 sidebar를 42 columns로 resize 후 toggle close: `@dotfiles-session-sidebar-width=42` 저장 확인
- 테스트 서버에서 다시 `--open-sidebar`: width 42 sidebar 재생성 확인

후속 주의:
- red 표시는 tmux가 제공하는 `session_activity`와 `pane_current_command` 기반 heuristic입니다. 프로그램이 조용히 오래 실행되거나 입력 대기 중인 상태를 완벽하게 구분하지는 않습니다.

## 2026-06-20 - tmux sidebar toggle과 list 갱신 보강

요약:
- tmux 시작 시 sidebar가 자동으로 열리지 않도록 session-changed hook을 제거했습니다.
- `Ctrl+a s`를 sidebar on/off toggle로 바꾸고, session 전환 시 선택 row와 attached/detached 표시가 새로 반영되도록 보강했습니다.
- sidebar session list의 컬럼 표시를 좁게 줄였습니다.

변경 파일:
- `dotfiles/tmux.conf`: `client-session-changed` hook 제거, `Ctrl+a s`는 toggle wrapper 유지
- `scripts/tmux-session-launcher`: sidebar toggle, target sidebar respawn refresh, current session 상태 갱신, fzf 시작 위치 복원, compact list 출력 추가
- `README.md`: sidebar toggle과 시작 시 비표시 동작 설명 추가

검증:
- `bash -n install.sh`: 통과
- `bash -n scripts/tmux-session-launcher`: 통과
- `perl -c dotfiles/urxvt/ext/resize-font`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- 시작 직후 `tmux -L codex-dotfiles-test list-panes`: sidebar 없이 기본 pane 1개 확인
- `tmux -L codex-dotfiles-test list-keys -T prefix s`: `--open-sidebar` 바인딩 확인
- `tmux -L codex-dotfiles-test show-hooks -g client-session-changed`: hook 제거 확인
- local launcher `--open-sidebar` 1회 실행: 왼쪽 sidebar 생성 확인
- local launcher `--open-sidebar` 2회 실행: sidebar 제거 확인
- `printf 'a\nb\n' | fzf --sync --bind='load:pos(2)' --filter=''`: fzf `load:pos(...)` 구문 수용 확인

후속 주의:
- 실제 interactive fzf에서 선택 row 복원과 attached/detached 즉시 갱신 체감은 사용자가 tmux 안에서 확인해야 합니다.

## 2026-06-19 - tmux session launcher를 고정 sidebar로 변경

요약:
- `Ctrl+a s` session launcher를 tmux popup 대신 현재 window의 제일 왼쪽 고정 sidebar pane으로 열도록 변경했습니다.
- 상하/좌우 split 상태에서도 sidebar는 전체 높이를 차지하는 왼쪽 pane 하나로 유지하고, 중복 생성을 막습니다.
- sidebar에 포커스가 있을 때 split 키를 누르면 sidebar가 아니라 오른쪽 작업 영역을 나누도록 했습니다.

변경 파일:
- `dotfiles/tmux.conf`: `Ctrl+a s`, `Ctrl+a |`, `Ctrl+a _`, session changed hook을 launcher wrapper로 연결
- `scripts/tmux-session-launcher`: sidebar 탐지/생성, 중복 방지, target session sidebar 보장, 작업 영역 split wrapper 추가
- `README.md`: session launcher 설명을 popup에서 고정 sidebar 동작으로 갱신

검증:
- `bash -n install.sh`: 통과
- `bash -n scripts/tmux-session-launcher`: 통과
- `perl -c dotfiles/urxvt/ext/resize-font`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test list-keys -T prefix s`: `--open-sidebar` 바인딩 확인
- `tmux -L codex-dotfiles-test list-keys -T prefix \|`: `--split-horizontal` 바인딩 확인
- `tmux -L codex-dotfiles-test list-keys -T prefix _`: `--split-vertical` 바인딩 확인
- `tmux -L codex-dotfiles-test show-hooks -g client-session-changed`: sidebar 보장 hook 확인
- 테스트 서버에서 local launcher `--open-sidebar` 2회 실행: sidebar 1개만 유지 확인
- 테스트 서버에서 sidebar focus 후 `--split-horizontal`, `--split-vertical`: 오른쪽 작업 영역만 split되는 layout 확인
- `tmux split-window -t =codex-target-test: -h -f -b -l 35 ...`: target session sidebar 생성에 쓰는 target 형식 확인

후속 주의:
- tmux pane은 session/window에 속하므로 서버 전체의 단일 물리 pane은 불가능합니다. 대신 이동한 target session/window마다 sidebar를 자동 보장합니다.
- 실제 tmux에서 왼쪽 pane 폭 35 columns가 충분한지 확인하고 조정할 수 있습니다.

## 2026-06-14 - init 명령을 undo/clear-state로 분리

요약:
- `init`이라는 넓은 이름 대신, 실제 동작에 맞는 `undo`와 `clear-state`로 설치 초기화 의미를 분리했습니다.
- `undo`는 manifest 기준으로 파일을 복원/삭제하고 상태를 정리하며, `clear-state`는 파일은 건드리지 않고 manifest 설치 추적 기록만 삭제합니다.

변경 파일:
- `install.sh`: `init` 처리 분리를 `undo` / `clear-state`로 재정의
- `README.md`: 사용자용 설치 방식 설명 갱신

검증:
- `bash -n install.sh`: 통과
- `git diff --check`: 통과
- 임시 `HOME`, 기존 manifest 구성, 입력 `clear-state` + `y`: manifest 삭제 및 cached install list 유지 확인
- 임시 `HOME`, 기존 manifest/backup 구성, 입력 `undo` + `y`: 백업 복원 및 manifest 삭제 확인

후속 주의:
- 기존 `init`은 호환용 별칭으로 유지했기 때문에, 다음 단계에서 완전히 제거할지 결정할 수 있습니다.

## 2026-06-14 - opencode 재설치 판정과 installer Enter 동작 수정

요약:
- `opencode` CLI가 `~/.opencode/bin/opencode` 같은 기본 설치 경로에 이미 있어도 재설치로 들어가던 판정을 완화했습니다.
- installer 첫 화면에서 Enter는 종료로 바꾸고, enabled 전체 설치는 `all` 명령으로만 수행하도록 정리했습니다.

변경 파일:
- `install.sh`: `opencode` CLI 존재 확인 보강, Enter 기본 동작을 종료로 변경
- `README.md`: installer 입력 안내와 `opencode` 설치 판정 설명 갱신
- `doc/opencode.md`: CLI 자동 설치 조건 설명 갱신
- `doc/architecture.md`: opencode 모듈 판정 규칙을 실제 동작과 맞춤

검증:
- 아직 실행 전

후속 주의:
- `opencode`를 PATH 밖 경로에 설치한 환경에서도 재설치가 반복되지 않는지 확인해야 합니다.

## 2026-06-14 - 설치 구조 문서 보강

요약:
- tmux와 opencode의 설치 원칙을 `doc/architecture.md`로 분리해 모듈 추가 기준을 한곳에 정리했습니다.
- README와 opencode 문서에서 구조/확장 원칙을 서로 연결해 문서 간 역할을 분리했습니다.

변경 파일:
- `doc/architecture.md`: 설치 모델, 모듈 형태, 확장 규칙 정리
- `README.md`: 구조 문서 링크 추가 및 모듈 추가 원칙 보강
- `doc/opencode.md`: architecture 문서 참조 및 CLI lifecycle 설명 추가
- `HISTORY.md`, `CONVERSATION.md`: 작업 맥락 기록

검증:
- 문서 변경만 적용

후속 주의:
- 새 모듈 추가 시 먼저 architecture 문서 기준으로 file / dependency / hook / external CLI를 분류하면 된다.

## 2026-06-14 - 설치 체인 중복과 순환 의존성 방지

요약:
- `install.sh`에 현재 설치 체인 추적을 넣어 같은 항목이 같은 실행 안에서 반복 설치되지 않도록 했습니다.
- dependency 순환이 생기면 탐지하고 중단하도록 보강했습니다.

변경 파일:
- `install.sh`: install stack / done tracking 추가, 중복 설치와 순환 의존성 방지
- `HISTORY.md`, `CONVERSATION.md`: 구조 보강 기록

검증:
- `bash -n install.sh`: 통과
- `git diff --check`: 통과

후속 주의:
- 앞으로 새 모듈이 dependency를 추가할 때, 순환 경로를 더 쉽게 막을 수 있습니다.

## 2026-06-14 - opencode 단일 선택 자동 설치로 단순화

요약:
- `opencode`를 한 번 선택하면 config를 갱신하고 CLI가 없을 때만 자동 설치하도록 단순화했습니다.
- 사용자가 모드를 따로 고르지 않아도 되도록 `config / cli / both` 분기를 제거했습니다.

변경 파일:
- `install.sh`: opencode 전용 선택 모드 제거, CLI 자동 설치 조건 추가
- `README.md`, `doc/opencode.md`: 단일 선택 자동 동작 설명 갱신
- `HISTORY.md`, `CONVERSATION.md`: 작업 맥락 기록

검증:
- `bash -n install.sh`: 통과
- `git diff --check`: 통과

후속 주의:
- CLI가 이미 설치되어 있으면 config만 갱신합니다.

## 2026-06-14 - opencode 기본 설치 모드 config only로 조정

요약:
- `opencode` 설치 시 기본 선택을 `config only`로 바꿨습니다.
- CLI 설치는 여전히 선택 가능하지만, 엔터 기본값은 설정 파일만 설치하는 쪽이 안전하다고 판단했습니다.

변경 파일:
- `install.sh`: opencode 설치 모드 기본값을 config only로 변경
- `README.md`, `doc/opencode.md`: 기본 설치 모드 설명 갱신
- `HISTORY.md`, `CONVERSATION.md`: 작업 맥락 기록

검증:
- `bash -n install.sh`: 통과
- `git diff --check`: 통과

후속 주의:
- CLI를 함께 설치하려면 설치 과정에서 명시적으로 `both`를 선택해야 합니다.

## 2026-06-14 - opencode CLI 공식 설치 스크립트 연동

요약:
- opencode CLI를 공식 설치 스크립트 `curl -fsSL https://opencode.ai/install | bash`로 설치하도록 방향을 확정했습니다.
- `install.sh`에서 `opencode` 항목을 선택하면 config only / cli only / both 중 하나를 고를 수 있게 했습니다.

변경 파일:
- `install.sh`: opencode 전용 설치 모드 프롬프트와 CLI 설치 함수 추가
- `README.md`, `doc/opencode.md`: 선택형 설치와 공식 CLI 설치 경로 반영
- `HISTORY.md`, `CONVERSATION.md`: 작업 맥락 기록

검증:
- 문서/설치 스크립트 변경만 적용

후속 주의:
- CLI 설치는 네트워크를 사용하므로 오프라인 환경에서는 실패할 수 있습니다.

## 2026-06-14 - opencode personal 설치 항목 추가

요약:
- opencode personal seed config를 설치 가능한 항목으로 `install.toml`에 연결했습니다.
- 현재는 `~/.config/opencode/opencode.jsonc`에만 설치하며, work profile과 실행 래퍼는 아직 추가하지 않았습니다.

변경 파일:
- `install.toml`: `opencode` visible 설치 항목 추가
- `README.md`: opencode가 설치 목록에 포함된다는 점과 대상 경로 반영
- `doc/opencode.md`: 현재 상태 설명 갱신
- `HISTORY.md`, `CONVERSATION.md`: 작업 맥락 기록

검증:
- 문서/매니페스트 변경만 적용

후속 주의:
- opencode CLI binary 설치는 아직 이 저장소가 책임지지 않습니다.

## 2026-06-14 - opencode seed config 주석 정리

요약:
- opencode personal seed config의 주석을 정리해 현재 상태와 향후 확장 지점을 더 분명하게 만들었습니다.
- 기능은 바꾸지 않고, personal-only 시작과 work profile 확장 가능성을 강조했습니다.

변경 파일:
- `dotfiles/opencode.jsonc`: personal seed config 주석 정리, 확장 지점 명시
- `HISTORY.md`, `CONVERSATION.md`: 작업 맥락 기록

검증:
- 문서/주석 정리만 적용

후속 주의:
- install.toml 연동이나 실행 래퍼는 아직 추가하지 않았습니다.

## 2026-06-14 - opencode 문서 분리

요약:
- opencode 관련 내용을 README 본문에서 분리하고 별도 문서로 정리하는 방향을 반영했습니다.
- 현재 상태는 personal-only seed config 중심이며, 향후 work profile과 실행 래퍼를 붙일 수 있도록 구조만 남겼습니다.

변경 파일:
- `doc/opencode.md`: opencode 현재 상태, 설계 방향, 확장 지점 정리
- `README.md`: opencode 문서 링크 추가, 현재 구조에 파일 반영
- `HISTORY.md`, `CONVERSATION.md`: 작업 맥락 기록

검증:
- 문서 변경만 적용

후속 주의:
- 실제 설치기 연결은 아직 하지 않았으므로, opencode의 실행/설치 동작은 다음 작업에서 결정해야 합니다.

## 2026-05-20 - URxvt Ctrl+wheel event mask 추가

요약:
- `Ctrl+마우스 휠`이 동작하지 않는 문제를 점검해 URxvt extension이 button press event mask를 요청하지 않았던 경로를 보강했습니다.
- `resize-font` extension 시작 시 `vt_emask_add(urxvt::ButtonPressMask())`를 호출해 wheel/click hook이 호출되도록 했습니다.

변경 파일:
- `dotfiles/urxvt/ext/resize-font`: button press event mask 등록 추가, Control modifier 판정은 URxvt 상수 사용
- `HISTORY.md`, `CONVERSATION.md`: 문제 원인과 후속 확인 기록

검증:
- `perl -c dotfiles/urxvt/ext/resize-font`: 통과
- `bash -n install.sh`: 통과
- `bash -n scripts/tmux-session-launcher`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test kill-server`: 통과

후속 주의:
- 설치된 환경에서는 `install.sh` 재실행 후 URxvt를 새로 열어야 extension 변경이 반영됩니다.

## 2026-05-20 - URxvt Ctrl+마우스 font resize 설치 포함

요약:
- tmux 설치 시 URxvt font resize 설정도 hidden dependency로 함께 설치되도록 확장했습니다.
- URxvt resize-font extension을 repo에 포함하고, `Ctrl+WheelUp/Down`은 확대/축소, `Ctrl+WheelClick`은 기본 크기 복원으로 처리합니다.
- Xresources 설치 후 X 세션에서는 `xrdb -merge`를 자동으로 시도하고, X 세션이 아니면 수동 적용 안내를 출력합니다.

변경 파일:
- `install.toml`: `tmux` dependency에 `urxvt-resize-font`, `tmux-xresources` 추가 및 Xresources 항목 hidden dependency화
- `install.sh`: Xresources load hook과 URxvt extension 권한 처리 추가
- `dotfiles/Xresources`: URxvt resource 키 정규화, `C-equal` 오타 수정
- `dotfiles/urxvt/ext/resize-font`: URxvt font resize extension 추가
- `README.md`, `AGENTS.md`, `HISTORY.md`, `CONVERSATION.md`: 설치 모델과 사용법 기록

검증:
- `bash -n install.sh`: 통과
- `bash -n scripts/tmux-session-launcher`: 통과
- `perl -c dotfiles/urxvt/ext/resize-font`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- 임시 `HOME`, `REPO_RAW_URL=file://...`, 입력 `q`: 설치 목록에 `tmux`, `vim`, `shell`만 표시되고 hidden 항목은 숨겨짐
- 임시 `HOME`, fake `urxvt`, `REPO_RAW_URL=file://...`, 입력 `Enter`: `tmux`, `tmux-session-launcher`, `tmux-zshrc`, `urxvt-resize-font`, `tmux-xresources`가 함께 설치되고 manifest에 기록됨
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test kill-server`: 통과

후속 주의:
- 실제 `Ctrl+마우스` 동작은 GUI URxvt 세션에서 수동 확인이 필요합니다.
- D2Coding 폰트 설치는 자동화하지 않으므로 없는 환경에서는 URxvt가 fallback font를 사용할 수 있습니다.

## 2026-05-13 - tmux 하위 설치 항목 hidden dependency 전환

요약:
- 설치 화면에서 `tmux-session-launcher`, `tmux-zshrc`가 독립 enabled 항목처럼 보여 사용자 관점에서 혼란스러운 문제를 정리했습니다.
- `tmux`에 `depends = ["tmux-session-launcher", "tmux-zshrc"]`를 추가하고, 하위 항목은 `hidden = true`, `enabled = false`로 변경했습니다.
- 설치 목록과 번호 선택은 hidden 항목을 건너뛰고, 실제 설치는 dependency를 따라 하위 파일까지 함께 설치합니다.

변경 파일:
- `install.toml`: `hidden`, `depends` 메타데이터 추가 및 tmux 하위 항목 hidden dependency화
- `install.sh`: TOML parser, 설치 목록, 번호 선택, enabled 설치에 hidden/dependency 처리 추가
- `README.md`, `AGENTS.md`, `HISTORY.md`, `CONVERSATION.md`: 설치 모델 설명 갱신

검증:
- `bash -n install.sh`: 통과
- `bash -n scripts/tmux-session-launcher`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- 임시 `HOME`, `REPO_RAW_URL=file://...`, 입력 `q`: 설치 목록에 `tmux`, `vim`, `shell`, `tmux-xresources`만 표시되고 hidden 항목은 숨겨짐
- 임시 `HOME`, `REPO_RAW_URL=file://...`, 입력 `Enter`: `tmux` 설치 시 `tmux-session-launcher`, `tmux-zshrc`가 함께 설치되고 manifest에 기록됨
- 임시 `HOME`, `REPO_RAW_URL=file://...`, 입력 `2`: hidden 항목을 건너뛴 번호 매핑으로 `vim`이 설치됨
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test kill-server`: 통과

후속 주의:
- hidden 항목은 사용자 목록에서 보이지 않지만 `install_by_name` dependency 경로로는 설치됩니다.

## 2026-05-13 - tmux 전용 zsh init으로 git completion 복구

요약:
- tmux 안에서 git 자동완성이 되지 않는 원인은 `default-command`가 `/bin/zsh -f`를 실행해 `~/.zshrc`와 `compinit`을 건너뛰는 것이었습니다.
- 단순히 `-f`를 제거하면 사용자 기본 prompt가 로드되어 경로 prompt가 다시 나타날 수 있으므로, tmux 전용 `ZDOTDIR`와 `.zshrc`를 추가했습니다.
- tmux 전용 zsh init은 짧은 `$ ` prompt를 유지하면서 `compinit -u`만 로드합니다.

변경 파일:
- `dotfiles/tmux.conf`: zsh를 `ZDOTDIR="$HOME/.cache/dotfiles"`로 실행하도록 변경
- `dotfiles/tmux.zshrc`: tmux 전용 prompt와 `compinit -u` 추가
- `install.toml`: `tmux-zshrc` 설치 항목 추가
- `install.sh`: tmux 설치 후 launcher와 함께 `tmux-zshrc`도 설치하고, runtime cleanup에서 tmux zshrc 삭제 제거
- `README.md`, `AGENTS.md`, `HISTORY.md`, `CONVERSATION.md`: 현재 상태와 의사결정 기록

검증:
- `bash -n install.sh`: 통과
- `bash -n scripts/tmux-session-launcher`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- 임시 `ZDOTDIR`에 `dotfiles/tmux.zshrc`를 `.zshrc`로 배치 후 `zsh -ic '...'`: `PROMPT=$ `, `compinit: function`, `_git` 확인
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test kill-server`: 통과
- 임시 `HOME`, `REPO_RAW_URL=file://...`로 `install.sh` 실행: `tmux-zshrc`가 `~/.cache/dotfiles/.zshrc`에 설치되고 managed 상태로 기록됨
- 설치된 임시 `ZDOTDIR`로 `zsh -ic '...'`: `PROMPT=$ `, `compinit: function`, `_git` 확인

후속 주의:
- tmux 안에서 개인 `~/.zshrc` 전체를 읽지는 않으므로, tmux pane에 필요한 zsh 설정은 `dotfiles/tmux.zshrc`에 명시적으로 추가해야 합니다.

## 2026-05-13 - managed 설치 항목 자동 갱신

요약:
- 실제 설치 환경에서 `~/.local/bin/tmux-session-launcher`가 이전 버전으로 남아 있어, repo 수정 후에도 tmux popup은 계속 오래된 launcher를 실행하는 문제를 확인했습니다.
- 기존 설치 파일이 있으면 항상 확인 프롬프트를 띄우는 구조 때문에 사용자가 force install을 거절하면 managed 항목도 갱신되지 않았습니다.
- manifest에 이미 기록된 managed 항목은 재설치 시 자동으로 백업 후 갱신하고, 비관리 파일만 기존처럼 확인을 요구하도록 변경했습니다.

변경 파일:
- `install.sh`: `is_managed "$name"`인 기존 target은 확인 없이 백업 후 새 파일로 갱신
- `README.md`: managed 항목은 재설치 시 자동 갱신된다는 설명 추가
- `HISTORY.md`, `CONVERSATION.md`: 설치된 launcher가 오래된 상태로 남는 원인 기록

검증:
- `bash -n install.sh`: 통과
- `bash -n scripts/tmux-session-launcher`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- 임시 `HOME`, `REPO_RAW_URL=file://...`, 기존 managed launcher를 오래된 내용으로 바꾼 뒤 `install.sh` 실행: 확인 프롬프트 없이 백업 후 최신 launcher로 갱신됨
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test kill-server`: 통과
- `tmux -L launcher-test ... './scripts/tmux-session-launcher'` 후 `send-keys c`: `New session name:` prompt 진입 확인

후속 주의:
- manifest가 없는 환경에서 이미 존재하는 파일은 여전히 비관리 파일로 취급되어 덮어쓰기 확인이 필요합니다.

## 2026-05-13 - tmux launcher Commands query/session 충돌 수정

요약:
- 이전 수정 후에도 `Commands>` prompt에서 인식되지 않은 query가 session row와 함께 남아 있으면 Enter가 session switch로 떨어져 launcher가 종료될 수 있는 경로가 남아 있었습니다.
- `Commands>`에서 Enter를 누를 때 query가 비어 있지 않으면 항상 command로만 해석하고, 알 수 없는 명령은 오류를 보여준 뒤 launcher로 복귀하도록 정리했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: `Commands>` Enter 분기에서 non-empty query를 session row보다 우선 처리하도록 수정
- `README.md`: `Commands>` query는 command 전용이며 session 검색 이동은 `Sessions>`에서 해야 한다는 설명 추가
- `HISTORY.md`, `CONVERSATION.md`: 버그 수정 맥락 기록

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `bash -n install.sh`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test kill-server`: 통과

후속 주의:
- `Commands>` prompt에서는 session 이름과 같은 문자열을 입력해도 command 해석이 우선이며, session 검색/이동은 `Sessions>` prompt로 전환해야 합니다.

## 2026-05-13 - tmux launcher fzf 출력 파싱 수정

요약:
- 설치 후 실제 tmux popup에서 `Commands>`에 어떤 key를 눌러도 launcher가 종료되는 문제를 다시 확인했습니다.
- 원인은 `fzf --print-query --expect` 출력 순서를 잘못 해석해 key 입력이 session 이름으로 오인되던 것이었고, query/key 파싱 순서를 실제 출력에 맞게 수정했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: `parse_selection()`이 `fzf` 출력의 첫 줄을 query, 둘째 줄을 pressed key로 읽도록 수정
- `README.md`: launcher가 의존하는 `fzf` 출력 순서 제약 설명 추가
- `HISTORY.md`, `CONVERSATION.md`: 원인과 수정 맥락 기록

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `bash -n install.sh`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- `printf 'alpha\nbeta\n' | fzf --filter=alpha --expect=c,d,r,enter --print-query`: 첫 줄 query, 둘째 줄 selected row 출력 형식 재확인
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test kill-server`: 통과

후속 주의:
- launcher 동작은 `fzf --print-query --expect` 출력 형식에 의존하므로, 관련 옵션 조합을 바꿀 때는 반환 줄 순서를 다시 확인해야 합니다.

## 2026-05-13 - tmux launcher query 입력 종료 방지

요약:
- `Commands>` prompt에 명령 문자열을 입력하고 `Enter`를 눌렀을 때, 해석되지 않은 query가 기존 Enter 기본 동작으로 흘러 launcher가 종료되는 버그를 수정했습니다.
- query 명령 dispatcher를 추가해 textual alias를 지원하고, 알 수 없는 명령이나 매칭 없는 session 검색은 종료 대신 안내 메시지 후 launcher로 복귀하게 했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: query command dispatcher 추가, invalid query/no-match Enter 처리 보강
- `README.md`: `Commands>` textual alias와 invalid command 복귀 동작 설명 추가
- `HISTORY.md`, `CONVERSATION.md`: 변경 이력과 사용자 의도 기록

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `bash -n install.sh`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- `printf 'alpha\n' | fzf --filter=rename --expect=tab,c,d,r,enter --print-query`: no-match query 출력 형태 확인
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test kill-server`: 통과

후속 주의:
- `Commands>`에서 query 명령은 단일 문자뿐 아니라 alias도 허용하지만, session 이름과 동일한 keyword를 `Commands>`에서 입력하면 명령이 우선합니다.

## 2026-05-09 - tmux launcher Commands query 처리 수정

요약:
- `Commands>`에서 `c`, `d`, `r`을 입력 후 Enter로 실행하면 query만 남아 session switch/종료 분기로 떨어질 수 있는 버그를 수정했습니다.
- `Commands>`의 Enter 입력 query가 `c`, `d`, `r`, `exit`일 때는 session row 처리보다 먼저 command로 해석합니다.

변경 파일:
- `scripts/tmux-session-launcher`: `Commands>` Enter query command 분기 추가
- `HISTORY.md`, `CONVERSATION.md`: 버그 수정 맥락 기록

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `bash -n install.sh`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test list-keys -T prefix s`: popup launcher 바인딩 확인
- `fzf --filter=c --expect=tab,c,d,r,enter --print-query`: `c` query와 session row 출력 형태 확인
- `fzf --filter=exit --expect=tab,c,d,r,enter --print-query`: `exit` query 출력 형태 확인

후속 주의:
- `Commands>`에서 `c`, `d`, `r`은 단축키로 눌러도, 입력 후 Enter로 실행해도 command로 처리됩니다.

## 2026-05-09 - tmux launcher exit 입력과 Sessions prompt 명령 차단

요약:
- `Commands>`에서 `exit`를 입력하고 Enter를 누르면 launcher가 닫히도록 추가했습니다.
- `Sessions>`에서는 `c`, `d`, `r`이 command로 실행되지 않고 session 검색 입력으로만 처리되도록 prompt별 expect key를 분리했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: `--print-query`로 입력 query를 파싱하고, `Commands>`에서만 `c`/`d`/`r` expect key를 활성화
- `README.md`: `Commands> exit` 닫기와 `Sessions>` 검색 동작 설명 추가
- `HISTORY.md`, `CONVERSATION.md`: 변경 이력과 버그 수정 맥락 기록

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `bash -n install.sh`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test list-keys -T prefix s`: popup launcher 바인딩 확인
- `fzf --filter=base --expect=tab,c,d,r,enter --print-query`: query/session row 출력 형태 확인
- `fzf --filter=exit --expect=tab,c,d,r,enter --print-query`: `exit` query 출력 형태 확인
- `fzf --filter=c --expect=tab,enter --print-query`: `Sessions>`에서 `c`가 command key가 아닌 query로 처리되는 형태 확인

후속 주의:
- `Commands>`에서 `exit` 이름의 session을 검색해 Enter를 눌러도 닫기 명령으로 우선 처리됩니다.

## 2026-05-09 - tmux launcher rename 종료와 Tab prompt 전환 수정

요약:
- 선택 session rename 후 launcher가 종료될 수 있는 `set -e` 조건식 경로를 `if` 문으로 수정했습니다.
- session list 단일 UI는 유지하면서 `Tab`으로 prompt가 `Commands>`와 `Sessions>` 사이에서 전환되도록 복구했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: rename 후 current session 갱신 조건을 `if`로 변경, `tab` expect와 prompt 전환 상태 추가
- `README.md`: `Tab` prompt 전환 설명 추가
- `HISTORY.md`, `CONVERSATION.md`: 변경 이력과 버그 수정 맥락 기록

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `bash -n install.sh`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test list-keys -T prefix s`: popup launcher 바인딩 확인
- `fzf --filter=base --expect=tab,c,d,r,enter`: session row 출력 파싱 형태 확인

후속 주의:
- `Commands>`와 `Sessions>`는 같은 session list UI의 prompt 상태이며, 별도 command list 화면은 없습니다.

## 2026-05-09 - tmux session launcher 단일 list UI로 정리

요약:
- command 목록 화면을 제거하고 session list 하나만 보이도록 launcher UI를 정리했습니다.
- prompt는 `Commands >`로 유지하되, list 항목은 항상 session 목록이며 `c`, `d`, `r` 키가 선택 session에 바로 동작합니다.
- 새 session 생성, 삭제 확인, rename 입력은 같은 popup 아래 prompt에서 진행한 뒤 session list로 돌아옵니다.

변경 파일:
- `scripts/tmux-session-launcher`: commands/sessions 이중 모드 제거, 단일 session list에서 `c`/`d`/`r`/`Enter` 처리
- `README.md`: launcher 키 설명 갱신
- `HISTORY.md`, `CONVERSATION.md`: 변경 이력과 사용자 의도 기록

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `bash -n install.sh`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test list-keys -T prefix s`: popup launcher 바인딩 확인
- `fzf --filter=base --expect=c,d,r,enter`: session row 출력 파싱 형태 확인

후속 주의:
- `c`, `d`, `r` 키는 fzf 검색 입력이 아니라 launcher command로 처리됩니다.

## 2026-05-09 - tmux session launcher command UI 확장

요약:
- popup launcher 시작 화면을 `Commands >`로 바꾸고 `Tab`으로 `Sessions >`와 전환하도록 변경했습니다.
- `Ctrl+n`은 제거하고 command 목록의 `c`, `d`, `r`로 새 session 생성, 삭제, 이름 변경을 수행하도록 확장했습니다.
- command 실행 후 popup을 닫지 않고 launcher로 돌아오게 했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: command/session 모드 루프 추가, `c`/`d`/`r` command 구현, 새 session 생성 시 기존 session 유지
- `README.md`: launcher 키 설명 갱신
- `HISTORY.md`, `CONVERSATION.md`: 변경 이력과 사용자 의도 기록

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `bash -n install.sh`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test list-keys -T prefix s`: popup launcher 바인딩 확인
- `fzf --filter='c:' --expect=tab,enter`: command row 출력 파싱 형태 확인

후속 주의:
- 현재 session 삭제는 원래 창을 닫는 위험을 피하기 위해 launcher에서 막습니다.

## 2026-05-09 - tmux 개별 설치 시 session launcher 누락 방지

요약:
- `curl ... install.sh | bash` 실행 후 번호 `1`만 선택하면 `tmux` 설정만 설치되고 `~/.local/bin/tmux-session-launcher`가 없어 `Ctrl+a s` popup launcher가 동작하지 않는 경로를 확인했습니다.
- `tmux` 설치 후 hook에서 launcher 항목도 함께 설치하도록 보강했습니다.

변경 파일:
- `install.sh`: `install_by_name` helper 추가, `tmux` after-install hook에서 `tmux-session-launcher` 설치 보장

검증:
- 임시 `HOME`, `REPO_RAW_URL=file://...`, 입력값 `1`로 `install.sh` 실행: `.tmux.conf`와 `.local/bin/tmux-session-launcher`가 함께 설치되고 launcher에 실행 권한이 붙는 것을 확인

후속 주의:
- `Ctrl+a s` 실행에는 여전히 `fzf`가 필요합니다. 설치 시 dependency 설치 질문에서 거절하면 launcher 항목은 건너뜁니다.

## 2026-05-09 - tmux popup session launcher 추가

요약:
- `Ctrl+a s` 기본 session chooser를 popup 기반 fzf session launcher로 교체했습니다.
- session 목록 선택, Enter로 이동, `Ctrl+n`으로 새 session 생성이 가능하도록 별도 스크립트로 분리했습니다.
- 향후 rename/delete/worktree/project launcher로 확장하기 쉽도록 `scripts/tmux-session-launcher`에 UI 로직을 모았습니다.

변경 파일:
- `dotfiles/tmux.conf`: `unbind-key s` 후 `display-popup` 기반 launcher 바인딩 추가
- `scripts/tmux-session-launcher`: fzf 기반 tmux session 선택/생성 스크립트 추가
- `install.toml`: `fzf` 의존성 추가, launcher 설치 항목 추가
- `install.sh`: launcher 설치 후 실행 권한 부여 hook 추가
- `README.md`, `AGENTS.md`, `CONVERSATION.md`: 설치/운영 맥락 갱신

검증:
- `bash -n install.sh`: 통과
- `bash -n scripts/tmux-session-launcher`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test list-keys -T prefix s`: `display-popup` launcher 바인딩 확인

후속 주의:
- launcher 실행에는 `fzf`가 필요합니다. 현재 검증 환경에는 `fzf`가 없어 실제 fzf 선택 UI는 설치 후 확인해야 합니다.

## 2026-05-05 - tmux window 이동을 prefix Tab으로 변경

요약:
- PowerShell/Windows Terminal에서 `Ctrl+Tab`이 tmux까지 전달되지 않을 수 있어 탭 이동 단축키를 prefix 기반으로 변경했습니다.
- 이제 `Ctrl+a` 후 `Tab`으로 다음 window, `Ctrl+a` 후 `Shift+Tab`으로 이전 window로 이동합니다.

변경 파일:
- `dotfiles/tmux.conf`: `bind-key -n 'C-Tab'`/`C-S-Tab`을 `bind-key Tab`/`BTab`으로 변경

검증:
- `bash -n install.sh`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test list-keys Tab`: `bind-key -T prefix Tab next-window` 확인
- `tmux -L codex-dotfiles-test list-keys BTab`: `bind-key -T prefix BTab previous-window` 확인

후속 주의:
- 터미널에 따라 `Shift+Tab`은 `BTab`으로 전달되지 않을 수 있습니다. 이 경우 추가 대체 키를 지정할 수 있습니다.

## 2026-05-05 - tmux 하단 status bar와 탭 복원

요약:
- 현재 경로를 상단 status bar로 옮기며 기존 하단 status bar와 신규 window tab 표시가 사라지는 회귀가 생겼습니다.
- 하단 status bar와 window tab은 원래 동작으로 복원하고, 현재 경로는 pane border 상단에 표시하도록 변경했습니다.

변경 파일:
- `dotfiles/tmux.conf`: `status-position bottom`, 기존 `status-left` 구성을 복원
- `dotfiles/tmux.conf`: 빈 `window-status-format`과 `window-status-current-format` 설정 제거
- `dotfiles/tmux.conf`: `pane-border-status top`, `pane-border-format "#{pane_current_path}"` 추가
- `AGENTS.md`, `CONVERSATION.md`: 최신 표시 방식 기록

검증:
- `bash -n install.sh`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test show-options -gqv status-position`: `bottom` 확인
- `tmux -L codex-dotfiles-test show-options -gqv window-status-format`: 기본 window tab format 확인
- `tmux -L codex-dotfiles-test show-options -gqv pane-border-status`: `top` 확인
- `tmux -L codex-dotfiles-test show-options -gqv pane-border-format`: `#{pane_current_path}` 확인
- `tmux -L codex-dotfiles-test capture-pane -p`: pane 본문에는 `$`만 표시 확인

후속 주의:
- pane border 상단 경로는 tmux pane border 기능을 사용하므로, status bar의 window tab 표시와 별도로 동작합니다.

## 2026-05-05 - tmux 설치 시 기존 런타임 정리

요약:
- 사용자가 tmux server를 완전히 끊고 다시 실행하면 새 설정이 적용된다고 확인했습니다.
- `install.sh`에서 tmux 설치 후 기존 tmux server와 이전 임시 zsh rc를 정리하도록 추가했습니다.

변경 파일:
- `install.sh`: tmux 항목 설치 또는 이미 설치됨 확인 후 `~/.cache/dotfiles/.zshrc` 제거
- `install.sh`: 기존 tmux session이 있으면 `tmux kill-server`를 실행해 다음 tmux 실행부터 새 설정을 사용하게 함
- `CONVERSATION.md`: 설치 과정에서 tmux 런타임을 정리해야 한다는 결정 기록

검증:
- `bash -n install.sh`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- 임시 `HOME`, `TMUX_TMPDIR`, `REPO_RAW_URL=file://...`로 `install.sh` 실행: tmux 설치 성공
- 같은 격리 테스트에서 기존 `~/.cache/dotfiles/.zshrc` 제거 확인
- 같은 격리 테스트에서 기존 tmux server 종료 확인

후속 주의:
- 설치 중 실행 중인 tmux session은 종료됩니다. 사용자가 요청한 동작이지만, tmux 안에서 설치하면 해당 세션도 끊길 수 있습니다.

## 2026-05-05 - tmux 경로를 상단 status bar로 이동

요약:
- `precmd`로 경로를 출력하는 방식은 `cd` 시 터미널 본문에 새 경로가 추가되어, 사용자가 원하는 “최상단 경로 갱신”과 달랐습니다.
- 현재 경로는 tmux 상단 status bar에서 갱신하고, shell 본문은 `$ ` 프롬프트만 남기도록 되돌렸습니다.

변경 파일:
- `dotfiles/tmux.conf`: `default-command`를 `PROMPT="$ "`와 `zsh -f` 실행으로 단순화
- `dotfiles/tmux.conf`: `status-position top`, `status-left`에 `#{pane_current_path}` 표시
- `dotfiles/tmux.conf`: status bar에 경로만 보이도록 window status format을 비움
- `AGENTS.md`, `CONVERSATION.md`: 최신 tmux 표시 의도 기록

검증:
- `bash -n install.sh`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test capture-pane -p`: pane 본문에는 `$`만 표시 확인
- `tmux -L codex-dotfiles-test show-options -gqv status-position`: `top` 확인
- `tmux -L codex-dotfiles-test display-message -p '#{pane_current_path}'`: 초기 경로 확인
- `tmux -L codex-dotfiles-test send-keys 'cd /tmp' Enter` 후 display: `/tmp`로 갱신 확인

후속 주의:
- tmux 상단 status bar는 pane capture 출력에는 포함되지 않으므로 `display-message -p '#{pane_current_path}'`로 갱신을 확인합니다.

## 2026-05-05 - tmux 경로 반복 출력 방지

요약:
- 이전 변경은 현재 경로를 prompt 자체에 넣어 Enter를 누를 때마다 경로가 반복 출력됐습니다.
- 사용자는 최초 진입 시 경로를 한 번 표시하고, 같은 위치에서는 `$`만 반복되며, `cd`로 위치가 바뀔 때만 새 경로가 표시되기를 원했습니다.

변경 파일:
- `dotfiles/tmux.conf`: tmux 시작 시 전용 `~/.cache/dotfiles/.zshrc`를 생성하고 `ZDOTDIR`로 읽게 변경
- `dotfiles/tmux.conf`: zsh `precmd`에서 이전 `PWD`와 현재 `PWD`를 비교해 변경된 경우에만 경로 출력
- `AGENTS.md`, `CONVERSATION.md`: 최신 tmux 표시 의도 기록

검증:
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test capture-pane -p`: 최초 경로 1회와 `$` 확인
- `tmux -L codex-dotfiles-test send-keys Enter Enter Enter` 후 capture: `$`만 반복 확인
- `tmux -L codex-dotfiles-test send-keys 'cd /tmp' Enter Enter` 후 capture: `/tmp`는 1회만 표시되고 이후 `$`만 반복 확인

후속 주의:
- tmux 안에서는 사용자 `~/.zshrc` 대신 `~/.cache/dotfiles/.zshrc`의 최소 설정을 읽습니다.

## 2026-05-05 - tmux 프롬프트 상단에 현재 경로 표시

요약:
- 실제 설치 후 tmux 안에서 `$` 프롬프트는 정상 표시되지만 현재 경로가 보이지 않는다고 보고했습니다.
- 경로를 tmux status bar 대신 zsh 프롬프트의 첫 줄에 표시하도록 조정했습니다.

변경 파일:
- `dotfiles/tmux.conf`: `printf`로 실제 newline이 들어간 `PROMPT`를 만들어 현재 작업 디렉터리를 `$` 위에 표시
- `dotfiles/tmux.conf`: status bar 오른쪽 경로 표시는 중복을 피하기 위해 비움
- `AGENTS.md`, `CONVERSATION.md`: 최신 tmux 표시 의도 기록

검증:
- `bash -n install.sh`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test capture-pane -p`: 현재 경로와 `$` 프롬프트 확인
- `tmux -L codex-dotfiles-test send-keys 'cd /tmp' Enter` 후 capture: `/tmp`로 갱신 확인

후속 주의:
- zsh를 `-f`로 실행하므로 tmux 안에서는 사용자 `~/.zshrc`를 읽지 않습니다.
- tmux socket 접근은 sandbox 제한 때문에 승격 실행으로 검증했습니다.

## 2026-05-05 - tmux 프롬프트 설정을 tmux.conf로 단순화

요약:
- `tmux-zshrc`가 설치되지 않은 상태에서 `ZDOTDIR`만 바꾸면 zsh new user 설정 화면이 뜰 수 있음을 확인했습니다.
- tmux 프롬프트 요구사항은 `tmux.conf` 하나로 처리하도록 단순화했습니다.

변경 파일:
- `dotfiles/tmux.conf`: zsh를 `-f`로 실행하고 `PROMPT="$ "`, `RPROMPT=""` 환경값을 전달
- `install.toml`: `tmux-zshrc` 설치 항목 제거
- `dotfiles/tmux-zshrc`: 제거
- `README.md`, `AGENTS.md`: enabled 항목과 구조 설명 정리

검증:
- `git diff --check`: 통과
- `bash -n install.sh`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `tmux -L codex-dotfiles-test capture-pane -p`: `$` 프롬프트 확인

후속 주의:
- zsh를 `-f`로 실행하므로 tmux 안에서는 사용자 `~/.zshrc`를 읽지 않습니다. 현재 요구사항인 단순 `$` 프롬프트에는 이 방식이 가장 덜 꼬입니다.

## 2026-05-05 - tmux 프롬프트를 `$` 전용으로 조정

요약:
- 실제 설치 후 tmux에서 `LAPTOP-...%`가 반복되는 문제를 확인했습니다.
- 프롬프트에는 `$`만 표시하고, 현재 경로는 tmux 하단 status bar에 표시하도록 조정했습니다.

변경 파일:
- `dotfiles/tmux.conf`: `PROMPT="$ "`와 `RPROMPT=""` 기본 환경값을 넘기고, `status-right`에 `#{pane_current_path}` 표시
- `dotfiles/tmux-zshrc`: 기존 `.zshrc`가 prompt를 다시 덮어써도 `$ `가 유지되도록 `precmd` 재정의

검증:
- `git diff --check`: 통과
- `zsh -n dotfiles/tmux-zshrc`: 통과
- `bash -n install.sh`: 통과

후속 주의:
- 이 항목의 `tmux-zshrc` 방식은 이후 단순화 작업에서 제거됐습니다. 최신 방식은 `tmux.conf`만 사용합니다.

## 2026-05-05 - 인수인계 문서 역할 정리

요약:
- `AGENTS.md`, `HISTORY.md`, `CONVERSATION.md` 사이에 겹치던 상세 설명을 줄이고 역할을 분리했습니다.
- `AGENTS.md`는 색인과 작업 규칙 중심으로 축소했습니다.

변경 파일:
- `AGENTS.md`: 상세 컨텍스트를 제거하고 빠른 상태, 문서 역할, 작업 규칙, 검증 명령만 유지
- `HISTORY.md`: 이번 정리 이력 추가
- `CONVERSATION.md`: 문서 중복 정리 요청과 결정 맥락 추가

검증:
- `git diff --check`: 통과
- `bash -n install.sh`: 통과
- `zsh -n dotfiles/tmux-zshrc`: 통과

후속 주의:
- 상세 설치 구조는 `README.md`, 변경 이력은 `HISTORY.md`, 대화 맥락은 `CONVERSATION.md`에만 추가해 중복을 피하세요.

## 2026-05-05 - tmux 프롬프트와 에이전트 인수인계 문서 추가

요약:
- tmux 진입 시 zsh 프롬프트가 `%`로 보이는 상태를 tmux 안에서만 `현재경로$ ` 형태로 바꾸는 작업을 진행했습니다.
- tmux status bar 위치를 하단으로 명시했습니다.
- 다음 에이전트가 현재 상태를 빠르게 파악할 수 있도록 `AGENTS.md`를 추가했습니다.

변경 파일:
- `dotfiles/tmux.conf`: `status-position bottom` 추가, tmux 전용 zsh rc를 읽도록 `default-command` 추가
- `dotfiles/tmux-zshrc`: 기존 `~/.zshrc`를 읽은 뒤 `PROMPT='%~$ '`와 `RPROMPT=''`를 설정하는 새 파일 추가
- `install.toml`: `tmux-zshrc`를 enabled 설치 항목으로 추가
- `AGENTS.md`: 간단 요약, 상세 컨텍스트, 다음 에이전트 응답 가이드 추가
- `HISTORY.md`: 주요 작업 이력 작성 규칙과 첫 이력 항목 추가
- `CONVERSATION.md`: 주제별 대화 맥락 기록 방식과 현재 대화 요약 추가
- `README.md`: `AGENTS.md` 링크와 `tmux-zshrc` 구조 반영

검증:
- `bash -n install.sh`: 통과
- `zsh -n dotfiles/tmux-zshrc`: 통과
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 별도 socket에서 로딩 확인

후속 주의:
- 기존 `~/.zshrc`가 `precmd`나 prompt theme으로 프롬프트를 나중에 다시 덮어쓰면 `dotfiles/tmux-zshrc`의 `PROMPT`가 원하는 대로 유지되지 않을 수 있습니다.
- `install_dotfiles.sh`와 `get_dotfiles.sh`는 레거시 성격이 강하고 자동 실행 시 위험하므로, 설치 흐름 변경 시 우선 `install.sh`와 `install.toml` 중심으로 작업하세요.
