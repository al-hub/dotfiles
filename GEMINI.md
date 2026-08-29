# Agent Handoff

다음 에이전트는 이 파일을 먼저 읽고, 세부 내용은 아래 문서로 이동하세요.

## 빠른 상태

- 개인 Linux dotfiles 저장소. 역할은 **워크스페이스 오케스트레이터**: 모듈을 어느 버전으로 어떤 순서로 설치·갱신·제거하는가만 책임진다.
- 진입점은 `./setup.sh` (install / update / uninstall / purge / status / doctor)와 `install.toml`. `setup`, `install.sh`, `uninstall.sh`는 `setup.sh` 심볼릭 링크.
- 모듈 타입은 두 가지. `type = "file"`(저장소 파일 복사, `post_install` 훅)과 `type = "upstream"`(독립 저장소 clone 후 그 저장소의 공개 CLI `setup.sh install|update|uninstall|purge|status`에 위임, `min_version` 게이트).
- **tmux 설정은 dotfiles에 없다.** `~/.tmux.conf`, `~/.config/tmux/*`, `~/.local/bin/tmux-*`, 사이드바/테마/키바인딩 전부 upstream [`tmux-session-dock`](https://github.com/al-hub/tmux-session-dock) 소유. dotfiles는 `tmux-session-dock` upstream 모듈 하나로 소비만 한다. tmux 동작을 바꾸려면 upstream 저장소에서 작업한다.
- enabled 모듈: `opencode`(file), `tmux-session-dock`(upstream, min `v0.3.46`), `urxvt`(file, hidden 의존성 `urxvt-resize-font`). disabled: `vim`, `shell`.
- 현재 안정 버전 `v0.8.0`. `setup.sh --v vX.Y.Z`는 GitHub raw URL을 `refs/tags/` 기준으로 계산한다. 버전 문자열을 바꾸면 같은 커밋에 동일 이름 tag를 만든다.
- `DOTFILES_DEV_ROOT`(기본 `~/workspace`) 아래 `<module>/setup.sh`가 있으면 clone 대신 로컬 checkout을 쓴다. 이 머신은 `~/workspace/tmux-session-dock`을 쓴다.

## 문서 역할

- `AGENTS.md` (= `GEMINI.md`, 동일 내용 유지): 현재 상태와 작업 규칙 색인
- `HISTORY.md`: 파일/설정 변경 이력
- `CONVERSATION.md`: 사용자 의도와 의사결정 맥락
- `README.md`: 사용자용 설치/구조 안내
- `docs/README.md`: 문서 색인
- `docs/architecture.md`: 설치 모델, 모듈 타입, 확장 규칙, SOLID 경계
- `docs/keybindings.md`: URxvt 단축키 + upstream tmux 단축키 문서 링크
- `docs/guides/opencode.md`, `docs/guides/vim.md`: 모듈별 가이드
- `tests/run-tests.sh`: 오케스트레이터 계약 검증 (구문, install.toml 스키마, 의존성 해석, tmux 설정 부재, read-only CLI)

## 작업 규칙

- 작업 전 `git status --short`로 기존 변경을 확인한다.
- 의미 있는 파일/설정 변경 후 `HISTORY.md`에 이력을 추가한다.
- 작업 방향에 영향을 준 사용자 의도나 결정은 `CONVERSATION.md`에 요약한다. 원문 대화 전체는 저장하지 않는다.
- 레거시 스크립트 `install_dotfiles.sh`, `get_dotfiles.sh`는 자동 실행하지 않는다 (구문 검사만).
- tmux 관련 요청은 upstream 저장소 범위인지 먼저 판단한다. dotfiles에 tmux 설정 파일을 다시 만들지 않는다.
- 새 모듈은 `install.toml` 선언으로 추가한다. `setup.sh`에 모듈 이름 분기(case)를 넣지 않는다. 필요한 후처리는 `post_install` 훅 어휘를 확장한다.
- upstream 모듈은 공개 CLI만 호출한다. upstream 내부 경로(`~/.local/bin/...`, `~/.config/tmux/...`)를 `setup.sh`에서 직접 rm/편집하지 않는다.
- `uninstall`/`purge`는 upstream tmux-session-dock이 tmux 서버를 종료한다. 테스트는 격리된 `HOME`, `TMUX_TMPDIR`, `env -u TMUX`로 실행한다. 실제 사용자 tmux 서버에 닿지 않게 한다.

## 검증

```sh
bash tests/run-tests.sh
git diff --check
```

격리 E2E (실제 홈 오염 없음):

```sh
T=$(mktemp -d)
env -u TMUX HOME="$T" TMUX_TMPDIR="$T" STATE_DIR="$T/.dotfiles-install" DOTFILES_DEV_ROOT=/nonexistent ./setup.sh install --all
cat "$T/.tmux.conf"        # upstream 마커 블록만 존재
env -u TMUX HOME="$T" TMUX_TMPDIR="$T" STATE_DIR="$T/.dotfiles-install" DOTFILES_DEV_ROOT=/nonexistent ./setup.sh purge
rm -rf "$T"
```

알려진 upstream 동작: `tmux-session-dock/setup.sh uninstall`의 `pkill -f tmux-session-dock`이 자기 자신을 종료해 `Terminated`가 찍히고 비정상 종료 코드를 돌려준다. 정리 자체는 그 전에 끝난다. dotfiles는 `[WARN]`으로 기록만 한다.
