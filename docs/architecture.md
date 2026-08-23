# Architecture

이 문서는 dotfiles 저장소의 설치 구조를 모듈 추가 관점에서 정리합니다.

## Install Model

- `install.sh`는 공통 설치 엔진이다.
- `install.toml`은 설치할 항목, 대상 경로, 의존성, 패키지 요구사항을 정의한다.
- hidden 항목은 목록에서 숨기지만 dependency로는 설치될 수 있다.
- managed 항목은 재설치 시 기존 파일을 백업하고 갱신한다.

## Version Model

- 현재 안정 설치 버전은 `v0.6.21` (v6.21)이다.
- `install.sh` 기본 실행은 `master` 최신 커밋을 기준으로 동작한다.
- `install.sh --v v0.6.21` 또는 `install.sh --version v0.6.21`은 GitHub raw URL을 `refs/tags/v0.6.21` 기준으로 계산한다.
- `install.sh --latest`는 명시적으로 `master` branch 기준으로 설치한다.
- `REPO_RAW_URL`이나 `INSTALL_TOML_URL`을 직접 지정하면 테스트용 raw URL을 강제로 사용할 수 있다.
- 새 버전을 배포할 때는 버전 문자열만 바꾸는 것으로 끝내지 말고, 해당 커밋에 같은 이름의 git tag를 만들어야 한다.

## Module Shapes

- file module
  - repo 안의 설정 파일 하나를 대상 경로에 복사한다.
- hidden dependency
  - 사용자에게 직접 노출하지 않지만, 상위 모듈의 필수 구성요소로 설치된다.
- hybrid module
  - 설정 파일과 외부 CLI/런타임 후처리를 함께 가진다.

## Current Modules

### tmux & Session Sidebar Ecosystem

- **Visible Top-Level Module**: `dotfiles/tmux.conf` 및 런타임 훅 설치.
- **Window-Local Presenter Model**: 각 관리 대상 윈도우마다 고정 Presenter Pane(`dotfiles-session-sidebar`) 상주.
- **Global Singleton Subpane Hub**: `dotfiles-subpane-hub`를 통한 단일 물리 서브페인 프로세스 원자적 임대(`@dotfiles_subpane_lease_window`).
- **10 Core Modular Architecture (`scripts/lib/*.sh`)**:
  - `sidebar_domain*.sh`: 순수 도메인 헬퍼, 24프레임 LUT 웨이브폼 엔진(30 FPS), AI 활동 상태 머신.
  - `sidebar_coordinator.sh` / `sidebar_presenter.sh`: 선택 정렬 리듀서, 마커 델타 계산, 뷰 템플릿.
  - `sidebar_port_tmux.sh` / `sidebar_subpane_hub.sh`: 소켓 격리 Tmux 어댑터, 싱글톤 허브 수명주기, tmux 3.2a 보정.
  - `sidebar_switch.sh` / `sidebar_archive.sh` / `sidebar_topology.sh`: Native 전환 파이프라인(0.75ms Fast-Path), Version 3 아카이브 직렬화, 토폴로지 분석기.

### opencode

- visible top-level module
- personal config file을 설치한다.
- CLI가 `command -v opencode` 또는 기본 설치 위치(`~/.opencode/bin/opencode`, `~/.local/bin/opencode`, `~/bin/opencode`)에 없으면 공식 installer를 실행한다.
- 나중에 work profile, allowlist, commands/instructions로 확장할 수 있다.

## Extension Rules

- 새 모듈은 가능한 한 `file module`로 시작한다.
- 외부 CLI가 필요하면 hidden dependency나 post-install hook으로 분리한다.
- dependency는 단순한 문자열 나열이 아니라 그래프로 다룰 가능성을 염두에 둔다.
- 후처리는 `install.sh`의 중앙 `case`를 무한히 키우지 말고, 모듈별로 좁혀간다.

## Practical Notes

- tmux는 내부 생태계가 크므로 hidden dependency가 많아질 수 있다.
- opencode는 외부 installer를 쓰므로 네트워크와 버전 상태를 같이 고려해야 한다.
- 앞으로 새 모듈을 추가할 때는 "설정만 필요한지", "CLI가 필요한지", "실행 후처리가 필요한지"를 먼저 나눈다.
