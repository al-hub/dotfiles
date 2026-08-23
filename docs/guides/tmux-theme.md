# tmux 테마 관리 시스템 가이드 (tmux Theme System Guide)

이 문서는 `dotfiles`에 추가된 tmux 실시간 테마 전환 시스템의 작동 방법, 로컬 설치 테스트 가이드, 테마 편집/복제 기능, 그리고 새로 설계된 시력 보호 테마 3종의 과학적 근거를 설명합니다.

---

## 1. 로컬 설치 테스트 가이드 (Local Verification)

본 프로젝트의 `install.sh`는 기본적으로 원격 GitHub 저장소의 최신 버전 파일들을 조회 및 다운로드하여 배포합니다. 로컬에서 수정한 내용을 실제 환경에 빌드하여 테스트하려면 아래 두 가지 방법 중 하나를 선택해 진행할 수 있습니다.

### 방법 A: `file://` 스킴을 통한 로컬 저장소 강제 주입 (권장)
로컬 저장소의 절대 경로를 환경변수 `REPO_RAW_URL` 및 `INSTALL_TOML_URL`에 바인딩하여 실행하면, `install.sh`가 외부 네트워크를 통하지 않고 로컬 디렉터리 내의 최신 변경 내용을 읽어와 설치합니다.

```bash
# 1. dotfiles 루트 디렉터리로 이동
cd /home/al-hub/workspace/dotfiles

# 2. 로컬 파일을 읽어들여 설치 실행
REPO_RAW_URL="file://$(pwd)" INSTALL_TOML_URL="file://$(pwd)/install.toml" ./install.sh
```
* 대화형 메뉴가 표시되면 **`tmux`** 항목(목록 번호)을 선택하여 설치를 진행합니다.
* 설치가 완료되면 스크립트가 실행 권한을 부여하고, `~/.config/tmux/themes/` 아래에 14개의 테마 설정 파일(`*.conf`)이 복사됩니다.

### 방법 B: 격리된 tmux 테스트 소켓으로 확인
현재 메인 tmux 서버 환경에 영향을 미치지 않고, 새로 작성된 테마 피커와 popup 바인딩을 독립적으로 테스트하려면 격리된 소켓명(`-L`)을 임의로 주어 테스트 세션을 시작합니다.

```bash
# 격리된 소켓으로 테스트 세션 실행
tmux -L codex-dotfiles-test -f dotfiles/tmux.conf new-session
```
* 실행 후 **`Ctrl+a T`** 단축키를 입력하면 화면 중앙에 팝업창으로 테마 피커가 구동됩니다.
* 테스트 소켓을 종료하려면 `exit` 또는 `tmux -L codex-dotfiles-test kill-server` 명령을 수행합니다.

---

## 2. 기존 테마 편집 및 신규 테마 추가 방법 (Clone & Edit)

테마 피커(`tmux-theme-picker`)를 실행하면 활성화된 테마 목록 중에서 직접 복제 및 수정을 진행할 수 있습니다.

1. **`Ctrl+a T`** 단축키로 테마 피커를 실행합니다.
2. 목록에서 복제의 기준(Baseline)이 될 테마를 방향키로 선택합니다.
3. **`Ctrl+e`** 단축키를 누르면, 피커가 종료되고 쉘 환경에서 새 테마의 이름을 묻는 프롬프트가 표시됩니다.
   * `Enter new theme name (a-z, 0-9, -, _):`
4. 새 이름을 입력하면, 선택했던 테마의 설정 내용이 복사되어 `~/.config/tmux/themes/<새이름>.conf` 파일로 즉시 생성되며, 시스템 기본 에디터(`vi`)로 자동 열립니다.
5. 에디터에서 원하는 색상 및 설정을 수정한 뒤 저장 후 종료(`:wq`)합니다.
6. 에디터가 닫히면 프롬프트에 `Do you want to apply this new theme now? [y/N]`가 출력됩니다. `y`를 누르면 즉시 해당 테마로 tmux가 전환되며 `~/.config/tmux/theme.conf`에 영구 적용됩니다.

---

## 3. 테마 명명 체계 및 포커스 페어링 규칙 (Canonical 3-Tier Taxonomy)

모든 테마 파일은 3단계 계층 구조를 따르도록 표준화되어 있습니다:
$$\mathbf{규칙:\quad} \texttt{<카테고리>-<패밀리>[-<서브스타일>][-<변형>].conf}$$

* **카테고리 접두사**: `base-` (기본), `open-` (오픈소스 명작), `code-` (코딩/셸), `eye-` (시력보호), `disp-` (디스플레이/조도), `os-` (운영체제), `retro-` (레트로 하드웨어)
* **포커스 1:1 페어링**: 모든 `-focus` 테마는 대응하는 Standard 테마의 전체 이름 뒤에 `-focus`를 결합하여 완벽한 1:1 페어를 이룹니다.

---

## 4. 시력 보호 테마 (Eye-Care Series: 기본 & 포커스 특화 6종)

사용자의 안구 건강 및 시인성 향상을 위해 최신 안과학 및 생체 리듬 연구 논문을 기초로 설계된 3가지 테마 및 활성/비활성 페인 음영 대비를 극대화한 포커스 특화(-focus) 테마 3종입니다.

