# Agent Handoff

다음 에이전트는 이 파일을 먼저 읽고, 필요한 세부 내용은 아래 문서로 이동하세요.

## 빠른 상태

- 개인 Linux dotfiles 저장소입니다.
- 설치 흐름의 중심은 `./setup.sh` (install / update / uninstall / status / doctor / purge)와 `install.toml`입니다.
- `dotfiles`는 전체 개발 환경(Zsh + URxvt + Vim + OpenCode + Tmux)을 조율하는 **최상위 워크스페이스 오케스트레이터(Top-Level Orchestrator)** 역할을 수행합니다.
- 세션 런처/도크 TUI 엔진 및 38종 프리미엄 테마 시스템은 독립 최상위 오픈소스 저장소인 [`tmux-session-dock`](https://github.com/al-hub/tmux-session-dock)으로 완전 분리되었으며, dotfiles는 upstream 릴리스(`v0.1.0+`)를 소비(Consume)합니다.
- 기본 설치는 master 최신 기준이며, 안정 버전은 `v0.1`부터 `setup.sh --v v0.7.0`로 tag 기준 설치할 수 있습니다. 현재 안정 기준은 **v0.7.0**입니다.
- 기본 enabled 설치 항목은 사용자에게 `opencode`와 `tmux`가 보이며, `tmux-session-dock`, `tmux-zshrc`, `urxvt-resize-font`, `tmux-xresources`는 의존성으로 함께 관리됩니다.
- `vim`, `shell`은 manifest에 있지만 disabled입니다.
- `setup.sh` (및 `setup`, `install.sh`, `uninstall.sh` 심볼릭 링크)는 전체 구성 요소의 라이프사이클을 단 하나의 일관된 CLI로 총괄 관리합니다.

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
