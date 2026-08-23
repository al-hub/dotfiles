# dotfiles

개인 Linux dotfiles 저장소입니다. 현재는 `install.toml` 목록을 읽어 설치하는 manifest 기반 설치 구조로 관리합니다.

기존 README 내용은 [README.legacy.md](README.legacy.md)에 백업해 두었습니다.
다음 에이전트가 작업 맥락을 이어받기 위한 문서는 [AGENTS.md](AGENTS.md)에 정리합니다.
주요 작업 이력은 [HISTORY.md](HISTORY.md)에 누적합니다.
주제별 대화 맥락은 [CONVERSATION.md](CONVERSATION.md)에 요약합니다.
설치 구조와 모듈 추가 원칙은 [docs/architecture.md](docs/architecture.md)에 정리합니다.

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

설치 시 사용한 버전 또는 branch는 `~/.dotfiles-install/version`에 기록됩니다. 현재 sidebar 최적화 기준은 `v0.6.19`이며, 사용자는 `--v v0.6.19`로 고정 설치할 수 있습니다. 성능 비교 리포트는 `tests/profile-reports/`에 버전별로 보관합니다. v0.6.19는 Look-Up Table(LUT) 24프레임 파형 엔진 및 30 FPS 적응형 클록, CJK/Emoji 터미널 너비 안전 토크나이저, 다중 세션 비동기 AI 활동 추적 및 백그라운드 실시간 파형 대시보드, 서브페인 상/하 위치 전환 및 세션 전환 유지, 마우스 리사이즈 너비 영속화, 전역 토폴로지 에포크 프로토콜, 딥 뷰포트 매니저 및 상태 인지 델타 렌더링 파이프라인, 서브페인 제약조건 모델(Default Bottom, Always-OFF, Height-Only Persistence)을 통합 반영하였습니다.

## 로컬 개발 및 테스트 설치

로컬 저장소의 변경 사항을 GitHub에 푸시하지 않고 로컬 파일 시스템에서 직접 참조하여 테스트 설치하려면 `REPO_RAW_URL` 환경 변수를 사용합니다.

```sh
REPO_RAW_URL="file:///home/al-hub/workspace/dotfiles" bash install.sh
```

이렇게 하면 `install.sh`가 로컬 디렉터리의 `install.toml` 및 설정 파일들을 직접 참조하여 설치합니다.

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
│   ├── tmux/
│   │   └── themes/               ← 테마 설정 파일들 (*.conf)
│   └── urxvt/
│       └── ext/
│           └── resize-font
├── scripts/
│   ├── tmux-session-launcher
│   ├── tmux-sidebar-tmux-adapter
│   └── tmux-theme-picker         ← 실시간 테마 피커 스크립트
├── get_dotfiles.sh
├── install_dotfiles.sh
├── shortcut.md
└── docs/
    ├── README.md                 ← 문서 허브 & 용어 사전
    ├── architecture.md           ← 설치 아키텍처
    ├── keybindings.md            ← 주요 단축키 가이드
    ├── guides/                   ← 설정 & 사용 가이드 (opencode, vim, theme 등)
    ├── design/                   ← 단일 사이드바 & 런처 상세 설계
    ├── testing/                  ← 테스트 매트릭스 & 검증 계획
    └── archives/                 ← 과거 분석 & 벤치마크 리포트
```

`dotfiles/` 디렉터리에는 실제 배포할 설정 파일을 둡니다. `install.toml`은 어떤 파일을 설치할지, 어디에 설치할지, 필요한 실행파일과 패키지가 무엇인지 정의합니다.
모듈이 늘어날수록 설치 구조는 [docs/architecture.md](docs/architecture.md)에서 유지합니다.

## opencode

opencode 설정은 [docs/guides/opencode.md](docs/guides/opencode.md)에 별도로 정리합니다.
현재는 personal-only seed config를 기준으로 두고, `install.toml`에 있는 `opencode` 항목으로 `~/.config/opencode/opencode.jsonc`를 설치합니다.
설치 후 CLI가 없으면 공식 설치 스크립트로 자동 설치합니다.
work profile, 실행 래퍼, allowlist 확장 방향은 [docs/guides/opencode.md](docs/guides/opencode.md)와 [docs/architecture.md](docs/architecture.md)에 남겨둡니다.

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
commands = ["tmux", "zsh", "bc", "xclip"]
packages = ["tmux", "zsh", "bc", "xclip"]
depends = ["tmux-session-launcher", "tmux-zshrc", "urxvt-resize-font", "tmux-xresources", "tmux-theme-picker"]
description = "tmux configuration"
```

현재 사용자에게 보이는 enabled 항목은 `opencode`와 `tmux`입니다. `opencode`는 선택하면 config를 갱신하고, CLI가 이미 있으면 재설치하지 않습니다. CLI가 없을 때 원격 설치를 원하면 `DOTFILES_INSTALL_OPENCODE_CLI=true`를 명시해야 합니다. tmux session launcher, tmux 전용 zsh 초기화 파일, URxvt resize-font extension, Xresources, 그리고 tmux-theme-picker는 hidden dependency로 설치됩니다. Vim, shell 항목은 목록에 있지만 disabled 상태입니다.
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