### 테마 1. Astigmatism-Safe (난시 예방 & 하일레이션 방지)
* **파일명**: `eye-astigmatism-safe.conf` & `eye-astigmatism-safe-focus.conf`
* **과학적 근거**: 순백색 대신 편안한 회백색(#e0e0e0) 글씨와 차분한 어두운 그레이(#20222c) 배경을 활용하여 눈부심과 빛 번짐을 원천 억제합니다. Focus 버전에서는 활성 페인에 실버/오프화이트 보더를 부여합니다.

### 테마 2. Circadian-Warm (생체 리듬 보존 및 청색광 차단)
* **파일명**: `eye-circadian-warm.conf` & `eye-circadian-warm-focus.conf`
* **과학적 근거**: 청색(Blue) 계열 파장을 배제하고, 2700K 대역의 호박색(Amber) 및 소프트 오렌지만을 조합하여 야간 코딩 시 멜라토닌 분비 억제를 막아줍니다. Focus 버전에서는 활성 페인에 앰버 골드 보더를 적용합니다.

### 테마 3. Scotopic-Forest (야간 암순응 및 간상세포 순응)
* **파일명**: `eye-scotopic-forest.conf` & `eye-scotopic-forest-focus.conf`
* **과학적 근거**: 어두운 조도에서 간상세포가 가장 민감하게 반응하는 연한 세이지/허브 그린(#a3be8c) 텍스트를 활용하여 광량 피로도를 최소화합니다. Focus 버전에서는 활성 페인에 허브 그린 액센트 보더를 적용합니다.

---

## 5. 코딩 및 셸 전용 테마 5종

* **`code-windows-terminal.conf`**: Windows Terminal Campbell `#0C0C0C` 딥 차콜 블랙 & 윈도우 액센트 블루(`#0078D7`), 시안(`#61D6D6`) 보더.
* **`code-powershell.conf`**: Windows PowerShell 딥 네이비 블루(`#012456`) & 옐로우(`#ffff00`), 애저 스카이 블루(`#00a2ed`).
* **`code-cyberpunk-neon.conf`**: 딥 바이올렛 `#0f0b15` & 강렬한 네온 핑크/시안.
* **`code-monokai-pro.conf`**: 톤다운 파스텔 옐로우/그린 다크 프로페셔널.
* **`code-github-light.conf`**: 주간 자연광 및 사무실 환경용 클래식 화이트.

---

## 6. 글로벌 오픈소스 & 포커스 대비 특화 테마 (Open & Focus Series: 20종)

Reddit의 r/unixporn, r/tmux, r/neovim 등에서 사랑받는 명품 오픈소스 테마 10종과, **활성 페인(Focused)과 비활성 페인(Unfocused) 간의 음영 및 보더 대비를 극대화한 포커스 특화(-focus) 테마 10종**을 제공합니다.

1. **Dracula** (글로벌 1위 다크): `open-dracula.conf` & `open-dracula-focus.conf`
2. **Kanagawa** (우키요에 와비사비): `open-kanagawa.conf` & `open-kanagawa-focus.conf`
3. **Everforest** (자연주의 포레스트): `open-everforest.conf` & `open-everforest-focus.conf`
4. **Catppuccin Mocha**: `open-catppuccin-mocha.conf` & `open-catppuccin-mocha-focus.conf`
5. **Nord**: `open-nord.conf` & `open-nord-focus.conf`
6. **One Dark**: `open-onedark.conf` & `open-onedark-focus.conf`
7. **Gruvbox**: `open-gruvbox.conf` & `open-gruvbox-focus.conf`
8. **Tokyo Night**: `open-tokyonight.conf` & `open-tokyonight-focus.conf`
9. **Rosé Pine**: `open-rose-pine.conf` & `open-rose-pine-focus.conf`
10. **Solarized Dark**: `open-solarized-dark.conf` & `open-solarized-dark-focus.conf`

---

## 7. 특수 디스플레이 & 접근성 특화 테마 (Display & Accessibility)

* **`disp-oled-pureblack.conf`**: OLED 100% True Black(`#000000`) 배경으로 소자 전원 차단 $\to$ 배터리 절전 및 무한 명암비.
* **`disp-paper-sepia.conf`**: 주간 창가/자연광 환경에서 눈부심을 차단하는 킨들 전자책 & 양피지 크림(`#fbf0d9`) + 에스프레소 잉크(`#433422`).

---

## 8. OS & 레트로 플랫폼 시그니처 테마 (OS & Retro Heritage)

* **`os-ubuntu-aubergine.conf`**: Canonical Ubuntu 공식 딥 오베르진(`#300a24`) + 시그니처 오렌지(`#e95420`).
* **`os-apple-pro.conf`**: macOS Terminal 기본 'Pro'/'Homebrew' 스타일 다크 그래파이트(`#1c1c1e`) + 애플 네온 그린(`#30d158`).
* **`retro-crt-phosphor.conf`**: 1980년대 DEC VT220 및 매트릭스 터미널의 P1 그린 인광체(525nm, `#33ff33`).
* **`retro-crt-amber.conf`**: 유럽 TCO 표준 호박색 P3 앰버 인광체(589nm, `#ffb000`, 청색광 0% 차단).
