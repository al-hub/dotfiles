# dotfiles

개인 Linux dotfiles 저장소입니다. 현재는 `install.toml` 목록을 읽어 설치하는 manifest 기반 설치 구조로 관리합니다.

기존 README 내용은 [README.legacy.md](README.legacy.md)에 백업해 두었습니다.
다음 에이전트가 작업 맥락을 이어받기 위한 문서는 [AGENTS.md](AGENTS.md)에 정리합니다.
주요 작업 이력은 [HISTORY.md](HISTORY.md)에 누적합니다.
주제별 대화 맥락은 [CONVERSATION.md](CONVERSATION.md)에 요약합니다.
설치 구조와 모듈 추가 원칙은 [doc/architecture.md](doc/architecture.md)에 정리합니다.

## 빠른 설치

Debian 또는 Ubuntu 계열 PC에서 아래 명령으로 실행합니다.

```sh
curl -fsSL https://raw.githubusercontent.com/al-hub/dotfiles/refs/heads/master/install.sh | bash
```

`install.sh`는 기본적으로 master branch의 최신 `install.toml`을 내려받아 설치 가능한 전체 항목을 보여주고, 사용자가 선택한 항목만 설치합니다.

## 버전 설치

이 저장소는 `v0.1`부터 tag 기반 버전 설치를 지원합니다. 특정 버전을 명시하려면 아래처럼 실행합니다.

```sh
curl -fsSL https://raw.githubusercontent.com/al-hub/dotfiles/refs/heads/master/install.sh | bash -s -- --v v0.1
```

환경변수로도 버전을 지정할 수 있습니다.

```sh
DOTFILES_VERSION=v0.1 bash install.sh
```

명시적으로 최신 master 기준 설치를 요청하려면 아래 옵션을 사용할 수 있습니다.

```sh
curl -fsSL https://raw.githubusercontent.com/al-hub/dotfiles/refs/heads/master/install.sh | bash -s -- --latest
```

설치 시 사용한 버전 또는 branch는 `~/.dotfiles-install/version`에 기록됩니다. 새 버전을 배포할 때는 해당 커밋에 `v0.2` 같은 git tag를 만들고, 사용자가 `--v v0.2`로 설치할 수 있게 합니다.

## 현재 구조

```text
dotfiles/
├── install.sh
├── install.toml
├── dotfiles/
│   ├── opencode.jsonc
│   ├── tmux.conf
│   ├── tmux.zshrc
│   ├── vimrc
│   ├── myrc
│   ├── Xresources
│   └── urxvt/
│       └── ext/
│           └── resize-font
├── scripts/
│   └── tmux-session-launcher
├── get_dotfiles.sh
├── install_dotfiles.sh
├── shortcut.md
└── doc/
    ├── architecture.md
    ├── opencode.md
    └── vim.md
```

`dotfiles/` 디렉터리에는 실제 배포할 설정 파일을 둡니다. `install.toml`은 어떤 파일을 설치할지, 어디에 설치할지, 필요한 실행파일과 패키지가 무엇인지 정의합니다.
모듈이 늘어날수록 설치 구조는 [doc/architecture.md](doc/architecture.md)에서 유지합니다.

## opencode

opencode 설정은 [doc/opencode.md](doc/opencode.md)에 별도로 정리합니다.
현재는 personal-only seed config를 기준으로 두고, `install.toml`에 있는 `opencode` 항목으로 `~/.config/opencode/opencode.jsonc`를 설치합니다.
설치 후 CLI가 없으면 공식 설치 스크립트로 자동 설치합니다.
work profile, 실행 래퍼, allowlist 확장 방향은 [doc/opencode.md](doc/opencode.md)와 [doc/architecture.md](doc/architecture.md)에 남겨둡니다.

## 설치 방식

`install.sh`는 특정 dotfile 전용 스크립트가 아니라 공통 설치 엔진입니다.

- `Enter`, `q`, `quit`, `exit`: 종료
- `all`: enabled 항목만 설치
- `번호`: 선택한 번호만 설치, 예: `1` 또는 `1,3`
- `undo`: manifest에 기록된 설치 파일을 복원하고 설치 상태를 정리
- `clear-state`: 설치 파일은 건드리지 않고 manifest 설치 추적 기록만 삭제

기존 대상 파일이 있고 manifest에 기록된 managed 항목이면 자동으로 백업 후 갱신합니다. 비관리 파일은 덮어쓰기 전에 확인합니다. 백업은 아래 위치에 저장됩니다.

```text
~/.dotfiles-install/backups/
```

설치 상태는 아래 파일에 기록됩니다.

```text
~/.dotfiles-install/manifest.tsv
~/.dotfiles-install/install.toml
```

## 설치 목록 관리

설치 항목은 [install.toml](install.toml)에서 관리합니다.

