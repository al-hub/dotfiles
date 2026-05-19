# Conversation Notes

이 파일은 작업 주제와 관련된 대화 맥락을 요약해서 남깁니다. 원문 대화를 그대로 보관하지 않고, 다음 에이전트가 의도와 결정을 이해하는 데 필요한 내용만 기록합니다.

## 작성 규칙

- 새 대화 주제는 위에 추가합니다.
- 사용자 요청, 해석, 결정, 작업 결과, 남은 질문을 분리해서 적습니다.
- 원문 전체를 붙이지 말고 필요한 문장만 짧게 요약합니다.
- 민감하거나 일회성인 내용은 저장하지 않습니다.

## 템플릿

```md
## YYYY-MM-DD - 주제

사용자 요청:
- 사용자가 원한 것

해석/결정:
- 에이전트가 어떻게 해석했고 어떤 방향으로 결정했는지

작업 결과:
- 실제 변경 또는 답변 요약

남은 질문:
- 다음에 확인할 점
```

## 2026-05-20 - URxvt Ctrl+wheel 미동작 보강

사용자 요청:
- 구현 후 `Ctrl+휠키`가 동작하지 않는다고 보고했습니다.

해석/결정:
- URxvt Perl extension의 `on_button_press` hook은 유지하되, vt window에서 button press event를 받도록 event mask 등록이 필요하다고 판단했습니다.
- 설치된 파일 갱신 후 URxvt 새 창에서 다시 확인해야 합니다.

작업 결과:
- `resize-font` extension에 `vt_emask_add(urxvt::ButtonPressMask())`를 추가했습니다.

남은 질문:
- 실제 URxvt GUI에서 `Ctrl+WheelUp/Down/Click` 동작을 재확인해야 합니다.

## 2026-05-20 - tmux 설치에 URxvt Ctrl+마우스 확대/축소 포함

사용자 요청:
- tmux 안에서 `Ctrl+마우스 스크롤`로 화면 확대/축소를 하고 싶다고 했습니다.
- `Ctrl+마우스휠 클릭`은 기본 크기(100%)로 복원되면 좋겠다고 했습니다.

해석/결정:
- 폰트 크기 변경은 tmux가 아니라 URxvt terminal layer에서 처리해야 한다고 판단했습니다.
- 대상 터미널은 URxvt만으로 한정하고, `tmux` 설치 시 URxvt resize-font 설정도 hidden dependency로 함께 설치하기로 했습니다.
- `Ctrl+WheelUp`은 확대, `Ctrl+WheelDown`은 축소, `Ctrl+WheelClick`은 reset으로 고정했습니다.

작업 결과:
- URxvt resize-font extension을 repo에 추가했습니다.
- `tmux` dependency에 `urxvt-resize-font`, `tmux-xresources`를 추가하고 `tmux-xresources`를 hidden 처리했습니다.
- Xresources 설치 후 가능한 경우 `xrdb -merge ~/.Xresources`를 자동 실행하도록 했습니다.

남은 질문:
- 실제 URxvt GUI 환경에서 `Ctrl+마우스` 입력 동작을 확인해야 합니다.

## 2026-05-13 - tmux 구성요소를 hidden dependency로 정리

사용자 요청:
- 설치 화면에서 `tmux-session-launcher`, `tmux-zshrc`가 따로 보이지만 실제로는 tmux에 연결되는 구성요소가 아니냐고 지적했고, 이를 정리하길 원했습니다.

해석/결정:
- 사용자 선택 단위는 `tmux` 하나이고, launcher와 tmux 전용 zshrc는 파일 설치 단위로만 남겨야 한다고 판단했습니다.
- manifest에 `depends`와 `hidden`을 추가해 UI 표시와 실제 설치 파일 단위를 분리하기로 했습니다.

작업 결과:
- `tmux`가 `tmux-session-launcher`, `tmux-zshrc`를 dependency로 설치하도록 변경했습니다.
- 하위 항목은 hidden 처리해 설치 목록과 번호 선택에서 제외했습니다.

남은 질문:
- 없음

## 2026-05-13 - tmux git completion과 짧은 prompt 병행

