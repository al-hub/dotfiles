# Agent Handoff

다음 에이전트는 이 파일을 먼저 읽고, 필요한 세부 내용은 아래 문서로 이동하세요.

## 빠른 상태

- 개인 Linux dotfiles 저장소입니다.
- 설치 흐름의 중심은 `install.sh`와 `install.toml`입니다.
- 기본 enabled 설치 항목은 사용자에게 `tmux`만 보이며, `tmux-session-launcher`와 `tmux-zshrc`는 hidden dependency로 함께 설치됩니다.
- `vim`, `shell`, `tmux-xresources`는 manifest에 있지만 disabled입니다.
- 현재 주요 변경은 tmux 하단 status bar와 window tab을 유지하고, pane border 상단에 현재 경로를 표시하며, `Ctrl+a s`로 popup 기반 session launcher를 열고, tmux 전용 zsh init으로 짧은 prompt와 git completion을 함께 유지하는 것입니다.

## 문서 역할

- `AGENTS.md`: 현재 상태와 작업 규칙 색인
- `HISTORY.md`: 파일/설정 변경 이력
- `CONVERSATION.md`: 사용자 의도와 의사결정 맥락
- `README.md`: 사용자용 설치/구조 안내

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