```toml
[[dotfiles]]
name = "tmux"
enabled = true
source = "dotfiles/tmux.conf"
target = "~/.tmux.conf"
commands = ["tmux", "zsh", "bc", "xclip", "fzf"]
packages = ["tmux", "zsh", "bc", "xclip", "fzf"]
depends = ["tmux-session-launcher", "tmux-zshrc", "urxvt-resize-font", "tmux-xresources"]
description = "tmux configuration"
```

현재 사용자에게 보이는 enabled 항목은 `opencode`와 `tmux`입니다. `opencode`는 선택하면 config를 갱신하고, CLI가 `command -v opencode` 또는 기본 설치 위치(`~/.opencode/bin/opencode`, `~/.local/bin/opencode`, `~/bin/opencode`)에 없을 때만 자동 설치합니다. tmux session launcher, tmux 전용 zsh 초기화 파일, URxvt resize-font extension, Xresources는 hidden dependency로 설치됩니다. Vim, shell 항목은 목록에 있지만 disabled 상태입니다.
이미 manifest에 기록된 managed 항목은 재설치 시 새 버전으로 자동 갱신됩니다. 비관리 기존 파일은 덮어쓰기 전에 확인을 요구합니다.
새 모듈을 넣을 때는 `file / dependency / post-install / external CLI` 중 어느 형태인지 먼저 분류합니다.

tmux는 `ZDOTDIR="$HOME/.cache/dotfiles"`로 zsh를 실행합니다. 이 전용 `.zshrc`는 짧은 `$ ` 프롬프트를 유지하면서 `compinit`을 로드해 git 자동완성을 사용할 수 있게 합니다.

## URxvt font resize

tmux 설치에는 URxvt용 font resize 설정도 hidden dependency로 포함됩니다. URxvt 안에서 tmux를 사용할 때 아래 입력으로 터미널 폰트 크기를 조정합니다.

- `Ctrl+WheelUp`: 확대
- `Ctrl+WheelDown`: 축소
- `Ctrl+WheelClick`: 기본 크기로 복원
- `Ctrl+-`: 축소
- `Ctrl++`: 확대
- `Ctrl+=`: 기본 크기로 복원
- `Ctrl+?`: 현재 크기 표시

이 기능은 tmux가 아니라 URxvt Perl extension이 처리합니다. 설치 중 X 세션에서 실행 중이면 `xrdb -merge ~/.Xresources`를 자동으로 시도하고, X 세션이 아니면 다음 로그인 후 아래 명령을 직접 실행해야 적용됩니다.

```sh
xrdb -merge ~/.Xresources
```

## tmux session launcher

tmux 안에서 `Ctrl+a s`를 누르면 popup 기반 session launcher가 열립니다.

- `Enter`: 선택한 session으로 이동
- `Tab`: `Commands>` / `Sessions>` prompt 전환
- `c`: 새 session 생성
- `d`: 선택한 session 삭제
- `r`: 선택한 session 이름 변경
- `Esc`, `Commands> exit`: 닫기

`c`, `d`, `r`은 `Commands>` prompt에서만 명령으로 동작합니다. `Sessions>` prompt에서는 session 검색 입력으로 처리됩니다.
`Commands>`에서 `create`/`new`, `delete`/`remove`, `rename`, `q`/`quit`/`exit`를 입력하고 `Enter`로 실행할 수도 있습니다. `Commands>`에서 query를 입력한 뒤 `Enter`를 누르면 session row가 보여도 command로만 해석되며, 알 수 없는 명령은 launcher를 닫지 않고 오류만 보여준 뒤 prompt로 돌아갑니다. session 검색 후 이동은 `Sessions>` prompt를 사용해야 합니다.
내부적으로는 `fzf --print-query --expect` 출력의 첫 줄을 query, 둘째 줄을 pressed key로 해석합니다. 이 순서가 바뀌면 `Commands>`의 단축키 입력이 session 이름으로 잘못 해석되어 launcher가 종료될 수 있습니다.

이 기능은 `fzf`가 필요합니다. `install.sh`로 enabled 항목을 설치하면 Debian/Ubuntu 계열에서는 `fzf` 패키지도 함께 설치할 수 있습니다. 직접 설치하려면 아래 명령을 사용합니다.

```sh
sudo apt-get update
sudo apt-get install -y fzf
```

## 로컬 검증

설치 스크립트를 수정한 뒤에는 아래 명령을 실행합니다.

```sh
bash -n install.sh
bash -n scripts/tmux-session-launcher
perl -c dotfiles/urxvt/ext/resize-font
sh -n get_dotfiles.sh
sh -n install_dotfiles.sh
git diff --check
```

`shellcheck`가 설치되어 있다면 아래 검사도 실행합니다.

```sh
shellcheck install.sh get_dotfiles.sh install_dotfiles.sh
```
