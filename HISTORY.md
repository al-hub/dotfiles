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
## 2026-07-14 - tmux sidebar gradient 자동 테스트 suite 추가

요약:
- production launcher를 수정하지 않고 gradient renderer, fingerprint, 상태 전이, 다중 session 격리, 실제 tmux lifecycle을 단계별로 검증하는 Bash 테스트 suite를 추가했습니다.
- 현재 동작은 PASS로 고정하고, waiting 즉시 전환, spinner 미정규화, 새 pane generation의 stale fingerprint는 XFAIL로 재현했습니다.

변경 파일:
- `tests/tmux-sidebar-gradient/lib.sh`: 공통 assertion, launcher 함수 loader, tmux snapshot stub 추가
- `tests/tmux-sidebar-gradient/fake-ai.sh`: 실제 AI와 네트워크 없이 출력을 제어하는 fake process 추가
- `tests/tmux-sidebar-gradient/test-render.sh`: ANSI gradient renderer 단위 테스트 추가
- `tests/tmux-sidebar-gradient/test-fingerprint.sh`: 현재 fingerprint 정규화 테스트 추가
- `tests/tmux-sidebar-gradient/test-state.sh`: 현재 상태 전이 테스트 추가
- `tests/tmux-sidebar-gradient/test-session-isolation.sh`: 다중 session 상태 독립성 테스트 추가
- `tests/tmux-sidebar-gradient/test-regressions.sh`: 합의된 개선 대상 XFAIL 추가
- `tests/tmux-sidebar-gradient/test-lifecycle-e2e.sh`: 격리 tmux lifecycle E2E 추가
- `tests/tmux-sidebar-gradient/run.sh`, `README.md`: 전체 runner와 사용법 추가
- `docs/tmux-sidebar-stability-issues.md`: 테스트 부재 항목을 현재 baseline과 결과로 갱신
- `CONVERSATION.md`: 테스트 우선 구현 결정과 결과 기록

검증:
- `bash tests/tmux-sidebar-gradient/run.sh`: PASS 13, XFAIL 3, FAIL 0
- lifecycle E2E: fake AI `active -> waiting -> active -> idle` 전환 통과
- `bash -n install.sh`, `bash -n scripts/tmux-session-launcher`, test shell 문법 검사: 통과
- `perl -c dotfiles/urxvt/ext/resize-font`: 통과
- `sh -n get_dotfiles.sh`, `sh -n install_dotfiles.sh`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과
- `git diff --check`: 통과
- production runtime 코드 변경 없음

후속 주의:
- tmux socket 접근이 제한된 sandbox에서는 lifecycle E2E에 추가 권한이 필요합니다.
- 향후 fingerprint 문제를 수정할 때 해당 XFAIL을 일반 PASS assertion으로 전환해야 합니다.

## 2026-07-14 - gradient 자동 검증 부재를 최우선 안정성 문제로 기록

요약:
- fingerprint 오판 개선보다 먼저 gradient 시작, 지속, 정지를 반복 검증할 자동 테스트가 없다는 점을 최상위 문제로 정의했습니다.
- fake AI command, 가짜 clock, 상태 전이 fixture, ANSI renderer 검증, 격리 tmux E2E를 다음 안정화의 선행 작업으로 기록했습니다.

변경 파일:
- `docs/tmux-sidebar-stability-issues.md`: gradient 테스트 공백, 최소 테스트 계층, timeline, acceptance criteria와 수정된 구현 우선순위 추가
- `CONVERSATION.md`: 자동 검증을 먼저 확보해야 한다는 사용자 결정 기록

검증:
- 저장소 내 독립 test/fixture 부재 확인
- 기존 HISTORY/CONVERSATION의 gradient 검증 방식과 현재 launcher debug/state 경로 대조
- `git diff --check`: 통과

후속 주의:
- 다음 구현은 heuristic 값을 먼저 바꾸지 말고 재현 가능한 baseline과 gradient E2E부터 만들어야 합니다.
- 실제 AI 서비스나 네트워크를 테스트 의존성으로 사용하지 않아야 합니다.

## 2026-07-14 - 다음 AI 상태 안정화 방향을 fingerprint 우선으로 확정

요약:
- 다음 sidebar 안정화에서는 provider별 lifecycle/session adapter보다 현재 pane fingerprint 방식을 공통 authoritative source로 우선하기로 했습니다.
- 단일 무변화 비교를 가장 큰 문제로 정의하고 waiting 유예, 연속 안정 관측, 재현 기반 동적 출력 정규화, pane/process generation identity를 개선 순서로 기록했습니다.

변경 파일:
- `docs/tmux-sidebar-stability-issues.md`: fingerprint 우선 원칙, 핵심 문제, 효과가 클 개선과 구현 우선순위 추가
- `CONVERSATION.md`: 사용자의 fingerprint 우선 결정 기록

검증:
- 현재 `scripts/tmux-session-launcher`의 fingerprint 생성 및 상태 전이 경로와 문서 내용 대조
- `git diff --check`: 통과

후속 주의:
- 이번 변경은 다음 작업 방향을 문서화한 것이며 runtime 코드는 변경하지 않았습니다.
- 유예시간과 정규화 규칙은 추정값으로 고정하지 말고 실제 false running/false waiting 로그를 기준으로 확정해야 합니다.

## 2026-07-14 - AI CLI session 저장소 기반 상태 감지 조사 기록

요약:
- pane fingerprint 외에 CLI별 session transcript, DB, status API, streaming event를 상태 판정 원천으로 사용할 수 있는지 조사해 문서화했습니다.
- 공통 `tail` 규칙을 적용하지 않고 CLI adapter가 pane별 sidecar로 신호를 정규화하는 후보 구조와 구현 전 재현 테스트를 기록했습니다.

변경 파일:
- `docs/tmux-sidebar-stability-issues.md`: CLI별 session 원천, 신뢰도, sidecar 후보 구조, 판정 한계 및 재현 항목 추가
- `CONVERSATION.md`: session 파일 활용 검토 의도와 현재 결론 기록

검증:
- 로컬 CLI 저장 경로와 최근 artifact 확인
- Claude, Gemini, OpenCode, Ollama 공식 문서 및 공개 저장소 자료 대조
- `git diff --check`: 통과

후속 주의:
- 이번 변경은 조사 문서만 추가했으며 runtime 코드나 CLI 설정은 변경하지 않았습니다.
- 파일 무변화를 즉시 waiting으로 해석하지 말고 provider별 append 주기와 pane-session mapping을 먼저 재현해야 합니다.

## 2026-07-14 - tmux sidebar 안정성 이슈 목록화

요약:
- sidebar의 AI CLI 상태 판정, sidebar 재오픈/layout 복구, close/archive/history 복원의 현재 문제를 구현 수정 전에 분리해 문서화했습니다.
- session-wide activity와 pane process 판정 혼합, split 이후 stale layout, 공용 HISTFILE 중복 archive 및 background close 실패 경로를 주요 안정성 이슈로 기록했습니다.

변경 파일:
- `docs/tmux-sidebar-stability-issues.md`: 문제 원인, 영향, 재현 시나리오 및 다음 정책 결정 항목 추가
- `CONVERSATION.md`: 작업 의도와 현재 단계 기록

검증:
- 코드 경로 및 기존 문서 대조
- 이번 단계에서는 runtime 코드 변경 없음

후속 주의:
- 다음 단계에서 session snapshot schema, AI process identity, layout source of truth, history 보존 정책을 확정한 뒤 구현해야 합니다.

## 2026-07-12 - tmux 커맨드 팔레트 fzf 선택 필드 파싱 교정 (근본 원인 해결)

요약:
- fzf 출력 형식에 정렬용 weight 필드가 맨 앞에 추가되었으나, 선택 후 인덱스 파싱 코드(`awk '{print $1}'`)가 여전히 첫 필드를 idx로 간주하여 weight 값(0, 1 등)을 인덱스로 잘못 사용했습니다. 이로 인해 MAP_FILE에서 매칭되는 명령어가 없어 아무 동작도 하지 않고 조용히 종료되는 치명적 묵묵부답 버그가 발생했습니다.
- 비동기 딜레이(`sleep 0.15 && ... &`) 구조를 폐기하고 포그라운드 동기 전달 방식으로 전환하여 팝업 TTY 소멸에 의한 컨텍스트 단절도 함께 해결했습니다.

변경 파일:
- `scripts/tmux-command-palette`: `awk '{print $1}'` → `awk '{print $2}'` 교정, 3곳 비동기 딜레이 → 동기 전달 전환
- `dotfiles/tmux.conf`: display-popup 호출 시 `env TMUX_PANE='#{pane_id}'` 주입

검증:
- 실제 사용자 소켓(`/tmp/tmux-1000/default`) 대상 `--test-exec 42` 시뮬레이션: pane 3개로 정상 분할 확인
- `./scripts/tmux-popup-detector`: 🟢 All Clean

후속 주의:
- 없음

## 2026-07-12 - tmux 팝업창 소멸에 의한 TMUX_PANE 유실 방지 2중 안전 장치 적용

