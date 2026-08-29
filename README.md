# dotfiles

개인 Linux 개발 환경의 **워크스페이스 오케스트레이터**입니다. `install.toml`에 선언한 모듈을 `setup.sh`가 설치·갱신·제거합니다.

dotfiles는 "무엇을, 어느 버전으로, 어떤 순서로 설치하는가"만 책임집니다. 각 컴포넌트의 동작(예: tmux 키바인딩)은 컴포넌트 소유자가 책임집니다. tmux 관련 설정은 전부 독립 저장소 [`tmux-session-dock`](https://github.com/al-hub/tmux-session-dock)이 소유하며, dotfiles에는 tmux 설정 파일이 없습니다.

- 에이전트 handoff: [AGENTS.md](AGENTS.md)
- 변경 이력: [HISTORY.md](HISTORY.md) / 의사결정 맥락: [CONVERSATION.md](CONVERSATION.md)
- 설치 모델과 모듈 추가 원칙: [docs/architecture.md](docs/architecture.md)
- 구 README: [README.legacy.md](README.legacy.md)

## 빠른 설치

Debian / Ubuntu 계열.

```sh
curl -fsSL https://raw.githubusercontent.com/al-hub/dotfiles/refs/heads/master/setup.sh | bash
```

## 라이프사이클 명령

```sh
# 특정 릴리스 tag 기준 설치 (현재 안정 기준: v0.8.0)
curl -fsSL https://raw.githubusercontent.com/al-hub/dotfiles/refs/heads/master/setup.sh | bash -s -- --v v0.8.0

./setup.sh install    # enabled 모듈 설치. upstream 모듈은 해당 저장소의 setup.sh에 위임
./setup.sh update     # dotfiles pull + upstream 모듈 update + 재설치
./setup.sh uninstall  # manifest 기준 복원. upstream 모듈은 소유자 uninstall 호출
./setup.sh purge      # uninstall + 백업/상태/upstream checkout 제거
./setup.sh status     # 모듈 표 (상태, 타입, 명령, 관리 여부, 버전)
./setup.sh doctor     # 필수 명령 + upstream 버전 게이트 + 위임 status
```

옵션: `--skip-upstream` (upstream 모듈 건너뜀), `--v TAG`, `--latest`.
환경변수: `DOTFILES_DEV_ROOT` (기본 `~/workspace`) 아래에 `<module>/setup.sh`가 있으면 clone 대신 그 checkout을 사용합니다.

> `uninstall`/`purge`는 upstream `tmux-session-dock` 제거 시 tmux 서버를 종료합니다. tmux 밖에서 실행하세요.

## 구조

```text
dotfiles/
├── setup.sh              ← 오케스트레이터 (install / update / uninstall / purge / status / doctor)
├── setup, install.sh, uninstall.sh   ← setup.sh 심볼릭 링크 (하위 호환)
├── install.toml          ← 모듈 선언 (type, source/target 또는 repo/dir, depends, min_version)
├── dotfiles/
│   ├── opencode.jsonc    ← OpenCode personal 설정
│   ├── Xresources        ← URxvt TrueColor / 폰트
│   ├── urxvt/ext/resize-font  ← URxvt Ctrl+휠 폰트 크기 Perl 확장
│   ├── vimrc             ← Vim (disabled)
│   └── myrc              ← 공용 셸 함수 (disabled)
├── tests/run-tests.sh    ← 오케스트레이터 계약 검증
└── docs/                 ← 설치 모델 문서
```

## 모듈

| 모듈 | type | 상태 | 대상 |
|---|---|---|---|
| `opencode` | file | enabled | `~/.config/opencode/opencode.jsonc` |
| `tmux-session-dock` | upstream | enabled | `~/.local/share/tmux-session-dock` (소유: `~/.tmux.conf`, `~/.config/tmux/*`, `~/.local/bin/tmux-*`) |
| `urxvt` | file | enabled | `~/.Xresources` (+ hidden `urxvt-resize-font` → `~/.urxvt/ext/resize-font`) |
| `vim` | file | disabled | `~/.vimrc` |
| `shell` | file | disabled | `~/.myrc` |

### 모듈 타입

- **file**: 저장소 파일을 `target`으로 복사. 기존 파일은 `~/.dotfiles-install/backups/`에 백업. `post_install` 훅: `executable`, `xrdb-merge`.
- **upstream**: 독립 저장소를 `dir`에 clone하고 그 저장소의 공개 CLI `setup.sh install|update|uninstall|purge|status`만 호출. 내부 경로를 dotfiles가 알지 않습니다. `min_version`은 `git describe --tags`와 비교해 미달 시 경고.

```toml
[[dotfiles]]
name = "tmux-session-dock"
type = "upstream"
enabled = true
repo = "https://github.com/al-hub/tmux-session-dock.git"
dir = "~/.local/share/tmux-session-dock"
min_version = "v0.3.46"
commands = ["tmux", "bash", "git"]
```

설치 상태는 `~/.dotfiles-install/manifest.tsv`에 기록됩니다. upstream 모듈은 `source = upstream` 행으로 기록되어 uninstall 시 소유자에게 위임됩니다.

## tmux

tmux 설정, 사이드바 세션 도크, 테마, 단축키는 모두 upstream이 제공합니다.

- 저장소: https://github.com/al-hub/tmux-session-dock
- 단축키: [`docs/KEYBINDINGS.md`](https://github.com/al-hub/tmux-session-dock/blob/master/docs/KEYBINDINGS.md)
- 테마: [`docs/THEMES.md`](https://github.com/al-hub/tmux-session-dock/blob/master/docs/THEMES.md)

`~/.tmux.conf`는 upstream `setup.sh install`이 마커 블록(`# >>> tmux-session-dock configuration >>>`)으로 관리합니다. 개인 추가 설정은 그 블록 밖에 직접 적으면 유지됩니다. tmux 안 zsh 프롬프트 등 셸 설정은 `~/.zshrc`에서 관리합니다 (repo 밖).

## URxvt

`urxvt` 모듈이 `~/.Xresources`와 resize-font 확장을 설치합니다. X 세션 안에서 설치하면 `xrdb -merge`를 자동 시도하고, 아니면 다음 로그인 후 직접 실행합니다.

```sh
xrdb -merge ~/.Xresources
```

- `Ctrl+WheelUp` / `Ctrl+WheelDown`: 확대 / 축소
- `Ctrl+WheelClick`, `Ctrl+=`: 기본 크기
- `Ctrl+-` / `Ctrl++`: 축소 / 확대
- `Ctrl+?`: 현재 크기 표시

## opencode

[docs/guides/opencode.md](docs/guides/opencode.md) 참고. `install.toml`의 `opencode` 항목이 `~/.config/opencode/opencode.jsonc`를 설치합니다.

## 검증

```sh
bash tests/run-tests.sh
```
