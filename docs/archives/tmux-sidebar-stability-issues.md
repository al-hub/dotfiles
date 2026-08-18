# tmux Sidebar 안정성 이슈 목록

이 문서는 구현을 바로 수정하기 전에 현재 `tmux-session-launcher`의 안정성 문제를 사실과 영향 단위로 분리해 기록한 것이다. 대상은 AI CLI 상태 표시, sidebar 재오픈과 split 복구, session close와 history 복원 흐름이다.

## 1. AI CLI 동작 상태 판정

### 1.1 현재 판정 경로

- `collect_sessions()`가 `list-panes -a` 한 번으로 각 session의 pane ID와 `pane_current_command`를 수집한다.
- `codex`, `claude`, `gemini`, `opencode`, `ollama`와 정확히 일치하는 `pane_current_command`만 direct AI pane으로 기록한다.
- 정확히 일치하지 않으면 pane PID의 자식 및 한 단계 더 내려간 자식의 argv를 `pgrep`/정규식으로 검사한다.
- AI pane으로 판단되면 최근 12줄의 화면 내용을 `cksum`한 fingerprint를 만든다. fingerprint가 바뀌면 `active`, 같으면 `waiting`으로 표시한다.
- AI pane을 찾지 못하면 session 전체의 `session_activity`와 “shell이 아닌 pane이 하나라도 있는가”를 조합한 기존 busy/idle heuristic으로 fallback한다.

### 1.2 문제점

1. **세션과 pane의 경계가 섞인다.** `session_activity`는 session 전체의 마지막 입력/활동 시각인데, 여기에 editor, `top`, 일반 명령, 다른 work pane의 활동도 포함된다. AI CLI가 대기 중이어도 다른 pane 활동만으로 active처럼 보일 수 있다.
2. **프로세스 이름 exact match가 취약하다.** shell wrapper, 절대 경로, alias/function, `python -m`/Node wrapper, subcommand 형태에서는 `pane_current_command`가 CLI 이름이 아니어서 direct 탐지가 빠진다.
3. **프로세스 탐색 깊이가 제한된다.** pane shell의 자식과 그 자식만 검사하므로 더 깊은 wrapper, reparenting, supervisor를 거친 CLI는 놓칠 수 있다. 반대로 argv 문자열에 CLI 이름이 포함된 비대상 프로세스는 오인할 수 있다.
4. **stale direct pane ID가 검증되지 않는다.** direct pane ID가 남아 있는 동안 `session_cli_state_for_session()`은 해당 pane이 아직 AI CLI인지 다시 확인하지 않고, capture 결과가 있으면 active로 확정한다. CLI가 종료된 shell pane의 일반 출력도 active가 될 수 있다.
5. **화면 fingerprint는 동작 상태의 대체물이 아니다.** prompt redraw, cursor/ANSI 변화, streaming 출력, 화면 스크롤만으로 fingerprint가 바뀐다. 반대로 내부 작업 중 화면이 변하지 않으면 waiting으로 보인다. `cksum` 충돌과 마지막 줄 제거도 상태 신뢰도를 낮춘다.
6. **AI CLI가 여러 pane인 경우 식별이 불안정하다.** session당 direct pane 하나와 probe pane 목록을 임의 순서로 사용하며, 어느 CLI가 실제 동작 중인지 또는 여러 CLI 중 하나라도 동작 중인지에 대한 명시적 정책이 없다.
7. **탐지 실패와 실제 idle이 같은 값으로 축약된다.** `active/waiting/idle`만 남고 `unknown` 또는 `not-detected`가 없어, 표시 오류를 사용자가 유휴 상태로 오해한다.
8. **상태 갱신 주기와 fingerprint 비교가 결합되어 있다.** 상태 snapshot은 기본 5초 주기로 갱신되므로 짧은 작업은 관측되지 않으며, 이전 fingerprint가 process identity와 연결되지 않아 pane 재사용 시 잘못된 전이가 가능하다.

### 1.3 안정화 시 결정할 것

- session이 아니라 **pane 단위 process identity**를 authoritative source로 삼을지
- CLI별 process detection adapter와 “실행 중/입력 대기/종료” 상태를 어떻게 정의할지
- 여러 AI pane의 aggregate 상태와 탐지 불가 상태를 UI에서 어떻게 구분할지
- 화면 fingerprint를 보조 신호로 유지할지, 제거할지

## 2. Sidebar 재오픈과 split layout 복구

### 2.1 현재 동작