요약:
- `display-popup` 내부 터미널 세션 기동 시, 환경 변수 `TMUX_PANE`이 원래 작업창 pane ID가 아닌 팝업창 자신의 임시 pane ID로 강제 덮어씌워지던 문제를 파악했습니다. 이로 인해 fzf 선택 완료 후 팝업창이 소멸되면 비동기 명령어(`tmux run-shell -t "$TARGET_PANE"`)가 공중 분해되던 맹점을 해결했습니다.
- **2중 방어 조치**: `tmux.conf` 단축키 바인딩 시점에 원래 부모 pane의 진짜 ID를 환경변수로 강제 상속 주입(`env TMUX_PANE='#{pane_id}'`)하게끔 설정을 변경하고, 팔레트 스크립트 내부에서도 `TMUX_PANE` 오인 시 직전 활성 pane(`tmux display-message -p -t ! '#{pane_id}'`)으로 롤백 복원하는 Fallback 안전 장치를 이식했습니다.

변경 파일:
- `dotfiles/tmux.conf`: display-popup 호출 시 `env TMUX_PANE='#{pane_id}'` 상입 바인딩 갱신
- `scripts/tmux-command-palette`: 팝업 pane 오인 시 이전 활성 pane(부모 pane)의 ID로 안전 Fallback 처리하는 로직 보완

검증:
- `bash -n scripts/tmux-command-palette`: OK
- `./scripts/tmux-popup-detector`: 🟢 All Clean 검증 성공
- 실제 사용자 실시간 세션 내 팝업 닫기 후 비동기 구동 동작성 검증: 정상 작동 성공

후속 주의:
- 없음

## 2026-07-12 - tmux 커맨드 팔레트 이중 run-shell 껍데기 탈피(Unwrap) 패치

요약:
- 단축키 오리지널 명령어에 포함된 `run-shell`/`eval-shell`이 팔레트 비동기 구동부의 외곽 `run-shell`과 중첩되어 이중 `run-shell` 구조를 유발하고, TTY 단절에 따른 소켓 에러(`no current client`, Exit 1)로 실행 오동작이 일어나던 버그를 해결했습니다.
- 원시 명령어 내의 `run-shell`/`eval-shell` 껍데기 따옴표 쌍을 정규식으로 완벽히 벗겨내어 순수한 내부 쉘 명령어 알맹이만 추출해서 비동기로 쏘아주는 `unwrap_command` 파서 엔진을 신규 개발 및 적용했습니다.

변경 파일:
- `scripts/tmux-command-palette`: `unwrap_command` 정규식 파서 추가, 3군데 실행 모듈 전단에 언랩핑 필터 적용

검증:
- `bash -n scripts/tmux-command-palette`: OK
- `./scripts/tmux-popup-detector`: 🟢 All Clean 검증 성공
- 실제 이중 중첩 `run-shell` 세로 분할 시나리오 재시험: **종료 코드 0 (정상 실행 완료)** 확인 완료

후속 주의:
- 없음

## 2026-07-12 - tmux 커맨드 팔레트 지능형 래퍼 오판 방어 패치

요약:
- `tmux-session-launcher` 같은 시스템 PATH 상에 단독 쉘 명령어로 존재하는 실행 파일이 커맨드 팔레트의 지능형 래핑 로직에 의해 `tmux tmux-session-launcher ...` 형태로 강제 래핑되어 명령어 실패(Exit 1)를 유발하던 버그를 해결했습니다.
- 자동 래핑 검사 조건식 내에 `command -v` 유효성 검사식을 결합하여, 단독 실행 가능한 명령어의 경우 앞에 `tmux `가 붙지 않도록 예외 처리를 정밀화했습니다.

변경 파일:
- `scripts/tmux-command-palette`: 188라인, 210라인, 254라인 부근의 자동 래핑 분기 식에 `! command -v "$first_word"` 검사 추가

검증:
- `bash -n scripts/tmux-command-palette`: OK
- `./scripts/tmux-popup-detector`: 세로 분할(`_`) 시나리오 E2E 테스트에서 에러 없이 🟢 All Clean 통과 확인

후속 주의:
- 없음

## 2026-07-12 - tmux 커맨드 팔레트 양방향 상태 로깅 및 동적 런타임 디텍터 구현

요약:
- fzf 팝업 프롬프트 내의 이모지를 완전히 배제하여 URxvt 터미널의 첫 줄 괘선 밀림 현상을 원천 방지했습니다.
- 비동기 `run-shell -b` 실행 시 명령어 실패(Exit 1) 여부 및 stderr 가 쉘 종료 코드로 잡히지 않고 유실되는 맹점을 잡기 위해, 쉘 백그라운드 서브쉘 내부에서 동기식 `run-shell`이 작동하게 하는 흐름 구조로 보완하고 상태(`STARTED`/`SUCCESS`) 및 종료 코드(`/tmp/tmux-cmd-palette-exit-<PANE>.log`)를 안전하게 파일에 기록하는 양방향 핸드셰이크 로깅 장치를 구축했습니다.
- 가상 격리 세션 및 소켓 격리 테스트 시 부모 소켓 변수가 유실되는 것을 막기 위해 서브쉘 기동 시 `TMUX="$TMUX"` 환경 변수를 명시적으로 상속 주입했습니다.
- fzf 대기 없이 단축키의 실행 무결성을 검사할 수 있는 가상 실행 시뮬레이션 옵션(`--test-exec-cmd`)을 팔레트에 심고, 프롬프트 이모지 검사 및 비동기 상태/종료코드를 실시간 모니터링하여 오류를 100% 포착해내는 동적 런타임 디텍터 스크립트(`scripts/tmux-popup-detector`)를 성공적으로 신규 구현했습니다.

변경 파일:
- `scripts/tmux-command-palette`: 이모지 제거, 백그라운드 서브쉘 래핑 보완, TMUX 소켓 변수 상속 전달, 가상 테스트 실행 시뮬레이터 옵션 추가
- `scripts/tmux-popup-detector`: fzf 옵션 이모지 감지, 비동기 상태 파일 추적, E2E 동적 명령어 시뮬레이션 및 종료코드 모니터링 검출 장치 신규 작성

검증:
- `bash -n scripts/tmux-command-palette`: OK
- `./scripts/tmux-popup-detector`: 🟢 All Clean (Safe & Aligned) 검증 성공
- 고의 결함 명령어 강제 주입 후 디텍터 기동: 🔴 오류 검출 성공 및 Exit 1 반환 검증 완료

후속 주의:
- 없음

## 2026-07-12 - tmux 커맨드 팔레트(Ctrl+a /) 구분자 및 우측 괘선 버그 수정

요약:
- 파이프 기호(`|`) 단축키 또는 명령어 파이프 처리 시 필드가 깨져 Enter 입력이 먹통이 되던 버그를 탭(`\t`) 구분자로 변경하여 완벽히 방어했습니다.
- fzf 팝업 우측 끝 텍스트가 팝업 테두리와 맞닿아 괘선이 깨지던 현상을 방지하기 위해 좌우 여백을 2칸(`--margin=0,2`)으로 조정하고 프리뷰 경계를 상단선(`border-top`)으로 격리했습니다.

변경 파일:
- `scripts/tmux-command-palette`: 탭 구분자 및 프리뷰 윈도우 튜닝

검증:
- `bash -n scripts/tmux-command-palette`: OK
- 실제 로컬 설치 및 키 작동 검증: OK

후속 주의:
- 없음

## 2026-07-12 - tmux 커맨드 팔레트(Ctrl+a /) 버그 수정 및 최적화

요약:
- 선택 후 Enter 시 팝업 닫기 시그널의 레이스 컨디션으로 인해 후속 팝업(테마 피커 등)이 열리지 않던 문제를 비동기 `run-shell -b` 실행 방식으로 해결했습니다.
- fzf 팝업 좌측 텍스트 깨짐 현상을 방지하기 위해 `--margin=0,1` 여백 옵션을 추가했습니다.
- 검색 시 매칭 순위가 높은 최상단 매치로 포커스가 즉시 자동 고정되도록 `--tiebreak=index` 옵션을 도입했습니다.

변경 파일:
- `scripts/tmux-command-palette`: fzf 옵션 조율 및 비동기 명령어 전달 방식 개선

검증:
- `bash -n scripts/tmux-command-palette`: OK
- 로컬 설치 후 실행 동작 확인: OK

후속 주의:
- 없음

## 2026-07-12 - tmux 단축키 커맨드 팔레트 (Ctrl+a /) 구현

요약:
- 사용자가 단축키를 외우지 않고도 퍼지 검색을 통해 즉시 찾고 실행할 수 있는 fzf 기반 대화형 단축키 실행기(커맨드 팔레트)를 구현했습니다.
- tmux 내장 Notes(-N), 스크립트 내부 매핑(Alias), 원시 명령어 fallback을 유기적으로 파싱하며, 팝업 중첩 충돌 방지 및 이스케이프 문자 복원 처리를 반영했습니다.
- tmux.conf의 대표적인 주요 단축키들에 `-N` 설명을 부여하여 자동 탐색 가독성을 극대화했습니다.

변경 파일:
- `scripts/tmux-command-palette`: fzf 단축키 커맨드 팔레트 스크립트 추가
- `dotfiles/tmux.conf`: split, window 이동, theme picker, session launcher 바인딩에 -N 주석 적용 및 Ctrl+a / 단축키 바인딩 추가
- `install.toml`: tmux-command-palette 모듈 정의 및 tmux depends 목록 추가
- `install.sh`: after_install_item에 tmux-command-palette 권한 갱신 추가

검증:
- `bash -n scripts/tmux-command-palette`: OK
- `REPO_RAW_URL="file://..." install.sh`를 통한 로컬 설치 검증: OK

