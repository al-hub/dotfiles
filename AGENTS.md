# Agent Handoff

다음 에이전트는 이 파일을 먼저 읽고, 필요한 세부 내용은 아래 문서로 이동하세요.

## 빠른 상태

- 개인 Linux dotfiles 저장소입니다.
- 설치 흐름의 중심은 `install.sh`와 `install.toml`입니다.
- sidebar 유지보수 목표는 tmux server당 logical coordinator 1개와 unique managed
  window당 고정 thin presenter 1개입니다. 물리 pane 1개를 이동하는 모델은 채택하지
  않으며, `docs/design/tmux-single-sidebar.md`의 M0~M7 TDD strangler 순서를 따릅니다.
- 기본 설치는 master 최신 기준이며, 안정 버전은 `v0.1`부터 `install.sh --v v0.1`로 tag 기준 설치할 수 있게 준비했습니다. v0.6~v0.6.14를 이전 기준으로 보존하고, 현재 안정 기준은 v0.6.15(v6.15)입니다. launcher 내부 latency phase metrics는 기록되며 완화된 기준 목표(전환 1000ms 이내, 외부 키 반응 100ms 이내)를 적용합니다. 제자리 전환(Fast-Path)은 0.75ms 즉각 반환으로 5초 타임아웃 스파이크를 완전 박멸했으며, 복합 IPC 파이프라인(`switch-client \; select-pane`)으로 전환 안정성을 확보했습니다. 인플라이트 마커 핸드오버 및 선택 정렬 리듀서 도입으로 마커 비동기화와 0번 인덱스 오작동 전환을 완전 해결했습니다. 서브페인 상/하 전환(`Ctrl+a P`) 및 세션 전환 위치 유지, 결정론적 아카이브 명명 규칙, 배치 복원 레이아웃 무결성 직렬화를 지원합니다.
- 기본 enabled 설치 항목은 사용자에게 `opencode`와 `tmux`가 보이며, `tmux-session-launcher`, `tmux-zshrc`, `urxvt-resize-font`, `tmux-xresources`, `tmux-theme-picker`, `tmux-command-palette`는 hidden dependency로 함께 설치됩니다.
- `vim`, `shell`은 manifest에 있지만 disabled입니다.
- 현재 주요 변경은 tmux 하단 status bar와 window tab을 유지하고, pane border 상단에 현재 경로를 표시하며, `Ctrl+a s`로 고정 sidebar session launcher를 열고, tmux 전용 zsh init으로 짧은 prompt와 git completion을 함께 유지하고, URxvt에서 `Ctrl+마우스 휠`로 폰트 크기를 조절하는 것입니다.
- sidebar는 bash/tmux TUI로 분리되어 있으며, 반복 toggle 시 work layout을 저장/복구하고 current session 삭제 시 다른 session으로 이동하거나 마지막 session이면 tmux server를 종료합니다. sidebar가 열린 상태의 직접 tmux split/resize도 after-command/window-resized hook으로 full layout metadata를 갱신하며, sidebar 이동·복구 시 해당 metadata를 검증합니다. wrapper에 묶인 `Ctrl+a |`, `Ctrl+a _`, `Ctrl+a %`, `Ctrl+a "`는 sidebar를 제외한 work pane을 대상으로 하는 권장 경로입니다.
- session 전환은 논리적으로 하나의 shared sidebar 상태를 사용하되, tmux의 pane은 managed window별로 하나씩 사전 provision합니다. target 전환은 `move-pane` 없이 준비된 target pane으로 `switch-client`만 수행하며, hot path에서 layout snapshot/restore와 switch-requested full render를 실행하지 않습니다.
- active client가 session/window를 직접 변경하면 runtime tmux hook은 target window의 local sidebar 존재만 확인하고, 없을 때 cold provision합니다. `d All`은 `@dotfiles_sidebar_managed`로 표시된 session만 대상으로 하며 외부 session은 보존합니다. archive/restore 중에는 operation busy guard가 추가 입력을 거부합니다.
- non-owner client의 session/window 변경은 sidebar를 탈취하지 않고 관측 trace만 남깁니다. archive/delete/restore는 session identity, client attachment, owner client tty/session/window precondition을 재검증하며 외부 conflict 시 대상 session 보존과 rollback을 수행합니다.
- sidebar owner client는 `@dotfiles_sidebar_owner_client`로 고정되며 다른 client가 sidebar를 빼앗지 않습니다. `TMUX_SESSION_LAUNCHER_FAIL_STEP`은 snapshot/move/client-switch/restore-layout/sidebar-focus/transition rollback 테스트에만 사용합니다.
- archive는 version 3 work-pane logical slot/title/geometry/active metadata와 session 전체 window topology를 기록하고 window-local sidebar infrastructure는 저장하지 않습니다. version 1/2 archive는 legacy parser로 읽을 수 있으며, physical work-pane ID/PID는 restore 시 새로 생성됩니다.
- archive snapshot helper는 full `list-panes` schema를 기준으로 sidebar를 식별하고 work-only layout/geometry와 full-window sidebar layout을 분리 기록합니다. restore는 sidebar 생성 후 full layout을 재적용하며 arbitrary-topology attached-PTY 회귀에서 metadata·geometry·client-session readiness가 PASS했습니다.
- numeric session `0` 삭제는 archive target `=0:`과 managed sidebar refresh fan-out을 사용합니다. `test-delete-zero-stale-row.sh`는 삭제 후 stale row 제거와 다음 Enter 전환을 검증합니다.
- archive 생성은 임시 파일 검증 후 고유 이름으로 rename하며, restore 후 history import marker로 동일 archive의 중복 import를 막습니다. bulk archive 실패 시 session 삭제를 중단합니다.
- session 전환은 layout snapshot/restore를 사용하지 않습니다. archive/restore와 cold provisioning만 topology/geometry를 검증하며, horizontal/vertical multi-pane window도 local sidebar geometry를 유지합니다.
- 전환 직후 target sidebar pane이 absent이면 target window에 bounded repair/provision을 수행하고, 정상 전환에서는 이 경로를 실행하지 않습니다. live observer는 반드시 `display-message -c <client_tty>`로 사용자 client context를 고정해야 합니다.
- 성능 baseline은 `tests/compare-profiles.sh`가 현재 checkout의 launcher를 전용 tmux socket, attached urxvt, 임시 history에서 기본 3회 측정합니다. 사용자 live tmux를 변경하지 않으며, 실패한 invariant는 수치로 기록하지 않고 suite를 실패시킵니다.
- 전환 metrics는 validate/ensure-target-sidebar/switch-client/stabilize/finish phase를 operation ID로 연결합니다. native 전환은 target marker를 switch 직전에 게시하고 selection-sync ACK 후 client를 전환하며, current/selected marker delta만 갱신하고 실제 geometry 변화가 없는 full render는 억제합니다. attached PTY 전환 623~838ms는 공식 1000ms 기준 내이며, p95 500ms는 후속 최적화 목표입니다. 사용자 live 6회는 marker invariant 6/6, target pane identity 6/6, known error 0건이며 343~593ms로 측정됐습니다.
- `tmux-sidebar-tmux-adapter`에는 FIFO-backed persistent control-mode 실험 경로가 있으나 `TMUX_SESSION_SIDEBAR_CONTROL_MODE` 기본값은 false입니다. 실제 pane 이동 후 control client event isolation 문제가 확인되어 기본 production은 CLI adapter를 사용하며, control-mode 승격에는 dedicated internal control session/client가 필요합니다.
- history 화면의 `a`는 모든 archive를 명시적으로 선택하고, restore는 selected/restored cardinality를 trace와 `Restore incomplete: x/y`로 보고합니다. attached-PTY 6-archive 전체선택 restore 회귀가 6/6이어야 합니다.
- restore 중 tmux 자동 provision hook은 topology guard로 억제되며, archive의 빈/stale layout은 `-` sentinel과 pane-count 검증으로 geometry가 다른 layout의 적용을 막습니다.

