# dotfiles 문서

dotfiles는 워크스페이스 오케스트레이터다. 여기 문서는 **설치 모델**만 다룬다. 컴포넌트 동작 문서는 각 소유 저장소에 있다.

## 진입점

- [`architecture.md`](architecture.md): 책임 경계, 설치 모델, 모듈 타입(`file` / `upstream`), 버전 모델, 확장 규칙
- [`keybindings.md`](keybindings.md): URxvt 단축키 + upstream tmux 단축키 문서 링크

## 모듈 가이드 (`guides/`)

- [`guides/opencode.md`](guides/opencode.md): OpenCode 설정
- [`guides/vim.md`](guides/vim.md): Vim 플러그인 및 설정 (모듈 disabled)

## upstream 문서 (tmux)

tmux 설정, 사이드바 세션 도크, 테마, 용어 사전은 [`tmux-session-dock`](https://github.com/al-hub/tmux-session-dock)에 있다.

- [`README.ko.md`](https://github.com/al-hub/tmux-session-dock/blob/master/README.ko.md)
- [`docs/ARCHITECTURE.md`](https://github.com/al-hub/tmux-session-dock/blob/master/docs/ARCHITECTURE.md)
- [`docs/KEYBINDINGS.md`](https://github.com/al-hub/tmux-session-dock/blob/master/docs/KEYBINDINGS.md)
- [`docs/THEMES.md`](https://github.com/al-hub/tmux-session-dock/blob/master/docs/THEMES.md)
- [`CONTEXT.md`](https://github.com/al-hub/tmux-session-dock/blob/master/CONTEXT.md): 도메인 용어 (Presenter Window, Subpane Pool/Slot/Lease, Hub Keeper 등)

분리 전(v0.7.0 이전) 사이드바 엔진 설계·테스트·프로파일링 문서는 v0.8.0에서 제거했다. 필요하면 git history(`git log --all -- docs/design docs/testing docs/archives`)에서 본다.