- sidebar를 열 때 `save_work_layout()`이 sidebar가 추가되기 전 window layout 문자열을 window option `@dotfiles-session-work-layout`에 저장한다.
- sidebar를 닫을 때 sidebar pane을 kill하고 저장 문자열을 `select-layout`으로 적용한다.
- sidebar가 열린 상태의 split은 wrapper 함수가 work pane을 찾아 실행하지만, split 직후 새 layout을 `@dotfiles-session-work-layout`에 다시 저장하지 않는다.
- archive 시에는 저장 option의 pane 수와 현재 non-sidebar pane 수가 같을 때만 저장 layout을 사용한다. 다르면 layout을 빈 값으로 기록하거나 현재 전체 layout을 fallback으로 사용한다.
- history restore 시 pane을 새로 만든 뒤 저장 layout의 leaf pane ID를 새 ID로 치환하고 checksum을 다시 계산한다. 실패해도 오류를 외부에 명확히 보고하지 않고 계속 진행한다.

### 2.2 문제점

1. **wrapper split도 저장 layout을 갱신하지 않는다.** sidebar를 닫거나 session을 archive하면 split 전 layout으로 되돌아가 새 work pane이 사라질 수 있다. 현재 문서의 “wrapper를 사용하면 추적된다”는 설명과 구현이 일치하지 않는다.
2. **직접 tmux split은 더 명확히 추적되지 않는다.** pane 수가 달라지면 stale layout을 버리지만, pane 목록 자체는 새 pane을 포함한다. 따라서 restore는 pane은 만들고 비율/방향은 기본 split 결과에 의존하게 된다.
3. **layout 문자열은 pane ID에 강하게 결합된다.** live window에서 pane이 kill/recreate되거나 archive가 지연되면 저장 문자열의 ID와 실제 pane이 달라진다. pane 수만 비교하는 검증으로는 동일 pane인지 확인할 수 없다.
4. **pane ID 치환 순서가 layout leaf 순서와 생성 순서가 같다는 가정에 의존한다.** tmux의 split insertion/ordering과 serialized layout leaf 순서가 다르면 mixed layout에서 pane 내용과 위치가 뒤바뀔 수 있다.
5. **window 식별자가 이름에 의존한다.** restore 시 active window를 이름으로 선택하므로 이름이 같은 window가 있으면 잘못된 window를 선택할 수 있다. window index 또는 별도 stable ordinal이 필요하다.
6. **복구 실패가 조용히 무시된다.** `select-layout ... || true` 때문에 checksum/크기/ID 오류가 발생해도 사용자에게 “layout 복구 실패”가 전달되지 않는다.
7. **resize와 open/switch 타이밍이 경쟁한다.** sidebar 생성 직후 pane ID를 snapshot 차이로 찾고, session switch 직후 다시 respawn/resize한다. tmux command가 비동기로 처리되는 순간 새 pane 식별 또는 저장 대상 window가 어긋날 수 있다.
8. **저장 단위가 window option 하나다.** session 내 여러 window의 work layout을 명시적으로 관리하지 않고 현재 대상 window option에 의존하므로, session 전환/재오픈/삭제 시 snapshot 시점이 모호하다.

### 2.3 안정화 시 결정할 것

- layout의 source of truth를 live event마다 갱신할지, sidebar close 시점에 현재 상태를 계산할지
- sidebar pane을 제외한 **pane identity + path + layout**을 하나의 snapshot으로 저장할지
- restore가 exact layout에 실패할 때 abort할지, pane만 복구하고 degraded 상태를 명시할지
- window index/name, pane index/path를 복구 식별자로 어떻게 조합할지

## 3. Close, archive, history 복원

### 3.1 현재 동작

- session 삭제 시 `y`는 archive 후 삭제, 빈 입력은 archive 없이 삭제한다.
- archive는 `run-shell -b`에서 live tmux session을 조회해 window metadata, pane path/command, layout을 TSV로 쓴다.
- shell history는 `HISTFILE`의 마지막 200줄을 `history` record로 덧붙인다.
- restore는 같은 session 이름으로 새 session을 만들고, archive에 있던 pane 수/path/layout을 적용한 뒤 모든 work pane에 `clear`와 `clear-history`를 보낸다.
- restore 직전에 archive history 전체를 현재 `HISTFILE`에 append한다.

### 3.2 문제점

