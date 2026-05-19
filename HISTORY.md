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
