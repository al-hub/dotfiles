# Agent Handoff

다음 에이전트는 이 파일을 먼저 읽고, 필요한 세부 내용은 아래 문서로 이동하세요.

## 빠른 상태

- 개인 Linux dotfiles 저장소입니다.
- 설치 흐름의 중심은 `install.sh`와 `install.toml`입니다.
- 기본 설치는 master 최신 기준이며, 안정 버전은 `v0.1`부터 `install.sh --v v0.1`로 tag 기준 설치할 수 있게 준비했습니다. v0.6~v0.6.4를 이전 기준으로 보존하고, 현재 안정 기준은 v0.6.5(v6.5)입니다. key latency 40ms 목표 미달은 후속 과제로 추적합니다.
- 기본 enabled 설치 항목은 사용자에게 `opencode`와 `tmux`가 보이며, `tmux-session-launcher`, `tmux-zshrc`, `urxvt-resize-font`, `tmux-xresources`, `tmux-theme-picker`, `tmux-command-palette`는 hidden dependency로 함께 설치됩니다.
- `vim`, `shell`은 manifest에 있지만 disabled입니다.
- 현재 주요 변경은 tmux 하단 status bar와 window tab을 유지하고, pane border 상단에 현재 경로를 표시하며, `Ctrl+a s`로 고정 sidebar session launcher를 열고, tmux 전용 zsh init으로 짧은 prompt와 git completion을 함께 유지하고, URxvt에서 `Ctrl+마우스 휠`로 폰트 크기를 조절하는 것입니다.
- sidebar는 bash/tmux TUI로 분리되어 있으며, 반복 toggle 시 work layout을 저장/복구하고 current session 삭제 시 다른 session으로 이동하거나 마지막 session이면 tmux server를 종료합니다. 직접 tmux 기본 split/resize로 sidebar가 열린 상태의 work 영역을 바꾼 경우까지 완전 추적하지는 못하므로, sidebar와 함께 split할 때는 wrapper에 묶인 `Ctrl+a |`, `Ctrl+a _`, `Ctrl+a %`, `Ctrl+a "`를 사용하세요.
- session 전환 시 target sidebar 프로세스는 유지하고 force-refresh를 사용합니다. 최종 `>*` 정렬은 확인됐지만, 빠른 전환 직후 이전 `>`가 잠깐 남는 transient cursor frame은 아직 재현 가능한 제한사항입니다.
- 성능 baseline은 `tests/compare-profiles.sh`가 현재 checkout의 launcher를 전용 tmux socket, attached urxvt, 임시 history에서 기본 3회 측정합니다. 사용자 live tmux를 변경하지 않으며, 실패한 invariant는 수치로 기록하지 않고 suite를 실패시킵니다.

## 문서 역할

- `AGENTS.md`: 현재 상태와 작업 규칙 색인
- `HISTORY.md`: 파일/설정 변경 이력
- `CONVERSATION.md`: 사용자 의도와 의사결정 맥락
- `README.md`: 사용자용 설치/구조 안내
- `docs/reproduction.md`: 에이전트와 사용자의 실환경 재현 및 검증 가이드

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

tmux 설정 로딩 검증:

```sh
tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session -d
tmux -L codex-dotfiles-test kill-server
```

현재 sandbox에서는 tmux socket 접근에 승격 실행이 필요할 수 있습니다.