1. **history가 session별이 아니다.** 여러 session이 하나의 `HISTFILE`을 공유하므로 어느 session에서 실행한 명령인지 알 수 없고, 삭제 시 archive마다 같은 전역 history가 반복 저장된다.
2. **복원할 때 중복 append된다.** 같은 archive를 여러 번 restore하거나 여러 archive를 restore하면 동일한 200줄이 `HISTFILE`에 계속 추가된다. history 순서와 `HISTFILE` 크기가 빠르게 오염된다.
3. **archive 파일이 원자적으로 생성되지 않는다.** 바로 최종 파일에 쓰고 실패를 무시하는 경로가 있어, 중단된 TSV가 정상 history 항목처럼 노출될 수 있다.
4. **동일한 초 단위 timestamp와 재실행 정책이 없다.** 같은 session을 짧은 시간에 여러 번 archive하면 파일명이 충돌해 이전 snapshot이 덮어써질 수 있다.
5. **archive는 작업 재개 정보가 부족하다.** pane current path와 현재 명령 이름만 저장하며 command line, pane active 상태, environment, git context, CLI별 resume token, scrollback은 저장하지 않는다. process 자체를 복원하지 않는다는 한계도 사용자에게 명확한 정책으로 분리되어 있지 않다.
6. **복원 실패가 history에 반영될 수 있다.** session 생성 및 layout 적용의 성공 여부를 충분히 검증하기 전에 global history append가 수행된다. 부분 복원 후에도 history는 이미 오염될 수 있다.
7. **close의 의미가 두 가지다.** “작업을 이어가기 위한 snapshot 저장”과 “session을 완전히 버리기”가 y/Enter 입력에 묶여 있지만, archive 보존 기간, 최신본 선택, 자동 저장 여부가 정의되어 있지 않다.
8. **background delete의 결과를 기다리지 않는다.** current session 삭제는 client 전환과 backend archive/kill이 분리되어 있어, sidebar 종료와 archive 완료 순서가 사용자 관점에서 불명확하다. 실패 시 재시도/복구 방법도 없다.
9. **All delete는 archive 성공 여부와 무관하게 server를 종료한다.** `archive_all_sessions`가 개별 실패를 무시한 뒤 `kill-server`를 실행하므로 일부 session의 재개 정보가 유실될 수 있다.
10. **복원 session 이름 충돌 정책이 단순하다.** 같은 이름이면 전체 복원을 중단하며, suffix 생성이나 기존 session merge 정책이 없다.

### 3.3 제안할 정책의 최소 경계

- archive는 `session snapshot`으로 명명하고, shell history는 별도 선택적 artifact로 분리한다.
- snapshot은 임시 파일에 쓴 뒤 검증 후 rename하며, 고유 ID와 schema version을 포함한다.
- 복원은 “metadata/layout/path 복원”이지 process 재개가 아님을 명시한다. AI CLI는 CLI별 resume 지원 여부를 별도 처리한다.
- restore 성공 후에만 history import를 수행하고, archive ID 기반으로 한 번만 import한다.
- All close는 archive 실패 시 server를 종료하지 않는 fail-safe를 기본값으로 한다.
- 보존/삭제/최신 snapshot 선택, 이름 충돌, 부분 복원 실패를 명시적인 정책과 UI 상태로 만든다.

## 4. 우선순위와 재현 시나리오

1. **P0: 상태 오판**: AI CLI 종료 후 active 유지, 일반 pane 활동으로 AI active 표시, wrapper CLI 미탐지.
2. **P0: 작업 layout 유실**: sidebar open 후 wrapper split, sidebar close/reopen, split pane과 비율이 보존되는지 확인.
3. **P0: archive 유실/오염**: 같은 session을 연속 close, All close 중 archive 실패, 동일 archive 반복 restore 후 history 중복 확인.
4. **P1: mixed layout restore**: horizontal + vertical split, pane 순서와 path가 위치별로 유지되는지 확인.
5. **P1: 다중 AI pane**: 한 session에서 두 CLI가 각각 실행/대기/종료되는 경우 aggregate 상태 확인.
6. **P1: race**: session switch 직후 sidebar respawn, close 직후 archive 생성, restore 직후 sidebar 재부착을 반복한다.

이 문서는 문제 정의 단계의 기록이며, 구현 방식이나 최종 정책을 확정한 문서는 아니다.

## 5. AI lifecycle 실험 및 재현 기록

아래 내용은 2026-07-14에 별도 status bridge, CLI hook, process fallback, prompt adapter를 조합해 시험한 결과다. 실험 코드는 안정성이 기존 fingerprint 방식보다 낮다고 판단해 모두 rollback했다.