사용자 요청:
- tmux 안에서 git 명령어 자동완성이 되지 않는 원인을 물었고, 단순히 `zsh -f`를 제거하면 경로 prompt가 다시 나오는 것 아닌지 확인했습니다.
- 짧은 prompt는 유지하면서 git completion을 복구하는 변경을 원했습니다.

해석/결정:
- 기존 `default-command '... /bin/zsh -f'`가 zsh init 파일을 건너뛰어 `compinit`이 로드되지 않는 것이 원인입니다.
- 사용자 기본 `~/.zshrc`를 직접 읽으면 prompt가 바뀔 수 있으므로 tmux 전용 `ZDOTDIR`를 사용하기로 했습니다.

작업 결과:
- tmux가 `ZDOTDIR="$HOME/.cache/dotfiles"`로 zsh를 실행하도록 변경했습니다.
- `dotfiles/tmux.zshrc`를 추가해 `$ ` prompt와 `compinit -u`만 로드하도록 했습니다.
- install manifest와 tmux install hook에 `tmux-zshrc` 설치를 추가했습니다.

남은 질문:
- tmux 안에서 추가로 필요한 alias나 zsh 옵션이 있으면 `dotfiles/tmux.zshrc`에 선별적으로 추가해야 합니다.

## 2026-05-13 - 설치된 launcher 구버전 유지 문제

사용자 요청:
- 최신 수정 후에도 설치해서 tmux를 실행하면 `Commands>` key 입력 시 문제가 계속된다고 했습니다.

해석/결정:
- repo의 `scripts/tmux-session-launcher`는 `c` 입력 시 `New session name:`까지 정상 진입하지만, 실제 `~/.local/bin/tmux-session-launcher`는 이전 `parse_selection()` 구현이 남아 있음을 확인했습니다.
- 설치 스크립트가 기존 target 파일에 대해 항상 force install 확인을 요구하므로, managed 항목도 사용자가 거절하면 갱신되지 않는 것이 문제라고 판단했습니다.
- manifest에 기록된 managed 항목은 재설치 시 자동 백업 후 갱신하도록 변경하기로 했습니다.

작업 결과:
- `install.sh`에서 managed target은 확인 없이 업데이트하도록 수정했습니다.

남은 질문:
- manifest가 없는 기존 설치 환경에서는 최초 1회 force install 확인이 여전히 필요합니다.

## 2026-05-13 - tmux launcher Commands query와 session row 충돌

사용자 요청:
- 이전 커밋에서 고쳤다고 한 버그가 아직 수정되지 않았다고 했습니다.

해석/결정:
- `Commands>`에서 알 수 없는 query를 입력해도 fzf가 매칭한 session row가 있으면 Enter가 여전히 switch/exit 경로로 떨어지는 잔여 버그로 판단했습니다.
- `Commands>`에서는 non-empty query Enter를 항상 command 해석으로 고정하고, session 검색 이동은 `Sessions>` prompt에서만 허용하도록 정리했습니다.

작업 결과:
- `scripts/tmux-session-launcher`의 `Commands>` Enter 분기를 수정해 invalid query가 session row와 충돌해도 launcher가 종료되지 않게 했습니다.
- README에 `Commands>`와 `Sessions>`의 역할 차이를 더 명확히 기록했습니다.

남은 질문:
- 없음

## 2026-05-13 - tmux launcher fzf 출력 순서 오해

사용자 요청:
- 설치 후 tmux에서 `Commands>`에 어떤 key를 입력해도 종료된다고 했고, 어디가 문제인지 확인한 뒤 수정하길 원했습니다.

해석/결정:
- `parse_selection()`이 `fzf --print-query --expect` 출력을 `key, query, row` 순서로 잘못 가정한 것이 원인이라고 판단했습니다.
- 실제 출력인 `query, key, row` 순서에 맞춰 파싱을 수정하고, `Commands>` key 입력이 session 이름으로 오인되지 않게 정리했습니다.

작업 결과:
- `scripts/tmux-session-launcher`의 `parse_selection()`을 수정했습니다.
- README와 기록 문서에 실제 원인과 제약을 남겼습니다.

남은 질문:
- 없음

## 2026-05-13 - tmux launcher Commands 입력 시 종료 버그

