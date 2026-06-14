# Architecture

이 문서는 dotfiles 저장소의 설치 구조를 모듈 추가 관점에서 정리합니다.

## Install Model

- `install.sh`는 공통 설치 엔진이다.
- `install.toml`은 설치할 항목, 대상 경로, 의존성, 패키지 요구사항을 정의한다.
- hidden 항목은 목록에서 숨기지만 dependency로는 설치될 수 있다.
- managed 항목은 재설치 시 기존 파일을 백업하고 갱신한다.

## Module Shapes

- file module
  - repo 안의 설정 파일 하나를 대상 경로에 복사한다.
- hidden dependency
  - 사용자에게 직접 노출하지 않지만, 상위 모듈의 필수 구성요소로 설치된다.
- hybrid module
  - 설정 파일과 외부 CLI/런타임 후처리를 함께 가진다.

## Current Modules

### tmux

- visible top-level module
- config file, hidden dependencies, runtime hook을 모두 가진다.
- tmux server 재시작, executable bit 조정, Xresources 로딩 같은 후처리가 있다.

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
