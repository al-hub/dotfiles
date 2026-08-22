# tmux 테마 관리 시스템 계획

## 목표

- tmux 실행 중 테마를 실시간 미리보기하면서 전환할 수 있는 구조 구현
- 외부 플러그인(TPM) 없이 dotfiles 안에서 자체 관리
- 현재 dotfiles 설치 흐름(`install.sh` / `install.toml`)에 자연스럽게 통합

---

## 현재 상태

`dotfiles/tmux.conf`의 스타일 섹션에 Dracula 색상이 하드코딩되어 있음.

```
set -g status-style bg='#44475a',fg='#bd93f9'
set -g window-style bg='#0d1012'
set -g pane-border-style fg='#1b2224',bg='#0b0d0e'
...
```

---

## 목표 디렉터리 구조

```
dotfiles/
├── tmux.conf                        ← 기존 설정 유지, 색상 블록 제거
│                                       마지막에 source-file 한 줄 추가
├── tmux/
│   └── themes/
│       ├── dracula.conf             ← 현재 색상 분리
│       ├── catppuccin-mocha.conf
│       ├── catppuccin-latte.conf
│       ├── tokyonight.conf
│       └── gruvbox.conf
└── scripts/
    └── tmux-theme-picker            ← 실시간 미리보기 선택 스크립트

~/.config/tmux/
└── theme.conf                       ← 현재 활성 테마 (설치 시 생성)
```

---

## 동작 흐름

### 미리보기 및 전환

```
Ctrl+a T
   │
   ▼
tmux-theme-picker 실행 (tmux popup 또는 새 pane)
   │
   ▼
테마 목록 표시 (fzf)
   │
   ├─ 커서 이동 → tmux source-file <해당테마.conf>  → 즉시 미리보기
   │
   ├─ Enter    → ~/.config/tmux/theme.conf 교체
   │              tmux source-file ~/.tmux.conf
   │              → 영구 적용
   │
   └─ Esc/q   → 원래 테마 복원
```

### tmux 시작 시

```
tmux 시작
   └─ tmux.conf 로드
         └─ source-file ~/.config/tmux/theme.conf  ← 마지막 선택 테마 유지
```

---

## 핵심 메커니즘

| 단계 | 방법 | 효과 |
|------|------|------|
| 미리보기 | `tmux source-file <theme>.conf` | 현재 세션 즉시 반영 (임시) |
| 확정 | `~/.config/tmux/theme.conf` 파일 교체 후 reload | 영구 적용 |
| 취소 | 원래 테마 `source-file` | 되돌리기 |

---

## 테마 파일 구성

각 테마 파일은 색상 관련 set 명령만 포함. 예:

```sh
# dracula.conf
set -g status-style          bg='#44475a',fg='#bd93f9'
set -g status-left           '#[bg=#f8f8f2]#[fg=#282a36]#{?client_prefix,#[bg=#ff79c6],}C-a'
set -ga status-left          '#[bg=#44475a]#[fg=#ff79c6]#{?window_zoomed_flag,#[bg=#ff79c6]#[fg=#44475a],} z '
set -g window-status-current-style  fg=black,bg=green
set -g window-style          bg='#0d1012'
set -g window-active-style   bg='#0b0d0e'
set -g pane-border-style     fg='#1b2224',bg='#0b0d0e'
set -g pane-active-border-style fg='#344649',bg='#0d1012'
set -g pane-border-format    "#{?pane_active,#[fg=#d7e1e2]#[bold]#{pane_current_path}#[default],#[fg=#6f7a7b]#{pane_current_path}#[default]}"
```

---

## 포함할 테마 목록 (예정)

| 테마 | 종류 | 색상 출처 |
|------|------|----------|
| dracula | dark | 현재 설정 분리 |
| catppuccin-mocha | dark | catppuccin/tmux README (manual) |
| catppuccin-latte | light | catppuccin/tmux README (manual) |
| tokyonight | dark | tokyonight 색상 팔레트 직접 작성 |
| gruvbox | dark | gruvbox 팔레트 직접 작성 |

> 테마 파일은 플러그인 전체를 가져오지 않고,
> 색상 코드만 추출하여 dotfiles 안에 포함시킴.

---

## install.sh 연동 계획

```sh
# tmux-theme 항목 설치 시
mkdir -p ~/.config/tmux

# 기본 테마(dracula) 활성화
if [ ! -f ~/.config/tmux/theme.conf ]; then
  cp "$DOTFILES/tmux/themes/dracula.conf" ~/.config/tmux/theme.conf
fi
```

- 이미 `theme.conf`가 있으면 덮어쓰지 않음 (사용자가 선택한 테마 유지)
- `install.toml`에 `tmux-theme` 항목으로 별도 관리 예정

---

## tmux.conf 변경 내용

```diff
- set -g status-style bg='#44475a',fg='#bd93f9'
- set -g window-style bg='#0d1012'
- set -g pane-border-style fg='#1b2224',bg='#0b0d0e'
- ...

+ # 테마 (tmux-theme-picker로 전환 가능)
+ if-shell 'test -f ~/.config/tmux/theme.conf' \
+     'source-file ~/.config/tmux/theme.conf'
```

---

## 키바인딩

```sh
# tmux.conf에 추가
bind-key T run-shell "$HOME/.local/bin/tmux-theme-picker"
```

`Ctrl+a T` → 테마 피커 실행

---

## 의존성

| 항목 | 필수 여부 | 비고 |
|------|----------|------|
| fzf | 권장 | 없으면 select/번호 입력 fallback |
| tmux >= 3.0 | 필수 | popup 기능 사용 시 |
| bash | 필수 | 스크립트 런타임 |

---

## 미구현 / 보류 항목

- [ ] 터미널 배경(Xresources) 색상 연동 — tmux 밖 영역이라 별도 처리 필요
- [ ] Neovim 색상 연동 — 각 앱이 독립적으로 관리
- [ ] 테마 자동 업데이트 — 단순성 우선으로 보류

---

## 관련 파일

- [`dotfiles/tmux.conf`](../dotfiles/tmux.conf) — 현재 색상 하드코딩 위치
- [`HISTORY.md`](../HISTORY.md) — 변경 이력
- [`install.toml`](../install.toml) — 설치 항목 정의