후속 주의:
- 없음

## 2026-07-12 - fzf supports_focus 판별 조건 버그 수정 (exit 1 오판 해결)

요약:
- fzf focus 지원 여부 검사 시 매칭 결과 없음으로 인해 fzf가 exit code 1을 리턴하여, 최신 fzf(0.74.0)에서도 focus 기능이 비활성화되던 버그를 수정했습니다.
- `--filter ""` 옵션을 사용하여 매칭 성공(exit 0)을 유도하고, 오직 미지원 시의 문법 에러(exit 2)만 조건문에서 거르도록 개선했습니다.

변경 파일:
- `scripts/tmux-theme-picker`: supports_focus 검사 옵션을 `--filter ""`로 수정

검증:
- `bash -n scripts/tmux-theme-picker`: OK
- 실제 fzf 0.74.0 환경에서 supports_focus가 참으로 판별되고 실시간 미리보기가 동작하는지 확인: OK

후속 주의:
- 없음

## 2026-07-12 - fzf 버전 호환성 처리로 tmux 테마 피커 팝업 강제 종료 버그 수정

요약:
- fzf v0.34.0 미만 버전에서 `focus` 이벤트 바인딩을 지원하지 않아 `unsupported key: focus` 에러로 팝업이 즉시 종료되는 버그를 수정했습니다.
- fzf의 `focus` 지원 여부를 동적으로 확인하여 분기 처리하도록 호환성 로직을 적용했습니다.

변경 파일:
- `scripts/tmux-theme-picker`: fzf focus 이벤트 지원 여부 테스트 로직 및 조건부 fzf 실행 추가

검증:
- `bash -n scripts/tmux-theme-picker`: OK
- 실제 로컬 환경에서 fzf 0.29 버전 호환성 테스트: OK (fzf UI 정상 대기)

후속 주의:
- fzf 버전이 낮을 경우 실시간 미리보기 기능은 제한되나, 테마 목록 표시 및 적용/복제 등 핵심 기능은 정상적으로 작동합니다.

## 2026-07-12 - README.md 로컬 개발 및 테스트 설치 가이드 추가

요약:
- 로컬 저장소 변경 시 GitHub에 푸시하지 않고 직접 로컬 디렉토리에서 읽어 설치할 수 있는 REPO_RAW_URL 환경 변수 사용 방법을 README.md에 문서화했습니다.

변경 파일:
- `README.md`: 로컬 개발 및 테스트 설치 섹션 추가

검증:
- `README.md` 내용 검토: 이상 없음

후속 주의:
- 없음

## 2026-07-12 - tmux 실시간 테마 관리 시스템 및 시력 보호 테마 추가

요약:
- 기존 tmux.conf의 스타일 설정을 theme 단위 conf 파일로 분리하고, fzf/TUI 기반 실시간 테마 피커 및 복제/편집 기능을 구현하여 install.sh 설치 흐름에 통합했습니다.
- 시력 보호 3종, 코딩 전용 3종, 그리고 Reddit 인기 테마 3종(Rose Pine, Gruvbox, Tokyonight)을 포함한 총 14종의 테마를 개발/추가했습니다.

변경 파일:
- `dotfiles/tmux.conf`: 하드코딩된 스타일 제거, active theme 로드 및 Ctrl+a T 단축키 popup 바인딩 추가
- `scripts/tmux-theme-picker`: fzf 실시간 미리보기 및 ctrl-e 기반 테마 복제/편집, non-fzf 번호 선택 fallback이 지원되는 테마 피커 스크립트 추가
- `dotfiles/tmux/themes/`: classic-baseline, open-catppuccin-mocha, open-nord, open-onedark, open-solarized-dark, open-rose-pine, open-gruvbox, open-tokyonight, eye-astigmatism-safe, eye-circadian-warm, eye-scotopic-forest, code-cyberpunk-neon, code-monokai-pro, code-github-light 테마 파일들 추가
- `install.toml`: tmux-theme-picker 디펜던시 모듈 정의 추가
- `install.sh`: after_install_item에 tmux-theme-picker 설치 시 테마 파일들을 ~/.config/tmux/themes/로 자동 복사/다운로드 및 기본 테마 활성화 로직 구현
- `docs/tmux-theme-guide.md`: 로컬 설치 테스트 가이드, 테마 편집 플로우, 시력 보호/코딩/Reddit 인기 테마들의 배경지식과 특징을 설명한 가이드 추가