사용자 요청:
- 프로젝트를 분석하고, `Ctrl+a s` popup의 `Commands>` prompt에 명령을 입력하면 launcher가 종료되는 버그를 확인해 달라고 했습니다.

해석/결정:
- `Commands>`에서 Enter를 누를 때 query가 명령으로 해석되지 않으면, 선택 row가 비어 있어도 기존 Enter 기본 동작인 session switch 후 종료로 떨어지는 것이 원인이라고 판단했습니다.
- `Commands>`에서는 query 기반 명령 alias를 명시적으로 처리하고, row 없이 알 수 없는 명령이 들어오면 종료하지 않고 오류를 보여준 뒤 launcher로 복귀하도록 변경했습니다.

작업 결과:
- `scripts/tmux-session-launcher`에 query command dispatcher를 추가했습니다.
- `Commands>`에서 `create/new`, `delete/remove`, `rename`, `q/quit/exit` alias를 지원하게 했습니다.
- invalid command와 no-match session Enter 시 launcher가 종료되지 않도록 수정했습니다.

남은 질문:
- 없음

## 2026-05-09 - tmux launcher Commands query 버그

사용자 요청:
- `Commands>` 기본 동작이 되지 않고 명령 keyword를 입력하면 바로 종료되는 버그를 보고했습니다.

해석/결정:
- `--print-query` 도입 후 `Commands>`에서 `c`, `d`, `r`을 입력 후 Enter로 실행하면 선택 row가 비고 query만 남아 Enter 기본 동작인 session switch/exit로 떨어지는 문제로 판단했습니다.
- `Commands>`에서는 Enter query가 `c`, `d`, `r`, `exit`일 때 row 선택보다 먼저 command로 처리하도록 했습니다.

작업 결과:
- `scripts/tmux-session-launcher`의 `run_launcher`에 `Commands>` Enter query command 분기를 추가했습니다.

남은 질문:
- 없음

## 2026-05-09 - tmux launcher exit 입력과 Sessions 명령 차단

사용자 요청:
- `Commands>`에서 `exit`라고 직접 입력하면 `Esc(exit): close`처럼 launcher가 닫히길 원했습니다.
- `Sessions>` 입력에서는 `Commands>`의 `c`, `d`, `r` 명령이 동작하지 않아야 한다고 했습니다.

해석/결정:
- 같은 session list UI는 유지하되, prompt 상태별로 fzf expect key를 다르게 설정합니다.
- `Commands>`에서는 `c`/`d`/`r`을 command key로 받고, `Sessions>`에서는 `tab`/`enter`만 expect key로 받아 `c`/`d`/`r`이 검색 query에 남게 합니다.
- `--print-query`로 입력 query를 받아 `Commands>`에서 query가 정확히 `exit`이면 종료합니다.

작업 결과:
- `scripts/tmux-session-launcher`에서 prompt별 expect key와 header를 분리했습니다.
- `Commands> exit` 닫기를 추가했습니다.
- README에 `Sessions>`에서 `c`/`d`/`r`은 검색 입력으로 처리된다는 설명을 추가했습니다.

남은 질문:
- 없음

## 2026-05-09 - tmux launcher rename 종료와 Tab 전환 버그

사용자 요청:
- rename 후 launcher가 바로 종료되면 안 된다고 했습니다.
- `Tab`을 누르면 `Commands>`와 `Sessions>`가 서로 전환되어야 한다고 했습니다.

해석/결정:
- rename 종료는 `set -e` 상태에서 `[ "$current_session" = "$old_name" ] && ...` 조건식이 false를 반환하며 함수/스크립트가 종료될 수 있는 문제로 판단했습니다.
- 이전 단일 session list UI 요구는 유지하고, `Commands>`/`Sessions>`는 같은 list의 prompt 상태만 전환하는 것으로 해석했습니다.

작업 결과:
- rename 후 current session 갱신 조건을 안전한 `if` 문으로 변경했습니다.
- fzf `--expect`에 `tab`을 추가하고 prompt 상태를 `Commands>`/`Sessions>`로 토글하도록 변경했습니다.
- README에 Tab prompt 전환 설명을 추가했습니다.

남은 질문:
- 없음

## 2026-05-09 - tmux launcher 단일 session list UI