| 시험 항목 | 재현/확인 | 결과 |
|---|---|---|
| Claude hook payload mapping | fixture 확인 | `UserPromptSubmit`은 running, `Stop`/`idle_prompt`는 waiting으로 변환 가능했다. 실제 장시간 사용 E2E는 확인하지 않았다. |
| Gemini hook | fixture 및 실제 pane 확인 | `BeforeAgent`/`AfterAgent` 상태 전환과 waiting 표시가 동작했고, 사용자 확인에서도 의도대로 동작했다. |
| OpenCode plugin event | fixture 확인 | `session.status=busy`는 running, `session.idle`은 waiting으로 변환 가능했다. 실제 장시간 사용 E2E는 확인하지 않았다. |
| Codex notify | fixture 및 실제 완료 event 확인 | `agent-turn-complete`는 waiting으로 기록됐지만 외부 notify에 turn 시작이 없어 다음 turn의 running 시작을 확정할 수 없었다. |
| agy process/prompt adapter | 실제 pane 확인 | 입력 composer prompt에서 waiting으로 내려갔고 사용자 확인에서도 의도대로 동작했다. 공식 lifecycle event는 확인하지 못했다. |
| Ollama process fallback | 격리 tmux 확인 | process가 살아 있으면 `active/animate=true`, pane 종료 후 `idle/false`가 됐다. 입력 대기 중에도 process가 살아 있어 waiting은 구분하지 못했다. |
| Ollama prompt adapter | fixture 및 실제 pane 확인 | `>>> Send a message`에서 waiting은 잡았지만 scrollback에 남은 과거 prompt가 새 running을 막는 오판이 발생했다. |
| Ollama API wrapper | localhost stream fixture 확인 | `/api/chat`의 최종 `done=true`를 waiting으로 변환할 수 있었다. 기존 `ollama` CLI를 대체해야 하므로 기본 동작으로 채택하지 않았다. |
| event-only 판정 | 실제 pane 확인 | event가 없는 Codex/Ollama/agy에서 gradient가 전혀 시작하지 않는 회귀가 발생했다. |
| event + process fallback | 실제 pane 확인 | CLI process가 입력 대기 중에도 유지되어 gradient가 멈추지 않는 회귀가 발생했다. |
| pane 재사용 | 실제 pane 확인 | 같은 pane에서 Codex 종료 후 Ollama를 실행했을 때 Codex의 stale waiting event가 Ollama 상태에 섞였다. pane PID가 shell PID라 CLI generation 식별자가 되지 못했다. |
| provider별 prompt 보조 판정 | 격리 fixture 확인 | Codex/Ollama running과 waiting을 일부 구분했지만 cursor 위치, scrollback, TUI redraw에 의존해 provider별 예외가 계속 증가했다. |

### 5.1 확인된 결론

- 공식 hook/event는 provider별 제공 범위가 달라 공통 run/wait source로 사용할 수 없었다.
- process 생존은 CLI 존재 확인에는 쓸 수 있지만 running/waiting 구분에는 사용할 수 없다.
- pane ID와 pane PID만으로는 동일 pane에서 교체되는 CLI turn/generation을 식별할 수 없다.
- prompt/cursor adapter는 특정 화면에서는 동작하지만 TUI redraw와 scrollback에 민감해 일반화하기 어렵다.
- lifecycle event, process, prompt, session activity를 동시에 섞으면 우선순위와 stale state 관리가 기존 방식보다 복잡해졌다.
- 다음 시도는 외부 hook 설치 없이 기존 pane fingerprint 방식을 단일 source로 유지하고, 화면 정규화와 명시적 waiting prompt를 제한적인 보조 신호로 검토한다.

## 6. Session 저장소 기반 상태 감지 검토

아래 내용은 2026-07-14 로컬 설치 환경과 각 CLI 문서를 기준으로 조사한 결과다. 구현을 확정한 것이 아니며, vendor별 session 저장소나 상태 인터페이스가 pane fingerprint보다 안정적인 run/wait 신호가 될 수 있는지 검토하기 위한 기록이다.

### 6.1 기본 가설과 판정 한계