검증:
- `bash -n install.sh && bash -n scripts/tmux-theme-picker`: OK
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d && kill-server`: OK

후속 주의:
- install.sh를 로컬에서 설치 테스트할 경우 REPO_RAW_URL 환경변수를 file:// 스킴으로 강제 지정하여 실행해야 로컬 수정한 테마 파일들이 복사됩니다. (가이드 문서 참조)

## 2026-07-12 - URxvt keysym: Alt+Shift+Arrow → tmux resize 시퀀스 강제 매핑

요약:
- URxvt는 기본적으로 Shift+Arrow를 텍스트 선택으로 가로채서 tmux에 전달하지 않음
- Alt+Shift+Arrow가 tmux `M-S-*` 바인딩(resize)에 도달하지 않는 문제
- Xresources에 keysym 추가로 `\e[1;4D/C/A/B` 시퀀스를 URxvt가 직접 전송하도록 강제

변경 파일:
- `dotfiles/Xresources`: `M-S-Left/Right/Up/Down` keysym 4개 추가

검증:
- X 세션 안에서 `xrdb -merge ~/.Xresources` 후 URxvt 재시작 필요
- 파일 문법 이상 없음

후속 주의:
- install.sh 실행 후 `xrdb -merge ~/.Xresources` 또는 로그인 재시작 필요
- URxvt 재시작(새 창 열기)해야 keysym이 적용됨

## 2026-07-12 - tmux pane 단축키 PowerShell 맞춤 및 재배치

요약:
- pane 이동을 `Ctrl+Arrow` → `Alt+Arrow`로 변경하여 PowerShell pane 이동 키와 통일
- pane swap/reorder를 `Alt+Arrow` → `Ctrl+Alt+Arrow`로 변경 (충돌 해소)
- pane 크기 조절 `Alt+Shift+Arrow` 새로 추가

변경 파일:
- `dotfiles/tmux.conf`: pane navigation/swap/resize 바인딩 전면 재배치

검증:
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d && kill-server`: OK

후속 주의:
- URxvt 등 터미널에서 `Ctrl+Alt+Arrow`가 다른 기능(예: 데스크탑 workspace 이동)에 묶여 있을 수 있으므로 실제 환경에서 확인 필요

## 2026-06-23 - tmux sidebar animated cursor flicker age refresh fix

요약:
- animated 갱신뿐 아니라 매초 실행되는 age 갱신도 커서를 남길 수 있어서, 그 경로에도 `hide_cursor`를 추가했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: `render_age_cells` 시작 시 `hide_cursor` 추가

검증:
- 아직 별도 자동 검증은 실행하지 않음

후속 주의:
- 여전히 보이면 `render_row` 종료 시점의 커서 위치를 강제로 하단 안전 위치로 옮기는 후속 조치가 필요합니다.

## 2026-06-23 - tmux sidebar animated cursor flicker fix

요약:
- animated 세션 이름 갱신 경로에서 커서가 부분 redraw 뒤에 남아 보이는 문제를 줄이기 위해, 해당 경로에서 커서를 숨기도록 정리했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: animated name cell 갱신과 animation state redraw 시 `hide_cursor` 추가

검증:
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`: 통과

후속 주의:
- full render 경로는 이미 커서를 숨기고 있으므로, 남은 깜빡임이 있으면 부분 redraw가 아니라 tmux focus/cursor 복원 동작을 추가로 봐야 합니다.

## 2026-06-23 - tmux 배경과 활성 배경 교체

요약:
- tmux 테마에서 일반 배경과 활성 배경의 톤을 서로 바꿔, active pane이 더 어두운 배경으로 보이게 조정했습니다.

변경 파일:
- `dotfiles/tmux.conf`: `window-style`와 `window-active-style`의 배경색을 교체

검증:
- 별도 자동 검증은 아직 실행하지 않음

후속 주의:
- pane border와 status bar 색은 그대로라서, 필요하면 다음 작업에서 함께 재조정할 수 있습니다.

## 2026-06-23 - v0.4 release note

요약:
- sidebar fingerprint/state 정리와 cursor blink 관련 리팩토링 항목을 `v0.4` 릴리스 맥락으로 묶었습니다.
- 이번 릴리스는 실제 코드 안정화와 후속 리팩토링 분리를 같이 기록하는 기준점입니다.

변경 파일:
- `HISTORY.md`, `CONVERSATION.md`, `README.md`, `AGENTS.md`: v0.4 릴리스 표기 반영

검증:
- 없음

후속 주의:
- cursor blink는 아직 리팩토링 항목으로 남아 있으며, 별도 커서/포커스 정책 정리가 필요합니다.

## 2026-06-23 - sidebar cursor blink refactor item

요약:
- sidebar animated 상태에서 보이던 불규칙한 커서 blink는 sidebar 렌더만의 문제가 아니라, 포커스된 pane의 cursor 정책이나 tmux redraw 타이밍과 얽힌 리팩토링 항목으로 남겨두기로 했습니다.
- 현재 증상은 sidebar가 포커스일 때는 덜 보이고, active window 쪽에 포커스가 가면 더 잘 보인다는 점에서 pane focus side effect 가능성이 큽니다.

변경 파일:
- `HISTORY.md`, `CONVERSATION.md`: cursor blink를 refactoring 항목으로 기록

검증:
- 없음

후속 주의:
- 실제 수정은 cursor 정책/partial redraw 공통화/tmux focus 시그널 경로를 분리하는 쪽으로 별도 작업이 필요합니다.

## 2026-06-23 - sidebar partial redraw cursor anchor

요약:
- 부분 렌더가 끝난 뒤 커서 위치가 들쭉날쭉 남지 않도록, animated/state 갱신 경로의 종료 위치를 footer 라인으로 고정했습니다.
- 커서 hide만으로 해결되지 않는 경우를 대비한 보완 조치입니다.

변경 파일:
- `scripts/tmux-session-launcher`: partial redraw 종료 후 `move_cursor "$last_height" 1` 추가

검증:
- 아직 미실행

후속 주의:
- 그래도 보이면 실제로는 terminal cursor가 아니라 tmux/pane redraw 타이밍 문제일 수 있습니다.

## 2026-06-23 - sidebar animate cursor blink 완화

요약:
- sidebar의 부분 렌더 경로에서도 커서를 숨기도록 해서, 애니메이션 중에 커서가 불규칙하게 깜빡이는 side effect를 줄였습니다.
- 애니메이션 상태 판정은 건드리지 않고 렌더링만 조정했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: `render_animated_name_cells()`와 `render_animation_state_changes()`에서 `hide_cursor` 보장

검증:
- 아직 미실행

후속 주의:
- 만약 여전히 커서가 보이면, partial redraw 후 안전 위치로 커서를 돌려놓는 후속 정리가 필요할 수 있습니다.

## 2026-06-23 - tmux AI CLI fingerprint/state 최종 정리

요약:
- 실제 원인은 AI CLI fingerprint를 캐시한 상태에서 `waiting` 판정이 stale fingerprint를 기준으로 유지되던 점이었습니다.
- 캐시를 제거한 뒤, 현재는 pane 내용을 직접 읽고 이전 fingerprint와 즉시 비교하는 단순한 경로만 남겼습니다.
- 관련 캐시/refresh 보조 변수도 정리해서, 코드와 실제 동작이 일치하도록 만들었습니다.

변경 파일:
- `scripts/tmux-session-launcher`: fingerprint 캐시 및 refresh 보조 변수 제거, state debug 로그 단순화

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `git diff --check`: 통과
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d && tmux -L codex-dotfiles-test kill-server`: 통과

후속 주의:
- spinner가 fingerprint 본문에 섞이는 경우만 추가로 정규화하면 됩니다.

## 2026-06-23 - tmux AI CLI fingerprint cache 제거

요약:
- fingerprint를 캐시하면 waiting에서 active로 돌아오는 전환이 늦거나 멈출 수 있어서, AI CLI fingerprint를 매번 직접 읽도록 되돌렸습니다.
- 상태 판정은 fingerprint 비교만 유지하고, stale cache는 사용하지 않게 했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: AI CLI fingerprint cached branch 제거

검증:
- 아직 미실행

후속 주의:
- direct fingerprint capture 비용이 늘 수 있지만, 현재 판정 지연보다 우선합니다.

## 2026-06-23 - tmux AI CLI waiting 판정 단순화

요약:
- cached 경로가 `active/animate=true`를 붙잡는 문제를 줄이기 위해, fingerprint가 같으면 무조건 `waiting`으로 내리도록 상태 판정을 단순화했습니다.
- fingerprint 값이 동일한데도 animate가 계속 도는 경로를 막는 쪽으로 조정했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: cached 특례를 제거하고 fingerprint 동일 시 `waiting` 처리

검증:
- 아직 미실행

후속 주의:
- fingerprint 자체가 아직 흔들리면, 여전히 마지막 줄/본문 정규화가 추가로 필요할 수 있습니다.

## 2026-06-23 - tmux AI CLI fingerprint 최소 안정화

요약:
- AI CLI pane의 fingerprint가 spinner 같은 마지막 줄 변화에 끌려다니지 않도록, 마지막 한 줄을 fingerprint 입력에서 제외했습니다.
- 상태 머신은 그대로 두고 fingerprint 입력만 단순화해서 `waiting` 오판을 줄이는 쪽으로 조정했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: `session_ai_fingerprint_for_pane()`에서 마지막 줄을 무시하도록 fingerprint 입력 정리

검증:
- 아직 미실행

후속 주의:
- spinner가 마지막이 아닌 본문 줄에 섞이는 경우는 추가 정규화가 필요할 수 있습니다.

## 2026-06-23 - sidebar fingerprint state debug logs

요약:
- waiting 판정이 왜 바뀌는지 보기 위해, fingerprint 생성 직후와 상태 판정 직후의 debug 로그를 추가했습니다.
- debug 모드에서만 동작하며, fingerprint 값과 상태 전이를 함께 추적할 수 있습니다.

변경 파일:
- `scripts/tmux-session-launcher`: fingerprint / state debug 로그 추가
- `HISTORY.md`, `CONVERSATION.md`: debug logging 맥락 기록

검증:
- 미실행

후속 주의:
- `TMUX_SESSION_LAUNCHER_DEBUG=1`로 실행해 fingerprint와 state 로그를 비교합니다.

## 2026-06-23 - sidebar waiting cache state fix

요약:
- cached fingerprint 구간에서 waiting 상태를 유지하도록 정리했습니다.
- active 상태는 계속 animate 되고, waiting은 cached refresh에서도 멈춘 상태로 남게 했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: cached fingerprint의 state 전이를 단순화
- `HISTORY.md`, `CONVERSATION.md`: waiting cache state 맥락 기록

검증:
- 미실행

후속 주의:
- 실제 tmux에서 waiting 시 애니메이션이 즉시 멈추는지, active 시에는 계속 도는지 확인합니다.

## 2026-06-23 - sidebar cached fingerprint keeps animation

요약:
- AI CLI의 화면 fingerprint가 캐시된 경우에는 기존 animate 상태를 유지하고, fresh capture에서만 waiting 전환을 판단하도록 바꿨습니다.
- active 상태가 있는데도 1회만 animate되거나 바로 멈추는 side effect를 줄이기 위한 조정입니다.

변경 파일:
- `scripts/tmux-session-launcher`: fingerprint source를 `fresh/cached`로 구분하고 cached 구간은 previous animate를 유지
- `HISTORY.md`, `CONVERSATION.md`: cached/fresh 구분 맥락 기록

검증:
- 미실행

후속 주의:
- 실제 tmux에서 AI CLI가 active일 때는 animate가 유지되고, fresh capture에서 동일 fingerprint면 waiting으로 멈추는지 확인합니다.

## 2026-06-22 - sidebar previous fingerprint compare fix

요약:
- `waiting` 전환 기준을 현재 fingerprint가 아니라 이전 fingerprint와 비교하도록 고쳐서, 애니메이션이 아예 안 도는 문제를 해결했습니다.
- fingerprint를 상태 함수 안에서 갱신하는 구조와 비교 위치가 충돌하던 버그였습니다.

변경 파일:
- `scripts/tmux-session-launcher`: 이전 fingerprint를 먼저 저장한 뒤 animate 여부 비교
- `HISTORY.md`, `CONVERSATION.md`: compare fix 맥락 기록

검증:
- `bash -n scripts/tmux-session-launcher`
- `git diff --check`

후속 주의:
- 실제 tmux에서 AI CLI가 active일 때만 animate가 켜지고, fingerprint가 같아지면 waiting으로 내려가는지 확인합니다.

## 2026-06-22 - sidebar waiting stops animation

요약:
- AI pane이 조용해져 `waiting`으로 떨어지면 애니메이션도 멈추도록 바꿨습니다.
- `active` 상태에서만 animate를 유지해, 상태 변화가 없는데도 계속 흐르는 문제를 줄였습니다.

변경 파일:
- `scripts/tmux-session-launcher`: `waiting` 시 animate=false로 전환
- `HISTORY.md`, `CONVERSATION.md`: 상태-애니메이션 분리 맥락 기록

검증:
- 미실행

후속 주의:
- 실제 tmux에서 `active -> waiting` 전환 시 애니메이션이 즉시 멈추는지 확인합니다.

## 2026-06-22 - tmux color theme refactor note

요약:
- 현재 색상 결정은 시력 친화적인 검정 계열과 active focus 구분에 맞춰 유지하되, 나중에 theme를 바꾸기 쉽게 분리 포인트만 기록해 두었습니다.
- 실제 style 값은 그대로 두고, window/background/border/path 강조를 theme token 후보로 볼 수 있게 정리했습니다.

변경 파일:
- `HISTORY.md`, `CONVERSATION.md`: theme refactor 메모 추가

검증:
- 미실행

후속 주의:
- 다음 theme 작업에서는 `window-style`, `window-active-style`, `pane-border-format` 색을 한 곳에서만 바꿀 수 있도록 토큰화를 검토합니다.

## 2026-06-22 - tmux active pane path format fix

요약:
- 활성 pane 경로를 강조하려던 format 문자열에서 style 문법이 잘못 섞여 literal `bold]`가 보이던 문제를 수정했습니다.
- `fg`와 `bold`를 분리하고, 활성/비활성 분기를 명시적으로 다시 구성했습니다.

변경 파일:
- `dotfiles/tmux.conf`: `pane-border-format` 조건 스타일을 분리된 스타일 escape로 수정
- `HISTORY.md`, `CONVERSATION.md`: format 수정 맥락 기록

검증:
- 미실행

후속 주의:
- 실제 tmux에서 활성 pane의 경로가 제대로 표시되는지 확인합니다.

## 2026-06-22 - tmux active pane path emphasis

요약:
- 활성 pane의 경로만 더 진한 폰트와 밝은 색으로 보이게 해서, focus 위치가 더 쉽게 읽히도록 했습니다.
- 배경과 border는 그대로 두고 pane border text만 조건 스타일로 강조했습니다.

변경 파일:
- `dotfiles/tmux.conf`: `pane-border-format`에 `pane_active` 조건 스타일 추가
- `HISTORY.md`, `CONVERSATION.md`: path text emphasis 맥락 기록

검증:
- 미실행

후속 주의:
- 실제 tmux에서 활성 pane의 경로만 잘 강조되는지, 비활성 pane이 너무 흐려 보이지 않는지 확인합니다.

## 2026-06-22 - tmux active border raised slightly

요약:
- 활성 window 배경과 border를 아주 조금만 올려, focus가 더 쉽게 잡히도록 조정했습니다.
- 비활성 배경은 그대로 유지해 전체 톤은 크게 흔들지 않았습니다.

변경 파일:
- `dotfiles/tmux.conf`: active window background와 active border tone 소폭 상향
- `HISTORY.md`, `CONVERSATION.md`: focus border 조정 맥락 기록

검증:
- 미실행

후속 주의:
- 실제 tmux에서 border가 너무 튀지 않는지 확인합니다.

## 2026-06-22 - tmux active background nudged lower

요약:
- 활성 window 배경을 한 단계 더 낮춰, 비활성 배경과의 차등을 아주 조금 더 줄였습니다.
- focus 구분은 유지하되, 가능한 한 부드러운 톤으로 맞췄습니다.

변경 파일:
- `dotfiles/tmux.conf`: active window background를 더 어두운 톤으로 소폭 조정
- `HISTORY.md`, `CONVERSATION.md`: 미세 조정 맥락 기록

검증:
- 미실행

후속 주의:
- 실제 tmux에서 focus가 여전히 읽히는지 확인합니다.

## 2026-06-22 - tmux active background lowered

요약:
- 비활성 window 배경은 `#0b0d0e`로 고정하고, 활성 window 배경만 더 낮춰 차등을 줄였습니다.
- focus는 유지하되, 시각적 자극이 덜한 중간값에 가깝게 다시 맞췄습니다.

변경 파일:
- `dotfiles/tmux.conf`: active window background 및 active border 배경을 더 낮은 톤으로 조정
- `HISTORY.md`, `CONVERSATION.md`: active background 조정 맥락 기록

검증:
- 미실행

후속 주의:
- 실제 tmux에서 차등이 너무 약해지지 않았는지 확인합니다.

## 2026-06-22 - tmux focus contrast nudged down

요약:
- 현재 차등은 괜찮지만 조금 더 부드럽게 만들기 위해 비활성 배경만 한 단계 올렸습니다.
- 활성 배경은 유지해서 focus는 그대로 읽히되, 대비 자극만 아주 미세하게 줄였습니다.

변경 파일:
- `dotfiles/tmux.conf`: inactive window background를 한 단계 올려 contrast 소폭 완화
- `HISTORY.md`, `CONVERSATION.md`: 미세 대비 조정 맥락 기록

검증:
- 미실행

후속 주의:
- 실제 tmux에서 차등이 너무 약해지지 않았는지 확인합니다.

## 2026-06-22 - tmux focus contrast reduced

요약:
- 직전 변경은 대비가 너무 커서 눈에 거슬린다는 피드백을 반영해, active/inactive 차등을 중간 정도로 낮췄습니다.
- 배경은 검정 계열을 유지하면서도 focus는 여전히 구분될 정도의 최소 차이만 남겼습니다.

변경 파일:
- `dotfiles/tmux.conf`: active/inactive window background contrast 완화
- `HISTORY.md`, `CONVERSATION.md`: 대비 완화 맥락 기록

검증:
- 미실행

후속 주의:
- 실제 tmux에서 차등이 충분히 약해졌는지, 동시에 focus는 읽히는지 확인합니다.

## 2026-06-22 - tmux focus contrast widened

요약:
- focus 구분이 아직 약하다는 피드백에 따라, 비활성 배경을 더 눌러서 활성 배경과의 차이를 다시 벌렸습니다.
- 시력 부담은 검정 계열 안에서 유지하되, active window와 inactive window의 경계가 더 쉽게 읽히도록 조정했습니다.

변경 파일:
- `dotfiles/tmux.conf`: active/inactive window background contrast 강화
- `HISTORY.md`, `CONVERSATION.md`: 대비 조정 맥락 기록

검증:
- 미실행

후속 주의:
- 실제 tmux에서 contrast가 충분한지, 그리고 과하게 튀지 않는지 확인합니다.

## 2026-06-22 - tmux inactive background slightly darker

요약:
- 시력 부담을 줄이면서 focus 영역은 쉽게 구분되도록, 비활성 window 배경만 아주 조금 더 어둡게 내렸습니다.
- 활성 영역은 기존의 아주 약한 cool tint를 유지해 배경 대비로만 focus가 읽히게 했습니다.

변경 파일:
- `dotfiles/tmux.conf`: inactive window background를 소폭 어둡게 조정
- `HISTORY.md`, `CONVERSATION.md`: focus 가독성 조정 맥락 기록

검증:
- 미실행

후속 주의:
- 실제 tmux에서 배경 대비가 편안하면서도 focus가 잘 보이는지 확인합니다.

## 2026-06-22 - tmux focus tint 축소

요약:
- 직전의 focus tint는 border 대비가 조금 과해서 눈에 덜 편하다는 피드백을 반영해 되돌렸습니다.
- 최종적으로는 active window 배경만 아주 미세하게 다르게 두고, pane border는 원래 톤으로 복구했습니다.

변경 파일:
- `dotfiles/tmux.conf`: active window만 약하게 구분하고 border tone은 원복
- `HISTORY.md`, `CONVERSATION.md`: focus tint 축소 맥락 기록

검증:
- 미실행

후속 주의:
- 실제 tmux에서 배경 차이만으로 focus가 충분히 읽히는지 확인합니다.

## 2026-06-22 - tmux focus tint 강화

요약:
- pane 본문을 직접 칠할 수는 없어서, active window tint와 active border 대비를 조금 더 올려 focus 위치가 눈에 더 잘 들어오게 조정했습니다.
- 전체 배경은 검정에 가깝게 유지하고, 활성 영역만 아주 옅은 cool charcoal로 구분하도록 했습니다.

변경 파일:
- `dotfiles/tmux.conf`: active window tint와 active border tone 강화, pane body 제약 주석 추가
- `HISTORY.md`, `CONVERSATION.md`: focus 가시성 조정 맥락 기록

검증:
- 미실행

후속 주의:
- 실제 tmux에서 배경 틴트가 과하지 않은지, 그리고 focus 구분이 더 잘 느껴지는지 확인합니다.

## 2026-06-22 - sidebar refactor candidate note

요약:
- 현재 sidebar 멈칫은 `collect_sessions`의 세션별 반복 계산 구조에서 주로 나오며, 단순 미세 최적화만으로는 한계가 있음을 확인했습니다.
- 다음 단계 후보로는 collector/renderer 분리, snapshot 기반 갱신, CQRS-style 구조 전환을 검토해야 합니다.

변경 파일:
- `HISTORY.md`, `CONVERSATION.md`: 구조 개선 후보 메모 추가

검증:
- 미실행

후속 주의:
- 현재 상태는 보존하고, 구조 개선은 별도 작업으로 분리합니다.

## 2026-06-22 - tmux active window cool tint

요약:
- 검정 기반 배경에서 집중 창을 아주 약한 cool charcoal로만 띄우는 방향을 적용했습니다.
- tmux의 pane body 제약 때문에 active window와 border style에만 최소한의 색 변화를 넣었습니다.

변경 파일:
- `dotfiles/tmux.conf`: window active/background tint와 border tone 추가
- `HISTORY.md`, `CONVERSATION.md`: 색 후보 및 적용 기준 기록

검증:
- 미실행

후속 주의:
- 실제 tmux에서 검정 대비가 과하지 않고, focus가 자연스럽게 느껴지는지 확인합니다.

## 2026-06-22 - sidebar animation left-to-right smoothing

요약:
- sidebar 세션명 애니메이션의 흐름 방향을 왼쪽에서 오른쪽으로 맞추고, 옅은 회색 바탕 위에 좁은 흰색 하이라이트가 지나가도록 조정했습니다.
- 세션별 seed는 유지해서 row 간 독립성은 그대로 두되, 프레임당 변화가 더 연속적으로 보이도록 하고, 하이라이트 폭만 좁혀 자연스럽게 보이도록 했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: phase 계산 반전, 좁은 white highlight + light gray base 적용, animation frame 주기 확장
- `HISTORY.md`, `CONVERSATION.md`: 수정 맥락 기록

검증:
- 미실행

후속 주의:
- 실제 tmux에서 좌->우 흐름이 자연스럽고, 옅은 회색 바탕 위에 흰색 하이라이트가 자연스럽게 흐르는지 확인합니다.

## 2026-06-22 - sidebar hotspot timing instrumentation

요약:
- 5초 주기 미세 멈칫의 원인을 좁히기 위해, debug 모드에서만 핵심 hotspot의 타이밍을 기록하도록 계측을 넣었습니다.
- `collect_sessions` 안의 `list-sessions`, `list-panes`, per-session `display-message`, `capture-pane`, `pgrep` 비용을 분리해서 볼 수 있게 했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: debug 전용 timing helper와 hotspot 계측 추가
- `HISTORY.md`, `CONVERSATION.md`: 분석용 계측 맥락 기록

검증:
- 미실행

후속 주의:
- debug 로그로 실제 병목을 확인한 뒤에, side effect 없는 축소안을 적용합니다.

## 2026-06-22 - sidebar stdout parse 제거

요약:
- hot path에서 `session_cli_state_for_session`의 stdout 결과를 다시 파싱하던 부분을 없애고, scratch 변수에 결과를 채우는 방식으로 바꿨습니다.
- 내부 결과 전달은 그대로 유지하면서 command substitution과 read 파싱 비용을 줄였습니다.

변경 파일:
- `scripts/tmux-session-launcher`: `session_cli_state_for_session` 결과 전달 방식 변경, hot path 주석 추가
- `HISTORY.md`, `CONVERSATION.md`: 수정 맥락 기록

검증:
- 미실행

후속 주의:
- debug timing으로 parse-sessions 구간이 실제로 줄었는지 다시 확인합니다.

## 2026-06-22 - sidebar AI fingerprint 캐시 연장

요약:
- 3초 주기 상태 갱신 때마다 AI fingerprint를 다시 뜯어보지 않도록 캐시 유효 시간을 늘렸습니다.
- direct AI pane은 activity freshness와 분리해 계속 animate 되고, probe로 발견한 pane도 direct 경로로 승격해 반복 탐색을 줄였습니다.
- background gray를 한 단계 더 어둡게 내려서 대비를 조금만 강화했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: AI fingerprint refresh TTL 추가, direct/probe AI pane 판정 완화, background gray 조정
- `HISTORY.md`, `CONVERSATION.md`: 수정 맥락 기록

검증:
- 미실행

후속 주의:
- 실제 tmux에서 3초 주기 멈칫이 줄었는지, animate가 계속 자연스럽게 유지되는지 확인합니다.

## 2026-06-22 - sidebar animation tick 가속

요약:
- 애니메이션이 조금 더 빠르게 흐르도록 tick 간격을 줄이고, 프레임 진행폭을 키웠습니다.
- 상태 갱신 주기는 조금 더 느리게 해서 반복적인 refresh 체감이 덜하도록 조정했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: poll timeout 축소, animation frame step 확대, state refresh cadence 완화
- `HISTORY.md`, `CONVERSATION.md`: 수정 맥락 기록

검증:
- 미실행

후속 주의:
- 실제 tmux에서 속도가 원하는 수준인지, refresh side effect가 없는지 확인합니다.

## 2026-06-22 - sidebar epoch builtin 최적화

요약:
- 루프와 상태 갱신 경로에서 반복되던 외부 `date +%s` 호출을 bash epoch builtin 우선 사용으로 바꿔, 동작은 유지하면서 갱신 비용을 더 낮췄습니다.
- 애니메이션 진행폭은 요청대로 다시 `+1`로 유지했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: epoch builtin helper 추가, hot path의 epoch 조회를 builtin 우선으로 변경, animation frame step 원복
- `HISTORY.md`, `CONVERSATION.md`: 수정 맥락 기록

검증:
- 미실행

후속 주의:
- 실제 tmux에서 5초 주기 멈칫이 줄었는지 확인합니다.

## 2026-06-22 - sidebar state snapshot 단순화

요약:
- sidebar의 무거운 느낌을 줄이기 위해 세션별 `list-panes -a` 반복 호출을 없애고, 1회 pane snapshot으로 busy/AI 판정을 처리하도록 바꿨습니다.
- 오래된 session은 AI probe를 바로 건너뛰어 불필요한 `pgrep`와 `capture-pane`를 줄였습니다.

변경 파일:
- `scripts/tmux-session-launcher`: pane snapshot 캐시, activity age 캐시, stale session early exit 추가
- `HISTORY.md`, `CONVERSATION.md`: 성능 개선 맥락 기록

검증:
- `bash -n scripts/tmux-session-launcher`
- `git diff --check`

후속 주의:
- 실제 tmux에서 멈칫 구간과 체감 무게가 줄었는지 확인합니다.

## 2026-06-22 - sidebar animate 지속성 복구

요약:
- AI pane이 조용해지면 animate가 멈추는 버그를 완화하기 위해, animation lifetime을 activity freshness와 분리했습니다.
- AI fingerprint 재조회도 짧게 캐시해서 capture-pane 빈도를 낮췄습니다.

변경 파일:
- `scripts/tmux-session-launcher`: direct AI pane는 activity age와 분리해 animate 유지, fingerprint 체크 타임스탬프 캐시 추가
- `HISTORY.md`, `CONVERSATION.md`: 수정 맥락 기록

검증:
- `bash -n scripts/tmux-session-launcher`
- `git diff --check`

후속 주의:
- 실제 tmux에서 AI pane이 잠잠한 동안에도 animate가 계속 도는지 확인합니다.

## 2026-06-22 - sidebar refresh cadence 완화

요약:
- sidebar가 약 1초 주기로 멈칫하던 체감을 줄이기 위해 상태 수집을 별도 cadence로 늦췄습니다.
- 배경 회색도 조금 더 어둡게 내려서, 옅은 highlight가 더 또렷하게 보이도록 했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: state refresh를 3초 cadence로 분리, base gray를 더 어둡게 조정
- `HISTORY.md`, `CONVERSATION.md`: 수정 맥락 기록

검증:
- 미실행

후속 주의:
- 1초 경계의 멈칫이 줄었는지, 그리고 새 cadence가 status freshness에 너무 큰 지연을 만들지 확인합니다.

## 2026-06-22 - sidebar animation row refresh 분리

요약:
- sidebar의 AI 상태 변화가 전체 `render_full`를 부르는 경로를 줄이고, 세션별 seed로 name animation phase를 독립화했습니다.
- 애니메이션은 유지하되, 상태가 바뀐 row만 다시 그리도록 분리해서 전체 위에서 아래로의 refresh를 억제했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: 세션별 animation seed 추가, snapshot signature 경량화, 애니메이션 상태 변화는 row 단위 repaint로 처리
- `HISTORY.md`, `CONVERSATION.md`: 수정 맥락 기록

검증:
- `bash -n scripts/tmux-session-launcher`
- `git diff --check`
- `tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d`
- `tmux -L codex-dotfiles-test kill-server`

후속 주의:
- active/waiting 전환이 많은 세션에서 row 단위 repaint와 독립 phase가 충분히 자연스러운지 실제 tmux에서 확인합니다.

## 2026-06-22 - sidebar 애니메이션 refresh flicker 완화

요약:
- sidebar 세션명 애니메이션이 여러 개 동시에 움직일 때, 애니메이션 프레임 변화가 전체 `render_full`를 유발해 화면이 깜빡이는 문제를 줄였습니다.
- 애니메이션 상태는 유지하되, 스냅샷 서명에서는 프레임 관련 값을 제외해 상태 변화가 아닐 때는 부분 repaint만 일어나도록 바꿨습니다.

변경 파일:
- `scripts/tmux-session-launcher`: 애니메이션 프레임을 snapshot signature에서 제외
- `HISTORY.md`, `CONVERSATION.md`: 수정 맥락 기록

검증:
- 미실행

후속 주의:
- 실제 tmux sidebar에서 여러 busy/active 세션이 동시에 애니메이션될 때 전체 화면 깜빡임이 줄었는지 확인합니다.

## 2026-06-21 - delete 경로 디버그 로그 추가

요약:
- sidebar에서 세션 삭제 시 `server exited unexpectedly`가 왜 발생하는지 확인하기 위해 delete 경로에 디버그 로그를 추가했습니다.
- 현재 client session, target session의 client 보유 여부, fallback session, kill-server 진입 여부를 남기도록 했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: delete_session_after_archive와 tui_delete_session에 debug_log 추가
- `HISTORY.md`, `CONVERSATION.md`: 디버그 작업 맥락 기록

검증:
- `bash -n scripts/tmux-session-launcher`
- `git diff --check`

후속 주의:
- 다음 재현에서 `/tmp/tmux-session-launcher-debug.log` 또는 `TMUX_SESSION_LAUNCHER_DEBUG_FILE`로 실제 분기값을 확인합니다.

## 2026-06-21 - delete y 경로 진입점 추가 로그

요약:
- `delete -> y`에서 로그가 비는 현상을 좁히기 위해, `run_session_delete` 호출 전후와 `main` 시작/종료까지 디버그 로그를 추가했습니다.
- backend 이전에 launcher가 끊기는지, backend 호출 후에 끊기는지 구분하려는 목적입니다.

변경 파일:
- `scripts/tmux-session-launcher`: main/run_session_delete/tui_delete_session에 debug_log 추가
- `HISTORY.md`, `CONVERSATION.md`: 디버그 범위 확장 기록

검증:
- `bash -n scripts/tmux-session-launcher`
- `git diff --check`

후속 주의:
- 다음 재현에서는 `main start`, `before run_session_delete`, `after run_session_delete`가 실제로 남는지 확인합니다.

## 2026-06-21 - delete 후 render 경로 로그 추가

요약:
- `delete -> Enter`에서 backend 이후 UI 재렌더까지 실제로 진행되는지 확인하려고 `collect_sessions`, `render_full`, delete case 전후 로그를 추가했습니다.
- delete backend가 아니라 후속 UI 갱신 구간에서 상태가 꼬이는지 분리하기 위한 조치입니다.

변경 파일:
- `scripts/tmux-session-launcher`: collect_sessions/render_full/main delete case에 debug_log 추가
- `HISTORY.md`, `CONVERSATION.md`: 추적 범위 확장 기록

검증:
- `bash -n scripts/tmux-session-launcher`
- `git diff --check`

후속 주의:
- 다음 재현에서 delete 후 `collect_sessions end`와 `render_full end`가 찍히는지 확인합니다.

## 2026-06-21 - delete 후 wait와 snapshot 조회로 레이스 완화

요약:
- `delete -> Enter` 경로에서 backend가 세션을 지우는 동안 UI가 즉시 재렌더되며 상태가 꼬이는 문제를 완화했습니다.
- 삭제 대상 세션이 사라질 때까지 짧게 기다린 뒤 `collect_sessions`를 다시 돌리도록 했고, 세션 목록 조회도 스냅샷 기반으로 바꿨습니다.

변경 파일:
- `scripts/tmux-session-launcher`: wait_for_session_absence 추가, delete 경로 대기, collect_sessions 스냅샷화
- `HISTORY.md`, `CONVERSATION.md`: 근본 수정 맥락 기록

검증:
- `bash -n scripts/tmux-session-launcher`
- `git diff --check`

후속 주의:
- 다음 재현에서 `delete -> Enter`가 더 이상 `collect_sessions` 중간 종료를 만들지 확인합니다.

## 2026-06-21 - sidebar split reopen를 work pane에 고정

요약:
- sidebar가 있는 상태에서 split할 때 sidebar를 다시 붙이는 기준을 window 전체가 아니라 실제 target work pane으로 고정했습니다.
- split 직후 sidebar가 사라지거나 다른 pane에 붙는 현상을 줄이기 위한 변경입니다.

변경 파일:
- `scripts/tmux-session-launcher`: split_work_pane에서 open_sidebar 대상 pane을 target work pane으로 고정
- `HISTORY.md`, `CONVERSATION.md`: split 재부착 경로 기록

검증:
- `bash -n scripts/tmux-session-launcher`
- `git diff --check`

후속 주의:
- sidebar가 있는 상태에서 연속 split 시 sidebar가 유지되는지 다시 확인합니다.

## 2026-06-21 - sidebar split의 work pane 복귀 기준 수정

요약:
- sidebar가 켜진 상태에서 split을 반복할 때 work pane 탐지가 불안정한 문제를 줄이기 위해, sidebar에서 복귀할 때 `select-pane -R` 대신 `select-pane -l`을 우선 사용하도록 바꿨습니다.
- 마지막으로 활성화된 work pane을 기준으로 돌아가게 해서, 레이아웃 변화에 덜 흔들리도록 했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: select_work_pane_from_sidebar 복귀 기준 변경
- `HISTORY.md`, `CONVERSATION.md`: split bug 분석 기록

검증:
- `bash -n scripts/tmux-session-launcher`
- `git diff --check`

후속 주의:
- sidebar가 있는 상태에서 연속 split을 다시 재현해, `No work pane found for split.`가 사라지는지 확인합니다.

## 2026-06-21 - sidebar split의 work pane 대상 직접 선택

요약:
- sidebar가 있는 상태에서 split할 때 current pane 상태에 기대지 않고, 현재 window의 실제 work pane을 직접 찾아 그 pane을 split 대상으로 삼도록 바꿨습니다.
- `select-pane -l` 기반 복귀가 충분하지 않았던 문제를 구조적으로 줄이기 위한 수정입니다.

변경 파일:
- `scripts/tmux-session-launcher`: current_window_work_pane 추가 및 split_work_pane 타깃 명시화
- `HISTORY.md`, `CONVERSATION.md`: split 재설계 기록

검증:
- `bash -n scripts/tmux-session-launcher`
- `git diff --check`

후속 주의:
- sidebar가 있는 상태에서 첫 split 이후 `%`가 남는지, 두 번째 split이 정상 동작하는지 다시 확인합니다.

## 2026-06-21 - sidebar session delete handoff 보강

요약:
- sidebar에서 새 세션을 만든 뒤 그 세션을 delete할 때, 삭제 대상 세션에 client가 붙어 있으면 backend가 먼저 fallback 세션으로 handoff하도록 보강했습니다.
- delete가 현재 세션인지 여부만 보던 조건을 넓혀, tmux가 실제로 target session에 client를 들고 있는 경우도 보호합니다.
- archive/delete 백엔드가 세션 종료와 함께 끊기면서 shell 오류로 번지는 경로를 줄이기 위한 방어선입니다.

변경 파일:
- `scripts/tmux-session-launcher`: delete_session_after_archive client handoff 조건 강화
- `HISTORY.md`, `CONVERSATION.md`: 변경 기록 추가

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `git diff --check`: 통과
- mock tmux 환경에서 target session client 존재 시 `switch-client -t =base` 후 `kill-session -t =new` 순서 확인

후속 주의:
- 실제 attached tmux 세션에서 한 번 더 재현 확인이 필요합니다.

## 2026-06-21 - sidebar 현재 세션 삭제 시 client 선전환 수정

요약:
- sidebar에서 새 세션을 만들고 그 세션을 삭제할 때, 삭제 대상이 현재 붙어 있는 세션이면 먼저 fallback 세션으로 client를 옮기도록 바꿨습니다.
- 기존 백그라운드 delete는 현재 세션 안에서 돌다가 끊길 수 있어서, 현재 세션을 먼저 비우고 나서 kill-session 하도록 순서를 조정했습니다.
- 다른 세션이 있을 때 current session delete가 shell을 같이 흔드는 경로를 줄입니다.

변경 파일:
- `scripts/tmux-session-launcher`: current session delete 시 fallback session으로 선전환 후 delete enqueue
- `HISTORY.md`, `CONVERSATION.md`: 변경 기록 추가

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `git diff --check`: 통과
- mock tmux 환경에서 current session delete 시 `switch-client -t =new` 후 `RUN:old true` 순서 확인

후속 주의:
- All delete는 기존처럼 전체 server 종료 경로를 유지합니다.

## 2026-06-21 - codex/gemini AI CLI descendant 탐지 보강

요약:
- `codex`와 `gemini`가 tmux에서 `node` wrapper를 거쳐 실행되면서 direct child argv만으로는 AI pane으로 놓치던 문제를 보강했습니다.
- pane의 직접 자식과 그 자식 한 단계 아래까지 `pgrep`로 확인해 `codex`, `gemini` 실행 흔적을 잡도록 바꿨습니다.
- 이후 `codex`와 `gemini`도 `active -> waiting` 전환이 확인됐습니다.

변경 파일:
- `scripts/tmux-session-launcher`: descendant process 탐지 regex를 path-aware로 보강
- `HISTORY.md`, `CONVERSATION.md`: 변경 기록 추가

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `git diff --check`: 통과
- 실제 tmux에서 `codex`: `CODEX1:active`, `CODEX2:waiting` 확인
- 실제 tmux에서 `gemini`: `GEMINI1:active`, `GEMINI2:waiting` 확인

후속 주의:
- `waiting`은 여전히 screen snapshot 기반 휴리스틱이며, CLI별 hook이 생기면 더 정확한 상태로 대체할 수 있습니다.

## 2026-06-21 - codex/claude AI CLI 판정 보강

요약:
- `codex`가 tmux에서 `node`로만 보이는 경우가 있어, `pane_current_command`만으로는 AI pane으로 잡히지 않는 문제를 보강했습니다.
- pane의 직접 자식 프로세스 argv를 확인해 `codex`, `claude`, `gemini`, `opencode`, `ollama` 실행 흔적을 잡도록 했습니다.
- `opencode`/`ollama`는 기존처럼 동작하고, `codex`/`claude`도 AI pane으로 들어와 active/waiting 판정에 합류합니다.

변경 파일:
- `scripts/tmux-session-launcher`: pane child process argv 기반 AI pane 탐지 추가
- `HISTORY.md`, `CONVERSATION.md`: 변경 기록 추가

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `git diff --check`: 통과
- 실제 tmux에서 `codex` 실행 후 `session_cli_state[0] = active` 확인
- 실제 tmux에서 `claude` 실행 후 `session_cli_state[0] = active` 확인

후속 주의:
- `codex`/`claude`의 waiting은 화면 스냅샷 변화에 여전히 의존한다.

## 2026-06-21 - AI CLI waiting을 screen hash로 실용화

요약:
- AI CLI가 pane에 붙어 있지만 화면 변화가 거의 없는 상태를 `waiting`으로 보기 위해, AI pane 전용 `capture-pane` 해시 비교를 넣었습니다.
- blank line을 제거한 최근 화면 조각만 해시하고, 연속 동일한 스냅샷이 잡히면 `waiting`으로 내립니다.
- `active`는 화면이 달라질 때 유지하고, `idle`은 기존 non-AI fallback과 shell-only 판정에 남깁니다.

변경 파일:
- `scripts/tmux-session-launcher`: AI pane fingerprint helper, consecutive snapshot based waiting 판정 추가
- `HISTORY.md`, `CONVERSATION.md`: 변경 기록 추가

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `git diff --check`: 통과
- mock `tmux` 환경에서 `active -> waiting` 전환 확인
- 실제 `opencode` 세션에서 `FIRST:active`, `SECOND:active`, `THIRD:waiting` 확인

후속 주의:
- `waiting`은 여전히 휴리스틱이며, CLI별 hook이 있으면 나중에 더 정확한 상태로 대체할 수 있습니다.

## 2026-06-21 - AI CLI 종료 후 active 잔류 수정

요약:
- `opencode`를 종료한 뒤에도 sidebar가 계속 active처럼 남는 경로를 좁혔습니다.
- AI CLI가 실제로 pane에 붙어 있을 때만 `active/waiting`을 쓰고, 종료 후 shell prompt로 돌아온 세션은 기존 `busy/idle` 휴리스틱으로 다시 판단합니다.
- shell-only pane은 idle로 떨어지고, non-AI work pane은 기존 busy 판정을 유지합니다.

변경 파일:
- `scripts/tmux-session-launcher`: AI CLI adapter가 non-AI fallback을 `session_is_busy`로 바꾸도록 수정
- `HISTORY.md`, `CONVERSATION.md`: 변경 기록 추가

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `git diff --check`: 통과
- mock `tmux` 환경에서 `codex` live: `active`
- mock `tmux` 환경에서 `codex` 오래된 activity: `waiting`
- mock `tmux` 환경에서 shell-only: `idle`
- mock `tmux` 환경에서 non-shell work command: `active`

후속 주의:
- `waiting`은 아직 CLI별 hook이 없어서 session activity 기반 휴리스틱이다.

## 2026-06-21 - AI CLI status adapter 초안 반영

요약:
- sidebar 애니메이션 대상 판정을 AI CLI status adapter로 분리했습니다.
- `codex`, `claude`, `gemini`, `opencode`, `ollama`를 known AI CLI command로 취급하고, active/waiting/idle 상태를 얇게 분리했습니다.
- active 세션만 sweep 애니메이션을 유지하고, passive shell/monitoring command는 기존 idle 경로를 유지합니다.

변경 파일:
- `scripts/tmux-session-launcher`: AI CLI command registry, session activity age helper, session CLI state adapter 추가
- `HISTORY.md`, `CONVERSATION.md`: 계획과 검증 기록 추가

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `git diff --check`: 통과
- mock `tmux` 환경에서 `session_cli_state_for_session ai`: `active`, `waiting` 확인
- mock `tmux` 환경에서 shell command 세션: `idle` 확인
- `bash -lc 'tmux(){ ... }; source <(head -n -1 scripts/tmux-session-launcher); ...'`: tmux 로드 확인

후속 주의:
- 현재 adapter는 command name과 session activity만 보는 얕은 휴리스틱입니다.
- Claude Code의 hook 이벤트처럼 더 정교한 상태 전이는 나중에 별도 확장으로 붙일 수 있습니다.

## 2026-06-21 - sidebar 애니메이션 갱신 주기 분리

요약:
- sidebar 애니메이션을 더 짧은 poll 주기로 돌리고, age 갱신과 분리해 더 부드럽게 보이도록 조정했습니다.
- 기존 1초 단위 age refresh는 유지하고, sweep frame은 별도 갱신으로 돌립니다.
- poll 기본값은 `0.12s`로 두었습니다.

변경 파일:
- `scripts/tmux-session-launcher`: sidebar poll timeout 추가, age refresh와 animation repaint 분리
- `HISTORY.md`, `CONVERSATION.md`: 변경 기록 추가

검증:
- `bash -n scripts/tmux-session-launcher`: 예정

후속 주의:
- `TMUX_SESSION_SIDEBAR_POLL_TIMEOUT`으로 poll 주기를 조절할 수 있습니다.

## 2026-06-21 - sidebar sweep 색상 톤 조정

요약:
- sidebar 세션명 sweep 색감을 하늘색 계열에서 흰색-회색 계열로 바꿨습니다.
- Codex 느낌에 맞춰 장식성보다 텍스트 강조감을 더 남기는 팔레트로 정리했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: gradient sweep 팔레트를 grayscale로 조정
- `HISTORY.md`, `CONVERSATION.md`: 변경 기록 추가

검증:
- `bash -n scripts/tmux-session-launcher`: 예정

후속 주의:
- 상태 판정 로직은 유지하고 색상만 바꿨습니다.

## 2026-06-21 - sidebar 애니메이션 깜빡임과 대상 판정 수정

요약:
- v0.3 sidebar 애니메이션이 visible row 전체를 반복 repaint해 깜빡이던 문제를 줄였습니다.
- sweep 대상 판정을 session-wide busy가 아니라 session 안의 work pane 기준으로 분리했습니다.
- `top`, `btop`, `htop`, `watch` 같은 모니터링 command는 foreground여도 sweep 대상에서 제외했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: active work pane 판정, 세션명 cell 부분 repaint, passive command 제외 추가
- `HISTORY.md`, `CONVERSATION.md`: 변경 기록 추가

검증:
- `bash -n install.sh`: 통과
- `bash -n scripts/tmux-session-launcher`: 통과
- `perl -c dotfiles/urxvt/ext/resize-font`: 통과
- `sh -n get_dotfiles.sh`: 통과
- `sh -n install_dotfiles.sh`: 통과
- `git diff --check`: 통과
- tmux 설정 로딩 검증: 통과
- isolated tmux에서 focus가 다른 세션으로 이동한 상태에서도 `sleep` 실행 세션은 animate=true 확인
- isolated tmux에서 shell-only 세션은 animate=false 확인
- isolated tmux에서 `top` 실행 세션은 animate=false 확인

후속 주의:
- ai-cli의 yes/no 입력 대기 같은 앱별 상태 판정은 아직 별도 어댑터가 필요합니다.
- focus와 무관하게 session 내부에서 work command가 살아 있으면 sweep 대상이 됩니다.

## 2026-06-21 - sidebar busy session name 애니메이션 추가

요약:
- sidebar 세션 목록에서 `busy` 상태인 세션명에 왼쪽에서 오른쪽으로 흐르는 ANSI gradient sweep 효과를 추가했습니다.
- 애니메이션은 sidebar row의 세션명에만 적용하고, idle 세션은 기존 표시를 유지합니다.

변경 파일:
- `scripts/tmux-session-launcher`: busy 세션명 ANSI gradient 출력과 짧은 row repaint 추가
- `HISTORY.md`, `CONVERSATION.md`: 변경 기록 추가

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- `git diff --check`: 통과
- isolated tmux context에서 busy 세션명 ANSI 출력, idle 세션명 plain 출력 확인

후속 주의:
- `TMUX_SESSION_SIDEBAR_ANIMATION_ENABLED=false`로 애니메이션을 끌 수 있습니다.
- busy 판정은 기존 `session_is_busy` 휴리스틱을 그대로 사용합니다.

## 2026-06-21 - sidebar open 단축키와 delete 문구 조정

요약:
- sidebar의 history 모드를 `o` 단축키로 열도록 바꾸고, 표시 문자열도 `open:`으로 맞췄습니다.
- `delete -> All` 경로의 확인 문구를 `Save Session?`으로 변경했습니다.

변경 파일:
- `scripts/tmux-session-launcher`: sidebar 단축키와 history/open 표시 문자열, All delete 확인 문구 변경
- `HISTORY.md`, `CONVERSATION.md`: 변경 기록 추가

검증:
- `bash -n scripts/tmux-session-launcher`: 통과

후속 주의:
- 내부 모드 이름은 그대로 `history`를 유지하므로, 외부 표시와 입력만 `open`으로 바뀝니다.

## 2026-06-21 - tmux sidebar archive/delete 구조 리팩토링

요약:
- 반복된 sidebar delete/archive 버그의 원인이 archive 경로에서 live sidebar pane을 직접 닫는 구조라고 판단하고, archive 준비를 read-only에 가깝게 정리했습니다.
- delete는 current/other session 모두 같은 background backend를 타도록 TUI 직접 kill 경로를 줄였습니다.
- sidebar가 열린 상태에서 launcher split wrapper를 사용할 때 sidebar를 잠시 분리하고 work layout을 갱신한 뒤 다시 붙여, 저장 layout이 stale해지는 경우를 줄였습니다.

변경 파일:
- `scripts/tmux-session-launcher`: archive 준비 중 sidebar `kill-pane` 제거, split wrapper layout 갱신, session delete backend 단일화
- `HISTORY.md`, `CONVERSATION.md`: 구조 개선 기록

검증:
- `bash -n scripts/tmux-session-launcher`: 통과
- isolated tmux 서버에서 sidebar + split + archive + current delete + all delete 흐름 확인

후속 주의:
- sidebar가 열린 상태에서 tmux 기본 split 명령을 직접 사용하면 work layout option을 완전히 추적하지 못할 수 있으므로, sidebar 상태에서는 launcher wrapper split을 쓰는 정책이 여전히 중요합니다.
- 오래되었거나 stale한 work layout은 archive 시 빈 layout으로 저장될 수 있으며, 이 경우 restore는 pane 생성은 유지하되 exact layout 복원은 생략됩니다.

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
