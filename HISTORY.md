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
