# dotfiles

개인 Linux dotfiles 저장소입니다. 현재는 `install.toml` 목록을 읽어 설치하는 manifest 기반 설치 구조로 관리합니다.

기존 README 내용은 [README.legacy.md](README.legacy.md)에 백업해 두었습니다.
다음 에이전트가 작업 맥락을 이어받기 위한 문서는 [AGENTS.md](AGENTS.md)에 정리합니다.
주요 작업 이력은 [HISTORY.md](HISTORY.md)에 누적합니다.
주제별 대화 맥락은 [CONVERSATION.md](CONVERSATION.md)에 요약합니다.

## 빠른 설치

Debian 또는 Ubuntu 계열 PC에서 아래 명령으로 실행합니다.

```sh
curl -fsSL https://raw.githubusercontent.com/al-hub/dotfiles/refs/heads/master/install.sh | bash
```

`install.sh`는 `install.toml`을 내려받아 설치 가능한 전체 항목을 보여주고, 사용자가 선택한 항목만 설치합니다.

## 현재 구조

```text
dotfiles/
├── install.sh
├── install.toml
├── dotfiles/
│   ├── tmux.conf
│   ├── vimrc
│   ├── myrc
│   └── Xresources
├── scripts/
│   └── tmux-session-launcher
├── get_dotfiles.sh
├── install_dotfiles.sh
├── shortcut.md
└── doc/
    └── vim.md
```

`dotfiles/` 디렉터리에는 실제 배포할 설정 파일을 둡니다. `install.toml`은 어떤 파일을 설치할지, 어디에 설치할지, 필요한 실행파일과 패키지가 무엇인지 정의합니다.

## 설치 방식

`install.sh`는 특정 dotfile 전용 스크립트가 아니라 공통 설치 엔진입니다.

- `Enter` 또는 `all`: enabled 항목만 설치
- `번호`: 선택한 번호만 설치, 예: `1` 또는 `1,3`
- `init`: manifest에 기록된 설치 파일을 복원하거나 제거
- `q`, `quit`, `exit`: 종료

기존 대상 파일이 있으면 덮어쓰기 전에 확인합니다. 강제 설치를 선택하면 기존 파일은 아래 위치에 백업됩니다.

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
description = "tmux configuration"
```

현재 enabled 항목은 tmux와 tmux session launcher입니다. Vim, shell, Xresources 항목은 목록에 있지만 disabled 상태입니다.
이미 manifest에 기록된 managed 항목은 재설치 시 새 버전으로 자동 갱신됩니다. 비관리 기존 파일은 덮어쓰기 전에 확인을 요구합니다.

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
sh -n get_dotfiles.sh
sh -n install_dotfiles.sh
git diff --check
```

`shellcheck`가 설치되어 있다면 아래 검사도 실행합니다.

```sh
shellcheck install.sh get_dotfiles.sh install_dotfiles.sh
```
