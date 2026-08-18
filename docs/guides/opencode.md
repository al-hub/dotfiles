# opencode

이 문서는 opencode 설정의 현재 상태와 앞으로의 확장 방향을 정리합니다.
설치 구조 전체 관점은 [docs/architecture.md](../architecture.md)를 함께 본다.

## 현재 상태

- 현재 레포에는 [`dotfiles/opencode.jsonc`](../../dotfiles/opencode.jsonc) 하나가 있고, `install.toml`의 `opencode` 항목으로 설치합니다.
- 이 파일은 personal seed configuration으로 본다.
- 업무용 profile이나 실행 래퍼는 아직 만들지 않는다.
- CLI는 공식 설치 스크립트 `curl -fsSL https://opencode.ai/install | bash`로 설치한다.
- 설치 항목을 한 번 선택하면 config를 갱신하고, CLI가 `command -v opencode` 또는 기본 설치 위치(`~/.opencode/bin/opencode`, `~/.local/bin/opencode`, `~/bin/opencode`)에 없을 때만 자동 설치한다.

## 설계 방향

- 지금은 personal-only로 시작한다.
- 나중에 work profile을 붙일 수 있도록 파일 배치와 주석만 미리 남긴다.
- 복잡한 분기보다 단순한 기본값을 우선한다.
- 설정은 한 번에 완성형으로 만들지 않고, 점진적으로 확장한다.
- 추후 `oh my openagent`를 검토할 수 있지만, 현재는 저장소 자체 설정으로 운영한다.
- [`docs/architecture.md`](../architecture.md)의 module shape 규칙을 따른다.

## 확장 지점

- personal config
  - 현재 `dotfiles/opencode.jsonc`를 중심으로 유지한다.
- work config
  - 필요해지면 allowlist 중심의 별도 파일로 분리한다.
- agent/instructions
  - 개인용 워크플로 문서, command, handoff 규칙을 추가할 수 있다.
- environment
  - provider별 API key와 config dir 전환을 나중에 분리한다.
- cli lifecycle
  - CLI 존재 여부만 자동 판단하고, 버전 관리나 강제 재설치는 이후 확장으로 남긴다.

## 메모

- 이 저장소는 tmux처럼 "보이는 진입점은 하나, 내부 구성은 단계적으로 추가"하는 방식을 선호한다.
- opencode도 같은 원칙을 따르되, 지금은 문서와 개인용 seed config만 유지한다.
