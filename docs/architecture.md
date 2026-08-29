# Architecture

dotfiles 저장소의 설치 모델을 모듈 추가 관점에서 정리한다.

## 책임 경계 (SRP)

| 단위 | 단일 책임 | 소유 파일 |
|---|---|---|
| **dotfiles** (`setup.sh`, `install.toml`) | 어떤 모듈을 어느 버전으로 어떤 순서로 설치·갱신·제거하는가 | `~/.dotfiles-install/*` |
| **tmux-session-dock** (upstream) | tmux 안의 모든 UX: `~/.tmux.conf`, 사이드바, 테마, 키바인딩, ergonomics preset | `~/.tmux.conf`, `~/.config/tmux/*`, `~/.local/bin/tmux-*` |
| **urxvt** 모듈 | 터미널 에뮬레이터 층: TrueColor, 폰트, 폰트 줌 | `~/.Xresources`, `~/.urxvt/ext/*` |
| **opencode** 모듈 | OpenCode personal 설정 | `~/.config/opencode/*` |
| **shell** (사용자 `~/.zshrc`, repo 밖) | 프롬프트, 히스토리, completion | `~/.zshrc` |

원칙: 한 파일의 내용이 바뀌는 이유는 하나여야 한다. "tmux 동작을 바꾸고 싶다"는 upstream 저장소, "설치 방식을 바꾸고 싶다"는 dotfiles.

## Install Model

- `setup.sh`는 공통 오케스트레이터다. 모듈 이름을 알지 않는다.
- `install.toml`은 모듈을 선언한다. 필드:
  - 공통: `name`, `type`, `enabled`, `hidden`, `commands`, `packages`, `depends`, `description`
  - `type = "file"`: `source`(repo 경로), `target`(설치 경로), `post_install`(훅 목록)
  - `type = "upstream"`: `repo`(git URL), `dir`(checkout 위치), `min_version`(요구 tag)
- `hidden` 항목은 목록에 보이지 않지만 `depends`로 설치된다.
- 설치 결과는 `~/.dotfiles-install/manifest.tsv`(`name  target  backup  source`)에 기록한다. upstream 모듈은 `source = upstream`.
- 기존 파일은 `~/.dotfiles-install/backups/`로 백업 후 덮어쓴다. uninstall은 manifest를 역순으로 복원한다.

## Module Types

### file
저장소 파일 하나를 대상 경로에 복사한다. 후처리는 `post_install` 훅 어휘로 선언한다.

| 훅 | 동작 |
|---|---|
| `executable` | `chmod +x target` |
| `xrdb-merge` | `DISPLAY`가 있고 `xrdb`가 있으면 `xrdb -merge target` |

새 후처리가 필요하면 훅 어휘를 늘린다. 모듈 이름으로 분기하지 않는다 (OCP).

### upstream
독립 저장소의 공개 CLI 계약에만 의존한다 (DIP).

```
setup.sh install | update | uninstall | purge | status
```

- `DOTFILES_DEV_ROOT/<name>/setup.sh`가 있으면 로컬 checkout 사용, 없으면 `repo`를 `dir`에 clone.
- `install` 후 `git describe --tags --abbrev=0`을 `min_version`과 `sort -V`로 비교. 미달이면 경고.
- `uninstall`/`purge`는 위임한다. dotfiles가 upstream 내부 경로를 직접 지우지 않는다. `purge`는 위임 후 checkout 디렉터리만 제거한다 (dev checkout은 보존).
- `status`/`doctor`는 upstream `setup.sh status` 출력을 그대로 보여준다.

`source`/`target`은 upstream 모듈에 요구하지 않는다 (ISP).

## Version Model

- 현재 안정 버전 `v0.8.0`.
- 기본 실행은 `master` 최신. `setup.sh --v vX.Y.Z`는 raw URL을 `refs/tags/vX.Y.Z`로 계산한다. `--latest`는 `master`.
- `REPO_RAW_URL`, `INSTALL_TOML_URL`로 테스트용 raw URL을 강제할 수 있다.
- 버전 문자열을 바꾸면 같은 커밋에 동일 이름 git tag를 만든다.
- upstream 모듈의 버전은 `install.toml`의 `min_version`으로 고정한다. upstream이 dotfiles가 기대하는 기능(예: preset 키바인딩)을 추가하면 그 tag로 올린다.

## Current Modules

| 모듈 | type | enabled | 비고 |
|---|---|---|---|
| `opencode` | file | yes | personal seed config. CLI 설치는 사용자가 공식 installer로 |
| `tmux-session-dock` | upstream | yes | `min_version = "v0.3.46"`. `~/.tmux.conf` 전체 소유 |
| `urxvt` | file | yes | `xrdb-merge` 훅. hidden 의존성 `urxvt-resize-font`(`executable` 훅) |
| `vim` | file | no | |
| `shell` | file | no | bash 함수 모음 `myrc` |

## Extension Rules

- 새 모듈은 `install.toml` 선언으로 시작한다. `setup.sh` 수정이 필요하면 그 수정은 타입/훅 어휘 확장이어야 하며 모듈 이름 분기가 아니어야 한다.
- 외부 저장소가 자기 setup CLI를 갖고 있으면 `type = "upstream"`으로 소비한다. 그 저장소 내부 파일을 dotfiles가 다시 복사하지 않는다.
- 어떤 설정이 "이 도구 안에서의 UX"라면 그 도구 소유 저장소로 보낸다. dotfiles에 남기는 설정은 다른 소유자가 없는 것만이다.
- 셸 프롬프트/히스토리는 `~/.zshrc`(repo 밖)에서 관리한다. tmux `default-command`로 우회하지 않는다.

## Practical Notes

- upstream tmux-session-dock의 `uninstall`은 tmux 서버를 종료한다. 테스트는 `env -u TMUX HOME=<tmp> TMUX_TMPDIR=<tmp>`로 격리한다.
- upstream 위임 호출은 `</dev/null`로 stdin을 끊는다. `while read` 루프 안에서 호출되므로 stdin을 소비하면 다음 모듈이 건너뛰어진다.
- opencode는 외부 installer를 쓰므로 네트워크와 버전 상태를 같이 고려한다.