사용자 요청:
- session list가 보이는 창 하나만 있어야 하며 모든 기능이 그 UI에서 진행되어야 한다고 정정했습니다.
- `Sessions >` 대신 `Commands >`가 먼저 나오되, command 목록을 고르는 방식은 원하지 않았습니다.
- session list를 계속 유지한 상태에서 `c`, `d`, `r` 키를 누르면 선택 session에 대해 각 기능이 바로 동작하길 원했습니다.

해석/결정:
- 별도의 Commands list와 Tab 전환 모드를 제거하고, fzf에는 session list만 표시합니다.
- `Commands >`는 prompt 이름으로만 사용하고, `c`/`d`/`r`은 fzf `--expect` command key로 처리합니다.
- command 실행을 위해 fzf가 잠시 종료될 때도 `--no-clear`로 list 화면을 남기고 하단 prompt에서 입력을 받도록 했습니다.

작업 결과:
- `scripts/tmux-session-launcher`를 단일 session list 루프로 단순화했습니다.
- README의 launcher 사용법에서 Tab 전환과 command list 설명을 제거했습니다.

남은 질문:
- 없음

## 2026-05-09 - tmux launcher command UI 요구사항

사용자 요청:
- `Enter`, `Esc`는 유지하고 `Ctrl+n`은 제거하길 원했습니다.
- 시작 화면은 `Commands >`가 먼저 나오고, `Tab`으로 `Sessions >`와 전환되길 원했습니다.
- command 화면에서 `c`는 새 session, `d`는 선택 session 삭제, `r`은 선택 session rename으로 동작하길 원했습니다.
- 새 session 생성, 삭제 확인, rename 입력은 popup 하단 prompt에서 처리하고 command 실행 후 launcher로 돌아오길 원했습니다.

해석/결정:
- launcher popup은 하나로 유지하고, fzf 모드만 commands/sessions 사이에서 바뀌도록 했습니다.
- 선택 대상 session은 `Sessions >`에서 highlight 후 `Tab`으로 command 화면에 돌아오면 command가 그 session에 적용되는 방식으로 해석했습니다.
- 새 session 생성은 기존 창/session을 유지하고 detached session만 만든 뒤 launcher로 돌아오도록 했습니다.

작업 결과:
- `scripts/tmux-session-launcher`를 command/session 모드 루프로 변경했습니다.
- `Commands >`에서 `c`, `d`, `r` command를 추가하고 각 command 후 launcher로 돌아오게 했습니다.
- `README.md`의 launcher 키 설명을 새 UI에 맞게 갱신했습니다.

남은 질문:
- 없음

## 2026-05-09 - tmux launcher 원격 설치 누락 점검

사용자 요청:
- `curl -fsSL https://raw.githubusercontent.com/al-hub/dotfiles/refs/heads/master/install.sh | bash`를 다른 곳에서 실행하면 popup 기반 session launcher가 동작하지 않는다고 했고, 오류 여부 점검을 요청했습니다.

해석/결정:
- Enter로 enabled 전체 설치하면 launcher도 설치되지만, 번호 `1`만 선택하면 `tmux` 설정만 설치되고 launcher 스크립트가 빠지는 구조가 문제라고 판단했습니다.
- 사용자가 tmux 항목만 선택해도 `Ctrl+a s` 바인딩 대상이 존재해야 하므로 `tmux` 설치 hook에서 launcher 설치를 보장하기로 했습니다.

작업 결과:
- `install.sh`에 이름으로 manifest 항목을 설치하는 helper를 추가했습니다.
- `tmux` after-install hook에서 `tmux-session-launcher`도 설치하도록 변경했습니다.
- 임시 HOME 재현에서 번호 `1` 선택만으로 `.tmux.conf`와 `.local/bin/tmux-session-launcher`가 함께 설치되는 것을 확인했습니다.

남은 질문:
- 없음

## 2026-05-09 - tmux popup session launcher

사용자 요청:
- `Ctrl+a s`를 누르면 tmux popup 안에서 session 목록을 보고 fzf로 선택하고 싶다고 했습니다.
- Enter로 선택 session 이동, `Ctrl+n`으로 새 session 생성이 가능한 1단계 구현을 원했습니다.
- 이후 rename/delete/worktree/project launcher로 확장하기 쉬운 구조를 선호한다고 했습니다.