- AI CLI process가 살아 있고 해당 session 기록이 계속 append되면 `running`으로 볼 수 있다.
- 기록 변화는 강한 running 신호지만, 기록 무변화는 즉시 waiting을 의미하지 않는다. API 응답 대기, 내부 reasoning, write buffering 중에는 실제 작업 중이어도 파일이 변하지 않을 수 있다.
- 따라서 파일 변화가 멈춘 즉시 waiting으로 내리지 않고 유예시간과 연속 관측을 둬야 한다.
- session 파일 전체를 반복해서 읽거나 CLI마다 `tail -f` process를 유지하기보다 `device:inode:size:mtime_ns`를 비교하는 편이 sidebar polling에 적합하다.
- file rotation, compaction, resume, 새 session 생성 시 경로와 inode가 바뀔 수 있으므로 pane과 session artifact의 identity를 함께 갱신해야 한다.
- 여러 pane에서 같은 CLI를 동시에 실행할 수 있으므로 "현재 project의 최신 파일"만 선택해서는 안 된다. pane ID와 정확한 session ID 또는 artifact 경로를 연결하는 절차가 필요하다.

### 6.2 CLI별 관찰 원천

| CLI | 확인된 원천 | 기대 신뢰도 | 검토 방향 |
|---|---|---:|---|
| Claude | session transcript JSONL | 높음 | hook 입력의 `session_id`와 `transcript_path`로 pane과 transcript를 연결한 뒤 크기/mtime을 관찰할 수 있다. |
| Codex | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` | 높음 | 현재 session rollout의 append를 관찰한다. 로컬 확인에서는 reasoning, tool call, tool output event가 계속 기록됐다. |
| Gemini | `~/.gemini/tmp/<project>/chats/*.jsonl` | 높음 | project별 auto session transcript를 관찰하거나 `BeforeAgent`/`AfterAgent` hook과 보완한다. |
| agy | `~/.gemini/antigravity-cli/conversations/<id>.db`, `brain/<id>/.system_generated/logs/transcript*.jsonl` | 중간 이상 | SQLite보다 session별 transcript JSONL을 우선 후보로 삼되 generation 중 append 주기를 실제 측정해야 한다. |
| OpenCode | `~/.local/share/opencode/opencode.db*`, server `/event`, `/session/status` | 높음 | DB/WAL 변화보다 session ID가 포함된 SSE `session.status` 또는 status API를 우선한다. |
| Ollama | `~/.ollama/history`, REST streaming response | 기본 파일은 낮음 | history는 사용자 입력 recall용이므로 transcript로 쓰지 않는다. wrapper가 API chunk와 최종 `done=true`를 pane별 sidecar에 기록하는 방식을 별도 검토한다. |

참고 자료:

- Claude Code hooks는 공통 입력으로 `session_id`와 `transcript_path`를 제공한다: <https://code.claude.com/docs/en/hooks>
- Gemini CLI는 project별 session을 자동 저장하고 resume할 수 있다: <https://github.com/google-gemini/gemini-cli/blob/main/docs/reference/commands.md>
- OpenCode server는 SSE `/event`와 session status API를 제공한다: <https://opencode.ai/docs/server/>
- Ollama REST API는 streaming chunk와 최종 `done=true`를 제공한다: <https://docs.ollama.com/capabilities/streaming>, <https://docs.ollama.com/api/chat>
- Ollama의 `~/.ollama/history`는 assistant transcript가 아니라 readline 입력 history다: <https://github.com/ollama/ollama/issues/1052>

### 6.3 공통 adapter 후보

sidebar가 vendor별 JSONL, SQLite, API 형식을 직접 해석하면 기존 lifecycle 실험처럼 우선순위와 stale state가 복잡해질 수 있다. 검토할 구조는 각 CLI adapter가 원천 신호를 pane별 공통 sidecar로 정규화하고 sidebar는 sidecar만 읽는 방식이다.

```text
Claude transcript ---+
Codex rollout -------+
Gemini transcript ---+
agy transcript ------+--> CLI adapter --> pane별 sidecar --> sidebar
OpenCode status SSE -+
Ollama API wrapper --+
```

sidecar 후보 위치와 최소 필드는 다음과 같다.

```text
$XDG_RUNTIME_DIR/tmux-ai-status/<tmux-server-id>/<pane-id>.state

cli=<provider>
session_id=<provider-session-id>
source=<artifact-path-or-endpoint>
generation=<process-or-session-generation>
state=<running|waiting|idle|unknown>
activity_ns=<last-observed-activity>
```

- AI process가 없으면 `idle`로 정리한다.
- session artifact가 변하거나 status stream에서 busy event가 오면 즉시 `running`으로 올린다.
- artifact 무변화만으로 waiting을 확정하지 않고 provider별 유예시간 동안 이전 상태를 유지한다.
- 명시적인 idle/done event가 있으면 `waiting`으로 내릴 수 있다.
- process identity, session ID, pane ID 중 하나가 바뀌면 이전 sidecar를 stale로 간주하고 새 generation으로 교체한다.
- adapter 연결에 실패하면 `unknown`을 유지하거나 기존 pane fingerprint로 제한적으로 fallback한다. fallback 결과를 확정 상태와 구분할 수 있어야 한다.

### 6.4 구현 전 필요한 재현 테스트

1. 각 CLI에서 prompt 제출부터 첫 session artifact write까지 걸리는 시간을 측정한다.
2. streaming 응답, 긴 무출력 reasoning, tool 실행, permission 대기, turn 완료 동안 size/mtime 또는 status event가 어떻게 변하는지 기록한다.
3. 같은 project에서 동일 CLI 두 개를 동시에 실행해 pane과 artifact가 일대일로 연결되는지 확인한다.
4. resume, compact, clear, session file rotation 이후 artifact identity가 어떻게 바뀌는지 확인한다.
5. CLI 강제 종료, tmux pane 재사용, 같은 pane에서 다른 CLI 실행 시 이전 sidecar가 남지 않는지 확인한다.
6. OpenCode는 SSE/status API가 TUI process와 같은 session ID를 안정적으로 제공하는지 확인한다.
7. Ollama는 기본 CLI를 유지할 때와 API wrapper를 사용할 때 UX, model option, history, tool 기능 차이를 비교한다.
8. 파일 감시와 현재 pane fingerprint를 같은 시나리오에서 기록해 false running, false waiting 비율을 비교한다.

현재 단계의 결론은 session 저장소가 기존 pane fingerprint를 대체할 가능성이 있지만, 모든 CLI에 동일한 `tail` 규칙을 적용할 수는 없다는 것이다. Codex, Claude, Gemini, agy는 session transcript 계열, OpenCode는 status API, Ollama는 wrapper sidecar가 각각 우선 후보이며, 실제 채택 여부는 위 재현 테스트 이후 결정한다.

## 7. 다음 안정화의 우선 방향: pane fingerprint 고도화

이전 lifecycle event, process fallback, prompt adapter 실험은 provider별 예외와 stale state를 늘려 기존 방식보다 불안정했다. session 저장소 기반 감지도 유효한 조사 대상이지만 pane과 provider session을 정확히 연결해야 하고 vendor 저장 형식에 의존한다. 따라서 다음 안정화에서는 현재 pane fingerprint 방식을 공통 authoritative source로 우선하고, session 저장소와 lifecycle event는 기본 판정을 대체하지 않는 보조 연구 항목으로 둔다.

### 7.1 가장 큰 선행 문제: gradient 자동 검증 부재

fingerprint 정확도보다 먼저 해결해야 할 가장 큰 문제는 **gradient가 올바른 session에서 시작되고, 실행 중 유지되며, waiting에서 정지하는지를 반복 가능한 자동 테스트로 검증하지 못한다는 점**이었다. 문제 정의 당시 저장소에는 독립된 test/fixture가 없었고, 기존 검증은 일회성 mock, 격리 tmux 명령, debug log, 사용자 육안 확인에 주로 의존했다.

이 상태에서는 다음 문제가 반복된다.

- 상태 판정 수정 후 gradient가 아예 시작하지 않거나 영원히 멈추지 않는 회귀를 commit 전에 잡기 어렵다.
- state 계산과 ANSI 부분 렌더 중 어느 쪽이 실패했는지 분리하기 어렵다.
- 실제 AI CLI 응답 시간과 네트워크에 의존하므로 같은 조건을 반복할 수 없다.
- animation cadence, 상태 refresh cadence, age refresh가 겹치는 timing 문제를 수동 관찰로만 판단한다.
- 여러 session, pane 재사용, resize, sidebar reopen 같은 조합을 매 변경마다 동일하게 재현하지 못한다.
- "자연스럽게 움직인다"는 시각 평가와 "정확한 상태에서만 움직인다"는 lifecycle 평가가 섞인다.

따라서 다음 안정화의 첫 단계는 heuristic 변경이 아니라 gradient 검증 harness를 만드는 것이다. 실제 Claude/Codex/Gemini 등의 네트워크 응답을 테스트에 사용하지 않고, 정해진 시간표대로 pane 출력을 변경하는 fake AI command를 격리 tmux socket에서 실행해야 한다.

최소 자동 테스트 계층은 다음과 같다.

1. **Fingerprint fixture test**: raw pane capture fixture를 입력해 normalized text와 fingerprint가 기대값인지 확인한다.
2. **State transition test**: 가짜 clock과 fingerprint sequence로 `idle -> running -> waiting -> running -> idle` 전이를 결정적으로 검증한다.
3. **Renderer test**: 고정 session name, seed, animation frame을 입력해 ANSI color cell과 sweep 위치를 비교한다.
4. **Isolated tmux E2E**: 전용 tmux socket에서 fake `codex`/`claude` process를 띄우고 sidebar capture 및 debug state를 시간순으로 검증한다.
5. **Regression scenario test**: 여러 session, 여러 AI pane, CLI 종료/재실행, pane ID 재사용, resize, sidebar close/reopen을 고정 시나리오로 실행한다.

E2E 검증은 화면 screenshot의 픽셀 비교보다 상태 timeline과 ANSI cell 변화를 우선한다.

```text
t=0   fake AI 시작, 고정 prompt       -> idle 또는 초기 안정 상태
t=1   scripted output append          -> running, gradient frame 변화
t=2   scripted output append          -> running, gradient 계속 변화
t=15  output 무변화 임계값 도달       -> waiting, gradient 정지
t=16  output append                   -> running, gradient 재시작
t=20  fake AI process 종료            -> idle, gradient 정지
```

검증 가능한 acceptance criteria도 명시해야 한다.

- running 구간에서 같은 session name의 ANSI gradient frame이 최소 두 번 이상 달라진다.
- waiting/idle 구간에서는 gradient frame repaint가 발생하지 않는다.
- 대상이 아닌 session row는 ANSI gradient가 변하지 않는다.
- waiting 이후 새 출력이 생기면 설정된 한 번의 state refresh 안에 gradient가 다시 시작한다.
- process/pane generation이 바뀌면 이전 fingerprint와 animation state가 재사용되지 않는다.
- 전체 row repaint, cursor 노출, 다른 session name 손상 같은 렌더 회귀가 발생하지 않는다.

테스트를 결정적으로 만들려면 epoch 조회, poll interval, state refresh cadence를 test mode에서 주입할 수 있어야 한다. TUI 전체를 source하는 구조가 어렵다면 fingerprint 정규화, 상태 전이, gradient cell 계산을 side effect 없는 함수로 먼저 분리하고, 실제 tmux 명령은 얇은 adapter와 E2E에서만 사용한다.

이 harness가 통과하기 전에는 waiting 임계값이나 정규화 규칙을 조정하더라도 정확도가 개선됐다고 확정하지 않는다.

#### 7.1.1 추가된 자동 검증 baseline

2026-07-14에 production launcher를 변경하지 않고 `tests/tmux-sidebar-gradient/`에 다음 테스트 기반을 추가했다.

| 테스트 | 검증 범위 | 현재 결과 |
|---|---|---|
| `test-render.sh` | frame별 ANSI gradient 변화, waiting/plain 출력, global disable | PASS 3 |
| `test-fingerprint.sh` | 마지막 줄 제외, 본문 변화, 빈 줄 정규화 | PASS 3 |
| `test-state.sh` | `active -> waiting -> active`, shell-only idle | PASS 2 |
| `test-session-isolation.sh` | 여러 session의 독립 animation 상태 | PASS 1 |
| `test-lifecycle-e2e.sh` | 격리 tmux fake `codex`의 시작, 정지, 재시작, 종료 | PASS 4 |
| `test-regressions.sh` | 아직 수정하지 않은 합의된 개선 대상 | XFAIL 3 |

현재 XFAIL로 고정한 개선 대상은 다음과 같다.

- 한 번의 fingerprint 무변화로 즉시 waiting 전환
- fingerprint 본문에 포함된 spinner 변화 미정규화
- 같은 session에서 새 pane generation이 이전 fingerprint를 재사용

전체 suite는 다음 명령으로 실행한다.

```sh
bash tests/tmux-sidebar-gradient/run.sh
```

현재 baseline은 실제 AI 서비스나 네트워크를 사용하지 않는다. renderer와 상태 계산은 deterministic fixture로 검증하고, tmux 연결은 임시 실행 파일명이 `codex`인 fake AI와 전용 socket을 사용한다. XFAIL 항목을 수정할 때는 해당 assertion을 PASS로 전환한 뒤 전체 suite를 회귀 검증한다.

### 7.2 현재 fingerprint의 가장 큰 문제

가장 큰 문제는 fingerprint 생성에 `cksum`을 사용한다는 점이 아니라 **한 번의 화면 무변화를 즉시 waiting으로 해석하는 판정 방식**이다.

- AI가 reasoning, API 응답 대기, subprocess 실행 중이어도 화면이 갱신되지 않으면 false waiting이 발생한다.
- 반대로 spinner, elapsed time, token count, progress indicator, TUI redraw가 계속 바뀌면 실제 입력 대기 중에도 false running이 발생한다.
- sidebar가 처음 AI pane을 관측했을 때 이전 fingerprint가 없으므로, 이미 입력 대기 중인 CLI도 우선 running으로 보일 수 있다.
- fingerprint가 session 이름에 연결되어 pane이나 CLI process generation이 바뀌면 이전 값이 새 실행의 비교 기준으로 섞일 수 있다.
- 최근 12줄과 마지막 한 줄 제외라는 고정 규칙은 CLI별 TUI 구조, terminal resize, line wrapping에 따라 결과가 달라진다.

현재 판정은 사실상 다음과 같다.

```text
직전 fingerprint와 다름 -> running
직전 fingerprint와 같음 -> waiting
```

이 단일 비교를 그대로 두면 fingerprint 입력 일부를 정규화해도 긴 무출력 작업과 새로운 동적 UI에서 오판이 반복된다.

### 7.3 가장 효과가 클 개선

가장 먼저 **마지막 의미 있는 변화 시각과 연속 안정 관측**을 상태 판정에 도입한다.

```text
정규화 fingerprint 변화
  -> 즉시 running

무변화 1회
  -> 이전 running 상태 유지

무변화가 설정 시간 또는 설정 횟수 이상 지속
  -> waiting

waiting 이후 fingerprint 변화
  -> 즉시 running
```

초기 후보값은 상태 갱신 주기에 맞춰 2~3회 연속 무변화 또는 10~15초 안정 구간으로 두되, 실제 CLI별 재현 로그를 보고 확정한다. 이 변경은 짧은 무출력 구간에서 발생하는 false waiting을 가장 적은 복잡도로 줄일 가능성이 크다.

다음으로 fingerprint 입력에서 상태와 무관한 동적 표현을 제한적으로 정규화한다.

- spinner frame과 반복 animation glyph
- elapsed time과 계속 증가하는 token/progress 숫자
- prompt 또는 고정 status 영역
- terminal resize 직후 발생한 reflow snapshot
- provider별로 명확히 확인된 volatile line만 대상으로 하며 광범위한 숫자 제거처럼 실제 응답을 훼손하는 규칙은 피한다.

### 7.4 구현 우선순위

1. fake AI command, 가짜 clock, 고정 fingerprint sequence를 사용하는 gradient 자동 검증 harness를 만든다.
2. 현재 동작을 fixture와 E2E baseline으로 고정해 변경 전 실패/성공 조건을 재현한다.
3. waiting 전환에 유예시간과 연속 무변화 횟수를 적용한다.
4. raw capture, normalized capture, fingerprint, 상태 전이를 debug log로 동시에 기록한다.
5. 실제 false running을 만드는 spinner와 동적 숫자만 재현 기반으로 정규화한다.
6. fingerprint identity를 `tmux server + pane ID + AI process generation`에 연결하고 identity 변경 시 이전 값을 폐기한다.
7. 한 session의 여러 AI pane을 pane별로 판정한 뒤 `하나라도 running이면 session running`으로 집계한다.
8. resize, pane 재사용, CLI 교체, resume 시나리오를 회귀 테스트로 고정한다.
9. fingerprint로 해결되지 않는 확인된 사례에만 session 저장소나 명시적 lifecycle event를 보조 신호로 추가한다.

### 7.5 유지할 설계 원칙

- 화면 fingerprint는 Claude, Codex, Gemini, agy, OpenCode, Ollama에 같은 방식으로 적용 가능한 공통 기준으로 유지한다.
- provider별 hook, wrapper, DB/API 의존성을 기본 설치에 추가하지 않는다.
- 보조 신호가 없어도 현재 수준의 동작을 유지하고, 보조 신호 실패가 running/waiting 상태를 고정하지 않게 한다.
- 정규화 규칙과 상태 전이 정책을 분리해 각각 독립적으로 재현하고 조정할 수 있게 한다.
- 정확도를 평가할 때 사용자가 실제로 기대하는 gradient 기준인 `AI가 응답 생성 또는 tool 작업 중인가`와 `사용자 입력/승인을 기다리는가`를 구분한다.
- 자동 테스트로 재현되지 않는 체감 개선은 확정된 안정화 결과로 기록하지 않는다.

다음 안정화 작업은 이 절의 순서를 기본 계획으로 삼는다. session 저장소 방식은 fingerprint 고도화 이후에도 남는 구체적인 오판 사례가 확인될 때 다시 평가한다.
