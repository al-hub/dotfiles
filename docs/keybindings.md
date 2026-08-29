# 단축키

## tmux

tmux 단축키(prefix `Ctrl+a`, 사이드바 `s`, 테마 `T`, 팔레트 `/`, 도움말 `h`, safe split, `Alt+화살표` 이동, `Ctrl+Alt+화살표` 스왑, `Tab`/`Shift+Tab` 윈도우 이동, 사이드바 내부 TUI 키)는 전부 upstream이 정의한다.

- https://github.com/al-hub/tmux-session-dock/blob/master/docs/KEYBINDINGS.md
- tmux 안에서: `Ctrl+a h` (도움말 팝업), `Ctrl+a /` (커맨드 팔레트)

dotfiles는 tmux 키를 추가하지 않는다.

## URxvt (dotfiles `urxvt` 모듈)

URxvt Perl 확장 `resize-font`가 처리한다. tmux와 무관.

| 조작 | 기능 |
|---|---|
| `Ctrl + WheelUp` | 폰트 확대 |
| `Ctrl + WheelDown` | 폰트 축소 |
| `Ctrl + WheelClick` | 기본 크기 |
| `Ctrl + -` / `Ctrl + +` | 축소 / 확대 |
| `Ctrl + =` | 기본 크기 |
| `Ctrl + ?` | 현재 크기 표시 |

적용: X 세션에서 `xrdb -merge ~/.Xresources` 후 새 URxvt 창.