해석/결정:
- 기존 tmux 기본 `prefix s` session chooser를 `unbind-key s` 후 새 popup launcher로 교체합니다.
- popup은 tmux native `display-popup`을 사용하고, 선택 UI는 `fzf`, orchestration은 shell script로 둡니다.
- 확장성을 위해 복잡한 로직은 `dotfiles/tmux.conf`에 인라인으로 넣지 않고 `scripts/tmux-session-launcher`에 분리합니다.

작업 결과:
- `scripts/tmux-session-launcher`를 추가해 session 목록 표시, 선택 session 이동, `Ctrl+n` 새 session 생성을 구현했습니다.
- `dotfiles/tmux.conf`의 `Ctrl+a s`를 launcher popup으로 연결했습니다.
- `install.toml`에 `fzf` 의존성과 launcher 설치 항목을 추가했습니다.

남은 질문:
- 다음 단계에서 rename/delete/worktree/project launcher의 키맵과 데이터 소스를 정해야 합니다.

## 2026-05-05 - tmux 탭 이동을 Ctrl+a Tab으로 변경

사용자 요청:
- PowerShell에서 WSL로 들어와 tmux를 사용할 때 `Ctrl+Tab`이 동작하지 않는다고 했습니다.
- `Ctrl+a` 후 `Tab`으로 탭을 옮길 수 있는지 물었습니다.

해석/결정:
- Windows Terminal/PowerShell이 `Ctrl+Tab`을 먼저 처리할 수 있으므로 tmux prefix 기반 바인딩으로 변경합니다.
- `Ctrl+a Tab`은 다음 window, `Ctrl+a Shift+Tab`은 이전 window로 매핑합니다.

작업 결과:
- `dotfiles/tmux.conf`에서 prefix 기반 `Tab`/`BTab` window 이동 바인딩으로 변경했습니다.
- tmux test server에서 `list-keys`로 `prefix Tab next-window`, `prefix BTab previous-window`가 로드되는 것을 확인했습니다.

남은 질문:
- 없음

## 2026-05-05 - tmux 하단 status와 window tab 회귀 수정

사용자 요청:
- 본래 있던 하단 상태창이 사라졌고, 신규 창을 만들 때 나오던 tab도 보이지 않는 심각한 회귀를 보고했습니다.

해석/결정:
- 상단 status bar에 경로만 표시하면서 기존 하단 status bar와 window status format을 사실상 제거한 것이 원인입니다.
- 하단 status bar와 window tab은 기존 방식으로 복원합니다.
- 현재 경로는 status bar가 아니라 `pane-border-status top`의 pane border title로 표시합니다.

작업 결과:
- 하단 status bar와 window tab 표시를 복원했습니다.
- 현재 경로는 `pane-border-status top`과 `pane-border-format "#{pane_current_path}"`로 pane 상단 border에 표시하도록 변경했습니다.
- tmux 옵션 검증으로 status bar 위치, window tab format, pane border 경로 설정을 확인했습니다.

남은 질문:
- 없음

## 2026-05-05 - tmux 설치 시 기존 server 종료

사용자 요청:
- `tmux kill-server`와 임시 zsh rc 제거 후 다시 설치/실행하면 원하는 상태로 돌아간다고 확인했습니다.
- 이 완전 정리 작업을 `install.sh` 설치 과정에서 자동으로 수행해야 한다고 했습니다.

해석/결정:
- tmux 설정 파일이 새로 설치되어도 기존 tmux server와 기존 pane shell은 이전 설정을 유지하므로 설치 단계에서 runtime 정리가 필요합니다.
- `tmux` 항목을 설치했거나 이미 같은 파일이 설치되어 있더라도 `after_install_item`에서 정리를 실행합니다.
- 정리 범위는 `~/.cache/dotfiles/.zshrc` 제거와 기존 tmux server 종료입니다.

작업 결과:
- `install.sh`에 tmux 설치 후 정리 hook을 추가했습니다.
- tmux 항목이 설치되거나 이미 같은 파일이 설치된 경우에도 `~/.cache/dotfiles/.zshrc`를 제거하고 기존 tmux server를 종료합니다.
- 임시 `HOME`과 `TMUX_TMPDIR`를 사용한 격리 설치 테스트에서 rc 제거와 tmux server 종료를 확인했습니다.