## tmux session launcher & 단축키 안내

> 📖 **전체 상세 단축키 및 마우스 조작 가이드**: [`docs/keybindings.md`](docs/keybindings.md)

tmux 안에서 `Ctrl+a s`를 누르면 현재 window의 제일 왼쪽에 session launcher sidebar가 열립니다.
`Ctrl+a s`는 toggle로 동작하므로, sidebar가 이미 열려 있으면 닫고 없으면 엽니다. tmux 시작 시 sidebar는 자동으로 열리지 않습니다.
상하/좌우로 나뉜 window에서도 sidebar는 전체 높이를 차지하는 왼쪽 pane 하나로 유지됩니다.

- `Enter`: 선택한 session으로 이동
- `j`/`k`, `Up`/`Down`: session 선택 이동
- `c`: 새 session 생성
- `d`: 선택한 session 삭제
- `r`: 선택한 session 이름 변경
- `o`: 삭제한 session history 표시/숨김
- `q`: 닫기
- `Esc`: prompt 취소, history 창 닫기

sidebar에 포커스가 있을 때 `Ctrl+a |`, `Ctrl+a _`, `Ctrl+a %`, `Ctrl+a "`로 pane을 나누면 sidebar가 아니라 오른쪽 작업 영역이 나뉩니다. sidebar에서 다른 session으로 이동하면 target session의 active window에 sidebar를 보장합니다.
sidebar 폭을 직접 조정한 뒤 session을 이동하면, target session의 sidebar도 같은 폭으로 맞춥니다. sidebar를 열고 닫을 때는 sidebar를 제외한 work layout을 저장/복구해 반복 toggle 후에도 기존 pane 비율을 유지합니다.
session 목록은 선택 표시, session 이름, session 생성 후 경과 시간을 `DAY:HH:MM:SS` 형식으로 보여줍니다. 경과 시간은 1초마다 해당 컬럼만 갱신합니다.
mouse 기본 동작은 유지하며, sidebar의 session name 위치를 클릭한 경우에만 해당 session으로 이동합니다.

`d`로 session을 삭제할 때 `y`를 입력하면 `~/.cache/dotfiles/tmux-session-history` 아래에 복원용 metadata를 남기고 삭제합니다. 그냥 `Enter`를 누르면 history 없이 삭제하고, `Esc`는 삭제 prompt만 취소합니다. 현재 session도 삭제할 수 있으며, 다른 session이 남아 있으면 그쪽으로 이동한 뒤 삭제하고 남은 session이 없으면 tmux server를 종료합니다. 삭제 확인 prompt에서 `All`을 입력하면 모든 session 삭제를 진행하며, 이어서 history 저장 여부를 한 번 더 묻습니다.
`o`를 누르면 sidebar 하단 절반에 history 목록이 열립니다. history 목록에서는 `Space`로 여러 항목을 표시하고, `Enter`로 복원하며, `d` 후 `y`로 history 파일을 완전히 삭제합니다. history 창에서 `Esc`를 누르면 history 창만 닫고 기존 sidebar로 돌아갑니다.
복원은 session/window 이름, sidebar를 제외한 pane current path, sidebar-free window layout metadata, 저장된 shell history를 사용해 원래 session 이름으로 새 session을 만듭니다. 저장된 tmux layout은 새 pane id에 맞게 다시 계산해 vertical-only, horizontal-only, mixed split 배치를 유지합니다. 같은 이름의 session이 이미 있으면 복원하지 않습니다. 실행 중이던 process 자체를 되살리지는 않습니다.
이 sidebar는 별도 selector 의존성 없이 tmux와 bash만으로 동작합니다. 각 session의 busy/idle 상태는 내부 snapshot 구조에 포함하지만, 현재 UI에는 표시하지 않습니다.

session 전환 시 target sidebar pane에 refresh signal을 보내 `>`를 빠르게 `>*`로 정렬하고, signal 유실이나 startup race에는 기존 polling이 fallback으로 동작합니다. 운용 개선판의 live 측정은 0.75~0.83초였으며, Bash `read -t` 경계 때문에 수십 ms 수준의 완전 즉시 갱신은 후속 refactoring 과제로 남아 있습니다.
설치 후 이미 실행 중인 sidebar에는 새 코드가 자동 적용되지 않으므로, installer를 다시 실행한 뒤 sidebar를 재시작해야 합니다.

## 로컬 검증

설치 스크립트를 수정한 뒤에는 아래 명령을 실행합니다.

```sh
bash -n install.sh
bash -n scripts/tmux-session-launcher
bash -n scripts/tmux-theme-picker
perl -c dotfiles/urxvt/ext/resize-font
sh -n get_dotfiles.sh
sh -n install_dotfiles.sh
git diff --check
```

`shellcheck`가 설치되어 있다면 아래 검사도 실행합니다.

```sh
shellcheck install.sh get_dotfiles.sh install_dotfiles.sh
```