## 문서 역할

- `AGENTS.md`: 현재 상태와 작업 규칙 색인
- `HISTORY.md`: 파일/설정 변경 이력
- `CONVERSATION.md`: 사용자 의도와 의사결정 맥락
- `README.md`: 사용자용 설치/구조 안내
- `docs/README.md`: dotfiles 문서 허브 및 표준 도메인 용어 사전 (Glossary)
- `docs/keybindings.md`: dotfiles 및 tmux 주요 단축키/마우스 조작 가이드
- `docs/architecture.md`: dotfiles 설치 모델 및 모듈 아키텍처
- `docs/guides/reproduction.md`: 에이전트와 사용자의 실환경 재현 및 검증 가이드
- `docs/design/tmux-single-sidebar.md`: `feature/single-sidebar` 설계 계약과 invariant
- `docs/design/tmux-session-launcher-internals.md`: 세션 런처 내부 구조 및 IPC 파이프라인
- `docs/testing/test-matrix.md`: 기존 sidebar 테스트의 Gate A~E 분류, 변경 범위별 최소 실행 세트와 승격 기준
- `docs/testing/window-local-test-plan.md`: window-local sidebar 테스트 경계·정량 기준·RED/GREEN 정책
- `docs/archives/live-session-switch-regression.md`: live `session switch failed` 재현과 원인
- `docs/archives/live-usage-side-effects.md`: 실사용 설치/sidebar side-effect 및 bug audit
- `docs/archives/sidebar-transition-measurement.md`: sidebar 전환 레이턴시 측정 리포트
- `docs/archives/next-session-handoff.md`: 다음 세션 재현 명령·현재 결과·다음 작업 순서
- `tests/tmux-single-sidebar/test-keyboard-e2e.sh`: 실제 attached PTY 입력으로 prefix/sidebar/TUI 전체 시나리오를 검증
- `tests/tmux-single-sidebar/test-user-tmux-required-monitored.sh`: 사용자 default tmux의 현재 client/window에서 필수 live 동작과 timestamp 로그를 검증
- `tests/tmux-single-sidebar/test-session-switch-live-correlation.sh`: attached PTY의 10회 session 전환을 operation/phase/client/sidebar 경계로 상관 분석하고 transition event, 실제 sample interval, redraw/hook count 및 첫 실패 snapshot을 보존
- `tests/tmux-single-sidebar/test-session-switch-live-correlation-horizontal.sh`, `test-session-switch-live-correlation-vertical.sh`: target session의 horizontal/vertical split topology를 구성한 뒤 동일 correlation 전환을 검증
- `tests/tmux-single-sidebar/test-live-full-monitored.sh`: 중첩 tmux 없이 full E2E를 실행하고 raw PTY/trace를 실시간 모니터링
- `tests/tmux-single-sidebar/test-session-name-zero.sh`: live numeric session `0` target ambiguity를 재현하는 RED 회귀 테스트
- `tests/tmux-single-sidebar/test-delete-zero-stale-row.sh`: numeric `0` 삭제 후 sidebar snapshot invalidation과 유효 session 전환을 attached PTY로 검증
- `tests/tmux-single-sidebar/test-layout-metadata-failure.sh`: multi-pane target metadata 부재 시 rollback을 검증
- `tests/tmux-single-sidebar/test-keyboard-e2e-multi-window-topology.sh`: multi-window/복합 topology archive·restore와 active-window 단일 sidebar를 attached PTY로 검증
- `tests/tmux-single-sidebar/test-keyboard-e2e-direct-layout.sh`: raw tmux horizontal/vertical split/resize 후 session 왕복을 attached PTY로 검증
- `tests/tmux-single-sidebar/test-keyboard-e2e-rapid-operations.sh`: archive/delete/restore 중 급속 입력 drain과 operation ownership을 검증
- `tests/tmux-single-sidebar/test-multi-client-operation-conflict.sh`: 외부 client attach/delete/restore name collision conflict와 rollback을 검증
- `tests/tmux-single-sidebar/test-window-local-contract.sh`: managed window별 sidebar 1개와 global toggle contract
- `tests/tmux-single-sidebar/test-keyboard-e2e-window-local-switch.sh`: attached PTY window-local session switch contract
- `tests/tmux-single-sidebar/test-window-local-lifecycle-contract.sh`, `test-window-local-multi-client.sh`: archive/lifecycle와 linked-window/multi-client 경계 contract
- `scripts/tmux-sidebar-tmux-adapter`: 단일 sidebar의 tmux 경계 어댑터 구현

## 작업 규칙

- 작업 전 `git status --short`로 기존 변경을 확인하세요.
- 의미 있는 파일/설정 변경 후에는 `HISTORY.md`에 변경 이력을 추가하세요.
- 작업 방향에 영향을 준 사용자 의도나 결정은 `CONVERSATION.md`에 요약하세요.
- 원문 대화 전체를 저장하지 말고, 다음 작업에 필요한 맥락만 남기세요.
- 레거시 스크립트 `install_dotfiles.sh`, `get_dotfiles.sh`는 자동 실행하지 마세요.

## 검증

기본 검증:

```sh
bash -n install.sh
bash -n scripts/tmux-session-launcher
perl -c dotfiles/urxvt/ext/resize-font
sh -n get_dotfiles.sh
sh -n install_dotfiles.sh
git diff --check
```

단일 sidebar 개발 branch의 TDD 계약 테스트:

```sh
bash tests/tmux-single-sidebar/test-contract.sh
```

이 테스트는 window-local sidebar provisioning과 native switch 기준선을 검증합니다.

tmux 설정 로딩 검증:

```sh
tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d
tmux -L codex-dotfiles-test kill-server
```

현재 sandbox에서는 tmux socket 접근에 승격 실행이 필요할 수 있습니다.