남은 질문:
- 없음

## 2026-05-05 - tmux 경로는 최상단에서 갱신

사용자 요청:
- `cd ..`를 하면 새 경로가 아래쪽에 새로 찍히는 것이 아니라 최상단 경로 표시가 갱신되어야 한다고 했습니다.
- pane 안에는 `$` 프롬프트만 반복되는 형태를 원합니다.

해석/결정:
- shell prompt 또는 `precmd` 출력으로는 이미 출력된 최상단 줄을 안정적으로 갱신하기 어렵습니다.
- 현재 경로는 tmux 상단 status bar에 표시하고, pane 본문에는 `$ ` 프롬프트만 남기는 방식으로 정리합니다.
- `#{pane_current_path}`를 사용하면 `cd` 후 tmux가 현재 pane 경로를 갱신해 status bar에 반영합니다.

작업 결과:
- tmux status bar를 상단으로 옮기고, 왼쪽에 현재 pane 경로만 표시하도록 변경했습니다.
- zsh는 다시 `PROMPT="$ "`와 `zsh -f`만 사용해 pane 본문에는 `$`만 표시되게 했습니다.
- `cd /tmp` 후 `#{pane_current_path}`가 `/tmp`로 갱신되는 것을 확인했습니다.

남은 질문:
- 없음

## 2026-05-05 - tmux 경로는 변경될 때만 표시

사용자 요청:
- 설치 후 tmux에서 Enter를 누를 때마다 `/mnt/c/Users/82108`과 `$`가 반복된다고 했습니다.
- 원하는 형태는 최초에 `/mnt/c/Users/82108`가 한 번 나오고, 이후 같은 경로에서는 `$`만 반복되는 것입니다.
- 경로를 옮기면 새 경로는 표시되어야 합니다.

해석/결정:
- 경로를 `PROMPT`에 직접 넣으면 매 프롬프트마다 반복되므로 요구사항과 맞지 않습니다.
- zsh `precmd`에서 마지막으로 출력한 `PWD`와 현재 `PWD`를 비교하고, 달라졌을 때만 경로를 출력하기로 했습니다.
- `tmux.conf` 하나만 설치해도 동작하도록 tmux 시작 시 전용 `~/.cache/dotfiles/.zshrc`를 생성해 `ZDOTDIR`로 읽게 합니다.

작업 결과:
- Enter 반복 시 경로는 반복되지 않고 `$`만 표시되도록 변경했습니다.
- `cd /tmp` 후 `/tmp`가 한 번 표시되고 다음 Enter부터 `$`만 반복되는 것을 tmux capture로 확인했습니다.

남은 질문:
- 없음

## 2026-05-05 - tmux 현재 경로를 프롬프트 위에 표시

사용자 요청:
- `curl ... install.sh | bash`로 `tmux`만 설치한 뒤 tmux에 들어가면 Enter마다 `$`는 의도대로 나오지만 경로가 보이지 않는다고 했습니다.
- 원하는 형태는 tmux 진입 시 현재 경로가 제일 위에 한 줄 표시되고, 그 아래에 `$` 프롬프트가 반복되는 것입니다.
- 예시는 `/mnt/c/Users/82108` 다음 줄에 `$`가 나오며, `cd`로 경로를 옮기면 해당 위치로 업데이트되는 형태입니다.

해석/결정:
- `tmux.conf` 하나만 설치해도 동작해야 하므로 별도 zsh rc 파일은 만들지 않습니다.
- zsh prompt escape `%/`를 사용해 매 프롬프트마다 현재 작업 디렉터리를 표시합니다.
- 하단 status bar의 `status-right` 경로 표시는 중복을 피하기 위해 비웁니다.

작업 결과:
- `dotfiles/tmux.conf`의 tmux 기본 zsh 프롬프트를 현재 경로 줄과 `$` 줄로 변경했습니다.
- `cd /tmp` 후 다음 프롬프트가 `/tmp`로 갱신되는 것을 tmux capture로 확인했습니다.

남은 질문:
- 없음

## 2026-05-05 - tmux-zshrc 제거와 단순화

사용자 요청:
- 실제 설치 결과를 공유하며 원하는 형태가 프롬프트 `$`와 하단 현재 경로임을 명확히 했습니다.

해석/결정:
- `tmux-zshrc`를 별도 enabled 항목으로 두면 사용자가 `1`만 선택했을 때 설치되지 않아 문제가 재발합니다.
- `ZDOTDIR`만 지정하고 rc 파일이 없으면 zsh new user 설정 화면이 뜰 수 있어 구조가 불안정합니다.
- 따라서 `tmux.conf` 하나로 처리하고 `tmux-zshrc`는 제거하기로 했습니다.

작업 결과:
- zsh는 tmux 안에서 `PROMPT="$ " RPROMPT="" /bin/zsh -f`로 실행합니다.
- 현재 경로는 tmux status bar 하단 오른쪽에 `#{pane_current_path}`로 표시합니다.
- `install.toml`의 `tmux-zshrc` 항목과 `dotfiles/tmux-zshrc` 파일을 제거했습니다.

남은 질문:
- tmux 안에서 사용자 `~/.zshrc`의 alias/function도 필요하면 별도 방식이 필요합니다. 현재는 단순 프롬프트 안정성을 우선했습니다.

## 2026-05-05 - tmux 실제 설치 후 프롬프트 재조정

사용자 요청:
- `curl ... install.sh | bash` 실행 후 설치 메뉴에서 `1`만 선택해 `tmux`를 설치했습니다.
- tmux 진입 후 Enter를 누르면 `LAPTOP-4482G7PC%`가 반복된다고 보고했습니다.
- 원하는 형태는 프롬프트 줄에는 `$`만 나오고, 현재 경로는 tmux 맨 아래에 `/mnt/c/Users/82108`처럼 표시되는 것입니다.

해석/결정:
- 사용자가 `tmux-zshrc` 항목을 설치하지 않아 tmux 전용 zsh rc가 없는 상태로 zsh 기본 프롬프트가 나온 것으로 판단했습니다.
- 선택 설치에서 `tmux`만 설치해도 최소한 `$` 프롬프트가 나오도록 `tmux.conf`의 `default-command`에 `PROMPT`와 `RPROMPT` 환경값을 넣기로 했습니다.
- 경로는 shell 프롬프트가 아니라 tmux 하단 status bar의 `status-right`에 `#{pane_current_path}`로 표시하기로 했습니다.

작업 결과:
- `dotfiles/tmux.conf`: prompt 환경값 추가, `status-right`를 현재 경로로 변경
- `dotfiles/tmux-zshrc`: prompt를 `$ `로 고정하고 `precmd`에서 유지

남은 질문:
- 사용자가 날짜/시간도 하단에 함께 유지하기 원하는지는 아직 확인되지 않았습니다.

## 2026-05-05 - 문서 중복 정리

사용자 요청:
- `AGENTS.md`, `HISTORY.md`, `CONVERSATION.md` 사이에 겹치는 부분을 삭제하고 효율적으로 관리하자고 요청했습니다.

해석/결정:
- `AGENTS.md`는 다음 에이전트가 가장 먼저 읽는 색인으로 축소하기로 했습니다.
- 변경 이력은 `HISTORY.md`, 사용자 의도와 결정 맥락은 `CONVERSATION.md`에만 남기는 기준을 유지하기로 했습니다.

작업 결과:
- `AGENTS.md`에서 상세 설치 구조, tmux 변경 의도, 레거시 상세 설명을 제거했습니다.
- `AGENTS.md`에는 빠른 상태, 문서 역할, 작업 규칙, 검증 명령만 남겼습니다.
- `HISTORY.md`와 `CONVERSATION.md`에는 이번 정리 자체의 이력을 추가했습니다.

남은 질문:
- 이력 기록을 실제 자동화할지, 에이전트 작업 규칙으로만 유지할지는 아직 결정되지 않았습니다.

## 2026-05-05 - 작업 인수인계와 이력 기록 방식

사용자 요청:
- "현재 상태 알려줘"에는 짧은 요약을, "자세히 알려줘"에는 상세 내용을 제공할 수 있도록 다음 에이전트용 문서를 원했습니다.
- 주요 변경 이력도 자동으로 남길 수 있으면 좋겠다고 요청했습니다.
- 주제와 관련된 대화 이력도 남겨야 할 것 같다고 요청했습니다.

해석/결정:
- 다음 에이전트가 가장 먼저 찾기 쉬운 파일로 `AGENTS.md`를 추가했습니다.
- 작업 변경 이력은 `HISTORY.md`에 누적하고, 대화 맥락은 별도 `CONVERSATION.md`에 요약하기로 했습니다.
- 대화 이력은 원문 전체가 아니라 사용자 의도, 결정, 작업 결과, 남은 질문 위주로 기록합니다.

작업 결과:
- `AGENTS.md`: 현재 상태 요약, 상세 컨텍스트, 다음 에이전트 응답 가이드 추가
- `HISTORY.md`: 주요 작업 이력 작성 규칙, 템플릿, 첫 이력 항목 추가
- `CONVERSATION.md`: 대화 맥락 작성 규칙, 템플릿, 현재 주제 기록 추가
- `README.md`: `AGENTS.md`, `HISTORY.md`, `CONVERSATION.md` 링크 추가

남은 질문:
- 사용자가 원하는 "자동"의 범위가 commit hook인지, 에이전트 작업 규칙인지, 스크립트 생성인지 아직 확정되지 않았습니다.

## 2026-05-05 - tmux 프롬프트와 status bar 변경

사용자 요청:
- tmux 진입 시 상단에 경로가 나오고 한 칸 띈 뒤 `%`가 표시되는 상태를 바꾸고 싶다고 했습니다.
- 경로는 하단에 한 번만 표시하고, `%` 대신 `$`를 쓰며, 경로와 `$` 사이에는 공백이 없기를 원했습니다.
- 설정이 꼬이지 않는지도 확인해 달라고 했습니다.

해석/결정:
- 보이는 `%`는 tmux status bar가 아니라 tmux 안에서 실행되는 zsh 기본 프롬프트로 해석했습니다.
- 전역 `~/.zshrc`를 직접 수정하지 않고, tmux 안에서만 전용 zsh rc를 읽게 하는 방향을 선택했습니다.
- `default-command`는 중간 shell이 남지 않도록 `exec env ZDOTDIR=... /bin/zsh` 형태로 정리했습니다.

작업 결과:
- `dotfiles/tmux.conf`: `status-position bottom` 추가, tmux 전용 zsh rc를 읽는 `default-command` 추가
- `dotfiles/tmux-zshrc`: 기존 `~/.zshrc`를 source한 뒤 `PROMPT='%~$ '`와 `RPROMPT=''`를 설정
- `install.toml`: `tmux-zshrc` 설치 항목 추가

남은 질문:
- 기존 `~/.zshrc`의 prompt theme 또는 `precmd`가 프롬프트를 다시 덮어쓰는 경우 실제 tmux에서 추가 조정이 필요할 수 있습니다.

## 2026-05-05 - Codex 입력창 줄바꿈

사용자 요청:
- Codex에서 Enter가 바로 전송되는데, 줄바꿈 후 계속 입력하는 방법을 물었습니다.
- Linux 환경에서 `Shift+Enter`가 안 되고 `Ctrl+Enter`만 된다고 했으며, `Shift+Enter`도 줄바꿈으로 쓰고 싶다고 했습니다.

해석/결정:
- 일반적으로 터미널에서 `Shift+Enter`가 `Enter`와 동일하게 전달되어 Codex가 구분하지 못하는 문제로 설명했습니다.
- Codex 자체 설정보다는 터미널 에뮬레이터 키 매핑 문제로 판단했습니다.

작업 결과:
- 즉시 가능한 방법으로 `Ctrl+Enter` 사용을 안내했습니다.
- WezTerm, Kitty 같은 터미널에서는 `Shift+Enter`를 `Ctrl+Enter` 또는 대응 escape sequence로 리매핑할 수 있다고 설명했습니다.

남은 질문:
- 사용자가 실제로 사용하는 터미널 에뮬레이터가 무엇인지 아직 확인되지 않았습니다.
