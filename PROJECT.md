# PROJECT.md — AI 협업 자동화 PoC (ai-pipeline) v0.6 초안 (2026-11-23 n8n 판정 구조 간소화, 17절)

## 1. 목적
- 한 단계가 끝나면 다음 단계의 AI가 **사람의 복사·붙여넣기 없이** 자동으로 일을 시작하는지 확인한다.
- 조건: API 키 없이 계정 로그인만 쓴다 (Claude Pro, ChatGPT 무료).
- 이번 PoC는 **연동 확인만** 한다. 실제 기능(수집·비전 등)은 만들지 않는다.
- 완료 뒤에는 이 흐름을 기존 PoC 고도화에 재사용한다. 그래서 처음부터 **프로젝트 폴더만 바꾸면 돌아가는 공통 흐름**으로 만든다.

## 2. 구성
| 구성 요소 | 역할 | 실행 방식 | 로그인 |
|---|---|---|---|
| n8n | 단계 순서를 지휘(orchestrator) | 노트북에 직접 설치 (npm) | — |
| Claude Code | ② 개발, ⑥ 2차 검수 (④ 실행은 2026-11-22부터 stage.ps1이 직접, 16절) | `claude -p "<지시>"` (화면 없이 실행) | Claude Pro (구독 한도에서 차감) |
| Codex | ③ 코드 리뷰, ⑤ 1차 검수 | `codex exec --sandbox read-only "<지시>"` | ChatGPT 무료 계정 (Free 한도, 2026-11-22 정정) |
| 사람 | ① 기획, ⑦ 판정 | Claude 채팅 + 파일 확인 | — |

## 3. 흐름
| 단계 | 담당 | 하는 일 (이번 PoC) | 남기는 것 |
|---|---|---|---|
| ① 기획 | 사람 (Claude 채팅) | TASK.md 작성 후 n8n [시작] | TASK.md |
| ② 개발 | Claude Code | 아주 작은 더미 코드 작성 (예: 문장을 파일에 쓰는 스크립트) | 코드, REPORT.md |
| ③ 코드 리뷰 | Codex (읽기 전용) | 코드 리뷰, 결과 첫 줄에 `VERDICT: PASS` 또는 `VERDICT: BLOCK` | `.pipeline/reviews/` 원문 |
| ④ 실행 | stage.ps1 (AI 없음, 2026-11-22 변경) | TASK.md의 `RUN:` 명령을 그대로 실행 | runs/, REPORT.md |
| ⑤ 1차 검수 | Codex (읽기 전용) | REPORT 주장과 runs/ 실제 파일 대조 | `.pipeline/reviews/` 원문 |
| ⑥ 2차 검수 | Claude Code (새 세션, 읽기만) | 중요도 판단, 놓친 문제, ⑤와의 이견 표 | RESULT.md (n8n이 기록) |
| ⑦ 판정 | 사람 | 결과 보고를 보고 결정 | PROJECT.md |

## 4. 신호와 기록 방식
- 단계 사이 신호: n8n이 각 단계 명령을 **순서대로** 실행하고, 끝나면 STATUS.json에 상태를 쓴다.
  - 예: `{"stage": "③", "status": "완료", "result": "통과", "at": "2026-11-22T10:30:00+09:00"}`
- 검사 단계(③·⑤ Codex, ⑥ Claude Code)는 **읽기만** 한다. 그래서 **검사자의 출력은 n8n이 받아서 파일로 적는다** (2026-11-22 결정, ⑥도 같은 방식). ③·⑤는 `.pipeline/reviews/` 원문, ⑥은 RESULT.md (15절). 검사자는 코드를 못 바꾸고, 기록은 남는다.
- 모든 단계의 시작·끝 시각, 명령, 종료 코드는 `.pipeline/logs/`에 남긴다.

## 5. 규칙
- ③ 결과가 `차단`이면 ②로 돌아간다. **최대 2회**까지, 그래도 차단이면 멈추고 사람에게 알린다.
- 어느 단계든 명령이 실패하거나 시간이 넘으면 다음 단계로 가지 않고 멈춘다.
  - Claude 단계의 "실패" 판정 (2026-11-22 결정): exitCode ≠ 0 **또는** `is_error` true **또는** `permission_denials` 1건 이상. 읽기만 하는 ⑥도 같은 기준. 판정은 결과 본문이 아니라 JSON 필드로 한다 (14절)
- ④ 실행 전 사람 승인은 이번 PoC에는 넣지 않는다 (실제 고도화 때 n8n 대기 기능으로 추가 검토).
- REPORT.md·RESULT.md는 덮어쓰지 않고 맨 위에 날짜와 함께 추가한다. 리뷰 원문은 시도마다 새 파일로 만든다.
- 기준 문서는 PROJECT.md다. 진행 상태는 PROJECT.md·REPORT.md·STATUS.json으로 본다.

## 6. 완료 조건
1. ①에서 [시작]을 한 번 누르면 ②~⑥이 사람 손 없이 이어진다.
2. ③ `차단` → ② 재작업 → ③ 재리뷰 흐름이 1회 이상 확인된다 (일부러 차단 나게 시험).
3. 단계 하나를 일부러 실패시키면 흐름이 거기서 멈춘다.
4. 끝나면 사람이 읽을 결과 보고가 하나 나온다 (RESULT.md, 15절).
5. 한 번 돌릴 때 Claude·Codex를 각각 몇 번 불렀는지 기록한다 (사용량 판단용).

## 7. 확인이 필요한 것 (지금은 추정)
- ✅ (2026-11-22 확인) Execute Command는 n8n 2.x에서 기본 차단. `NODES_EXCLUDE='["n8n-nodes-base.localFileTrigger"]'`로 실행하니 노드 목록에 보이고 실행됨 (n8n 2.48.7)
- ✅ (2026-11-22 확인) n8n Execute Command에서 `where claude & where codex & claude --version & codex --version` 실행 → exitCode 0, claude·codex 모두 찾음. PowerShell과 같은 결과(codex는 VS Code 확장 내장본 0.164.0-alpha가 맨 앞). AI 호출 0회
- ✅ (2026-11-22 확인) `claude -p` 권한 옵션: `dontAsk` + 허용 명단으로 허용분만 실행, 나머지는 거부되고 계속 진행. 거부돼도 exitCode 0 (14절, .pipeline/logs/perm-test-20261122-112514.*). Claude 1회
- ✅ (2026-11-22 확인) `claude -p` Haiku 5회(= v1 1회 실행 최대치) → 5시간·주간 모두 1% 미만 (8절, .pipeline/logs/usage-test-20261122-113541.*). Claude 5회
- ✅ (2026-11-22 확인) Codex 4회(= v1 1회 실행 최대치, 재리뷰 포함) → 1개월 한도 97%→97%, 1% 미만. 4회 모두 예상 판정(BLOCK) (8절, .pipeline/logs/codex-usage-test-20261122-121027.*). Codex 4회

## 8. 사용량
- `claude -p`는 Pro 구독 한도에서 차감된다 (2026-11-22 Claude 도움말 확인). 채팅과 같은 한도다.
- 시험은 아주 작은 작업으로만 돌린다.
- 확인 (2026-11-22): Pro 한도는 토큰 수가 공개되지 않고 %로만 보인다 (웹 Settings > Usage, 5시간·주간). 채팅·Claude Code가 같은 한도를 쓴다
- 측정 방법 결정 (2026-11-22):
  - 목적: v1 파이프라인을 일주일에 몇 번 돌릴 수 있는지
  - 모델: Haiku (v1은 더미 작업이라 모델 성능이 상관없고, v1에서 실제로 쓸 모델로 잼). 고도화 때 다른 모델을 쓰면 다시 잰다
  - 호출 5회 (v1 1회 실행의 최대 Claude 호출 수: ②·④·⑥ 3회 + ② 재작업 최대 2회)
  - % 전후 비교 + 호출별 토큰 기록(JSON) 둘 다. 측정 중에는 채팅을 쓰지 않는다 (같은 한도라 섞임)
  - 측정 전 주간 잔여: 약 70% (사용자 확인)
- 측정 결과 (2026-11-22 11:35~11:38, .pipeline/logs/usage-test-20261122-113541.txt·.csv):
  - 확인: 5회 모두 PASS. 사용량 전후 5시간 34%→34%, 주간 33%→33% (측정 중 채팅 1턴이 섞였는데도 변화 없음)
  - 확인: 토큰 합계 input 20 / cache_write 77,176 / cache_read 257,145 / output 1,282. 호출 1회 평균 cache_write 약 1.5만, cache_read 약 5.1만, output 약 260, 2~3초
  - 결론: v1 1회 실행(Claude 최대 5회)은 주간 한도 **1% 미만**. 화면이 1% 단위라 정확한 값은 알 수 없음
  - 추정: 남은 주간 약 67%로 v1을 **최소 수십 회(보수적으로 60회 이상)** 돌릴 수 있음. 단, Codex 사용량 별도, 실제 작업이 커지면 다시 잰다
  - 참고: 측정보다 긴 Claude 채팅이 한도를 더 많이 씀 → 단계가 끝나면 새 채팅으로 넘어간다
- Codex 측정 방법 결정 (2026-11-22):
  - 확인: ChatGPT 무료 계정의 Codex `/status`는 5시간·주간이 아니라 **1개월 한도** 하나만 보임. 측정 전 97% 남음, 12월 21일 초기화
  - 호출 4회 (v1 1회 실행의 최대 Codex 호출 수: ③ 첫 리뷰 1 + 재리뷰 최대 2 + ⑤ 1)
  - 리뷰 대상: tests/codex-test/의 더미(TASK.md, 일부러 버그를 넣은 sample.py, 틀린 주장이 있는 REPORT.md, runs/output.txt). 예상 판정: ③ BLOCK, ⑤ BLOCK
  - 옵션: `codex exec --sandbox read-only --skip-git-repo-check --ephemeral --json -o <마지막 메시지 파일>`. 토큰은 JSON의 `turn.completed` 이벤트 `usage`에서 기록 (Codex 공식 문서)
  - Codex 실패 판정 (측정용, 미확정): 종료 코드 ≠ 0 또는 `turn.failed`/`error` 이벤트 또는 판정 줄 없음. 판정 키워드는 `VERDICT: PASS/BLOCK`을 썼고, 11절 2번에서 이대로 확정 (2026-11-22)
  - 참고: 7절 5번 준비를 Codex에 요청했다가 "읽기 전용이라 못 쓴다"는 답을 받음 → 설계대로 동작한 것. 준비·작성은 Claude, Codex는 검사만
- Codex 측정 결과 (2026-11-22 12:10~12:12, .pipeline/logs/codex-usage-test-20261122-121027.txt·.csv·*.last.txt):
  - 확인: 4회 모두 종료 코드 0, 판정 줄 있음, STOP 0회. 판정은 ③ 3회 BLOCK, ⑤ BLOCK으로 예상과 같음. ⑤는 REPORT의 맞는 주장(출력 2.0)과 틀린 주장(빈 목록 0)을 구분해서 지적
  - 확인: 1개월 한도 97% → 97% (변화 없음)
  - 확인: 토큰 합계 input 161,219(그중 캐시 132,224) / output 655 / reasoning 0. ③ 1회 약 3.1만 입력·9~10초, ⑤는 파일을 더 읽어 약 6.6만 입력·17초
  - 확인: read-only 샌드박스에서도 Codex가 PowerShell로 파일 읽기 명령(Get-Content 등)을 실행해 확인함
  - 결론: v1 1회 실행(Codex 최대 4회)은 1개월 한도 **1% 미만**. 남은 97%로 월 **최소 90회 이상**(보수적 추정)
  - 한계: sample.py에 "Intentional bug" 주석을 넣어 버려 리뷰어에게 힌트가 됐음 → 판정 정확도 시험으로는 약함(사용량 측정에는 영향 없음). 판정 품질은 v1 본 실행 때 주석 없는 코드로 다시 본다
- 종합 (Claude 8절 결과 포함): v1 1회 실행 = Claude 주간 1% 미만 + Codex 월 1% 미만. 사용량은 v1 진행을 막지 않음

## 9. 하지 않는 것
- 실제 기능 개발, 웹 화면, Docker, API 키 사용
- 웹 화면을 조작하는 확장 프로그램 방식 (불안정, 약관 위험)

## 10. 코드 관리 (2026-11-22 결정)
- 목적: 포트폴리오. "Git으로 코드를 관리하며 정식 개발 절차를 밟았다"는 기록을 남긴다.
- 저장소: GitHub.
- n8n은 **로컬 커밋까지만** 한다. push·병합은 ⑦ 판정 때 사람이 직접 한다 (인증 설정을 PoC 범위에 넣지 않고, 사람 승인 기록도 남기기 위해).
- 단계와 개발 절차 대응 (설계안):
  | 단계 | 개발 절차 | Git에 남는 것 |
  |---|---|---|
  | ① 기획 | 이슈 | 작업 브랜치 생성 |
  | ② 개발 | 브랜치 개발 | 커밋 |
  | ③ 코드 리뷰 | PR 리뷰 | diff 기준 리뷰 기록 |
  | ④~⑥ | CI(자동 검사) | 검사 결과 기록 |
  | ⑦ 판정 | 승인·병합 | 사람이 push, main 병합 |

## 11. 미정 → 전부 결정 (2026-11-22)
1. ~~폴더 배치~~ → 결정 (2026-11-22): 15절
2. ~~판정 키워드~~ → 결정 (2026-11-22): `VERDICT: PASS` / `VERDICT: BLOCK`. 판정 줄이 없으면 실패로 멈춤. 이유: 8절 Codex 4회 시험에서 확인된 형식이고, 한글은 인코딩(UTF-16 저장 사례, 14절) 차이로 비교가 어긋날 위험이 있음(추정)
3. ~~리뷰 기록~~ → 결정 (2026-11-22): 시도별 원문만 남기고 REVIEW.md는 없앰. 요약은 RESULT.md 하나 (15절)
4. ~~프로젝트 폴더 전달~~ → 결정 (2026-11-22): 환경변수 `PROJECT_ROOT`를 start-n8n.ps1에서 `$env:`로 지정. 이유: 한동안 한 프로젝트만 돌림(사용자) → 폴더를 바꿀 때 n8n을 다시 켜야 하는 단점이 작음. 흐름 맨 앞에서 PROJECT_ROOT에 PROJECT.md·TASK.md가 둘 다 있는지 확인하고, 없으면 멈춤. 여러 프로젝트를 번갈아 돌리게 되면 [시작] 입력 방식(Form Trigger)으로 다시 검토. 스크립트 수정은 n8n 구성 때
5. ~~NODES_EXCLUDE·환경변수 방식~~ → 결정 (2026-11-22): 현재 start-n8n.ps1 그대로. localFileTrigger만 막고, 환경변수는 `$env:`(그 창에서만). 이유: `setx`는 영구 설정이라 다른 프로그램에 영향, 쓰지 않는 파일 감시 기능은 닫아 둠
6. ~~GitHub 공개 여부~~ → 결정 (2026-11-22): ai-pipeline은 공개 저장소 (민감 정보 들어갈 가능성 없음, 사용자 확인). 기존 PoC는 고도화 때 PoC마다 자료를 확인한 뒤 공개 여부를 정함

## 12. v2 후보 (2026-11-22, 미확정)
- 방향: 이 PoC를 대표 포트폴리오로 키운다. v1은 연동만, 아래는 v1 완료 후 v2에서 넣는다.
| 기술 | 넣는 방식 (안) | 보여줄 수 있는 것 |
|---|---|---|
| LLM 연동 | 로컬 모델(Ollama)을 한 단계(예: 판정 정리·추가 검수)로 붙임. n8n에서 모델 교체 가능하게 | 구독 AI + 로컬 LLM 혼합, 에이전트 교체 가능 구조 |
| MCP | 파이프라인 상태(STATUS.json·logs)를 읽는 작은 MCP 서버를 직접 만들어 Claude Code·Codex가 같은 방식으로 조회 | MCP 서버 직접 구현 |
| Skills | 단계별 지시(개발·리뷰·검수)를 Claude Code Skill로 묶어 `claude -p`가 짧은 호출로 같은 지시를 쓰게 함 | 프로젝트 폴더만 바꿔 재사용하는 공통 지시 체계 |
- 확인 필요: Codex CLI의 MCP 지원 범위, Codex 쪽 Skill에 해당하는 방식(AGENTS.md 등), n8n의 LLM·MCP 노드 현황

## 13. 실행 환경 (2026-11-22)
- 환경 확인 결과: .pipeline/logs/env-check-20261122-104330.txt (AI 호출 0회)
  - 기본 Node: v26.13.0 → n8n 지원 범위(20.19~24.x, n8n 문서) 밖
  - claude: `C:\Users\apter\.local\bin\claude.exe` (2.1.316), 위치 1곳
  - codex: 3곳 발견. PATH 맨 앞은 VS Code 확장 내장본(0.164.0-alpha) — 확장 업데이트 시 경로가 바뀔 수 있음(추정)
- 결정: n8n 전용 Node 24를 따로 둔다 (기본 Node 26과 그 위의 codex는 건드리지 않음)
  - Node 24: `C:\dev\tools\node24` — scripts/get-node24.ps1 (공식 SHA256 대조 후 압축 해제)
  - n8n 2.48.7: `C:\dev\tools\n8n` 폴더에만 설치 (전역 설치 안 함) — scripts/setup-n8n.ps1
  - 실행: scripts/start-n8n.ps1 (그 창에서만 Node 24 우선, NODES_EXCLUDE 설정)
- npm 설치 스크립트 15개는 승인하지 않은 상태로 n8n 정상 시작·계정 생성 확인 (필요해지면 그 패키지만 승인)
- n8n 내장 AI 도우미(Anthropic API 키 입력 창)는 쓰지 않는다 (9절 API 키 미사용)
- 결정 (2026-11-22): n8n은 codex를 npm 설치본 전체 경로로 고정해 부른다
  - `C:\Users\apter\AppData\Local\Programs\AI-DevTools\node-v26.13.0-win-x64\codex.cmd`
  - 이유: PATH 맨 앞의 VS Code 확장 내장본은 alpha이고 확장 업데이트 시 경로가 바뀔 수 있음
  - ✅ (2026-11-22, Codex가 직접 실행해 확인) 이 경로의 버전: `codex-cli 0.166.0`, `codex login status` = ChatGPT 계정 로그인. 13절 위쪽의 0.164.0-alpha는 VS Code 확장 내장본이라 다른 설치본임 (업데이트 아님)
  - ✅ (2026-11-22 21:03, 16절 뼈대 pass 실행 S0) n8n에서 이 경로로 실행됨: `codex-cli 0.166.0` 종료 코드 0, `codex login status` = Logged in using ChatGPT. 같은 실행에서 node v24.22.3(n8n 전용 Node 24), claude 2.1.316 종료 코드 0
- 다음 할 일: 7절 완료. 11절 1~6번 모두 결정 (2026-11-22). n8n 흐름 구성은 16절. **이어서 할 일은 16절 맨 끝 "다음에 이어서", 2026-11-23 판정 구조 간소화는 17절**

## 14. `claude -p` 권한 설정 (2026-11-22 결정)
- 확인(공식 문서): `-p`에는 권한 확인 창이 없다. 허락이 필요한 호출은 **멈추지 않고 거부된 채 계속 진행**된다 (v2.1.302부터 기본 Manual 모드, 설치본 2.1.316).
- 결정: 모든 Claude 단계는 `--permission-mode dontAsk`(명단에 있는 것만 허용, 나머지는 묻지 않고 거부) + 단계별 `--allowedTools` 명단.
  - 함께 쓰는 옵션: `--permission-prompts none`(재시도하지 말라고 알림), `--output-format json`(거부 목록 `permission_denials` 확인용)
  - 쓰지 않는 것: `bypassPermissions`(전부 허용, 격리 환경 전용), `--bare`(구독 로그인을 안 읽고 API 키 필요 → 9절 위반)
- 단계별 명단 (안, 시험 후 확정):
  | 단계 | 허용 명단 | 비고 |
  |---|---|---|
  | ② 개발 | `Edit(./<대상 폴더>/**)` | Edit 규칙이 Write(새 파일)도 포함 (문서 확인) |
  | ④ 실행 | (해당 없음 — 2026-11-22부터 AI 없이 stage.ps1이 실행, 16절) | |
  | ⑥ 2차 검수 | 없음 (읽기만) | 출력은 n8n이 RESULT.md에 기록 |
- 시험: scripts/perm-test.ps1 — 허용된 파일 쓰기 1개 + 허용 안 한 명령(`node -p 42`) 1개를 한 번에 시킴. AI 호출 Claude 1회, Codex 0회
- 시험 결과 (2026-11-22 11:25, .pipeline/logs/perm-test-20261122-112514.json·.txt) — 확인:
  1. `Edit(./out/**)` 허용으로 새 파일 생성됨 (내용 `pipeline ok` 직접 확인) → Edit 규칙이 Write도 포함
  2. `node -p 42`는 거부됨. `permission_denials` 1건, 도구 이름 `Bash` → 이 노트북에서 셸 허용 규칙은 `Bash(...)`로 씀
  3. 거부가 있었는데도 **exitCode 0, `is_error: false`, `subtype: success`** → 종료 코드만으로는 거부를 알 수 없음
  4. Claude 본문 보고(STEP2=denied)도 맞았지만, 판정은 본문이 아니라 JSON 필드로 해야 함 (본문은 모델이 쓰는 글이라 틀릴 수 있음)
  5. 7초, 3턴. 아주 작은 작업인데도 입력이 약 6.6만 토큰(대부분 캐시, Claude Code 기본 지시문 분량으로 추정) → 호출 1회마다 고정 비용이 있음. `total_cost_usd` 0.0042는 API 정가 환산 추정치이고 Pro 한도 차감량은 아님
- 결정 (2026-11-22): n8n 멈춤 판정 = exitCode ≠ 0 **또는** `is_error` true **또는** `permission_denials` 1건 이상. 모든 Claude 단계(⑥ 포함) 공통 (5절)
- 결정 (2026-11-22): 로그·JSON은 UTF-8(BOM 없음)로 저장한다. 첫 시험 로그(112514)는 UTF-16으로 남아 있음(Windows PowerShell 기본값). perm-test.ps1 수정 완료, 수정본 재실행은 안 함(AI 호출 아끼려고)

## 15. 파일 배치 (2026-11-22 결정)
- 원칙: 사람이 읽는 파일은 최상위, 자동 흐름이 쓰는 파일은 `.pipeline/`에 모아 노트북에만 둔다.
  | 위치 | 파일 | 쓰는 쪽 | GitHub |
  |---|---|---|---|
  | 최상위 | PROJECT.md, TASK.md | 사람 | 올림 |
  | 최상위 | REPORT.md | Claude Code(②·④) | 올림 |
  | 최상위 | RESULT.md (결과 보고) | n8n이 ⑥ 출력과 단계 요약을 기록 | 올림 |
  | `.pipeline/` | STATUS.json, logs/, reviews/ (리뷰 원문 `review-001-s3.md`…) | n8n | 안 올림 (`.gitignore`) |
- REVIEW.md는 만들지 않는다. 사람은 ⑦ 판정 때 RESULT.md만 본다 (사용자 결정).
- REPORT.md(Claude Code의 주장)와 RESULT.md(검수 결론)를 따로 두는 이유: 작성자를 구분하기 위해.
- ⑥ 2차 검수는 `.pipeline/reviews/`의 ③·⑤ 원문을 직접 읽는다 (추정: 읽기 권한 안에서 가능, n8n 구성 때 확인).
- n8n 로컬 커밋에서 `.pipeline/`은 빠진다 (10절). 포트폴리오에는 커밋 기록·REPORT.md·RESULT.md가 남는다.
- 기존 PoC 고도화 때도 일단 최상위 배치를 유지하고, 상황을 봐서 바꾼다 (사용자 결정).
- ✅ (2026-11-22) 최상위 logs/(시험 기록)를 `.pipeline/logs/`로 옮김. 시험 스크립트 4개의 기록 위치와 이 문서의 경로도 함께 바꿈. `.gitignore`에 `.pipeline/` 추가

## 16. n8n 흐름 구성 (2026-11-22 진행 중)
- 결정 (사용자):
  1. 흐름은 워크플로 JSON 파일을 만들어 n8n에 가져오기(import)한다. 파일 `workflows/ai-pipeline-v1-skeleton.json`은 Git에 올린다 (포트폴리오)
  2. 파일 작성은 Claude 채팅이 직접 한다. n8n 실행과 확인은 사람이 한다
  3. 먼저 AI를 부르지 않는 뼈대(가짜 실행)로 흐름·분기·멈춤을 확인한 뒤, 단계를 하나씩 실제 호출로 바꾼다
- 구조: 각 단계 = Execute Command 노드 1개 → `scripts/stage.ps1 -Stage sN ...` 실행 → 스크립트가 stdout 마지막 줄에 JSON 1줄 출력 (`ok`, `verdict`, `attempt`, `ai_claude`, `ai_codex`…) → n8n IF 노드가 그 줄을 읽어 다음 단계를 정함
  - 이유: Windows 명령 줄에서 따옴표 처리가 까다로워 단계별 처리는 스크립트에 두고, n8n에는 순서와 분기만 둔다. 스크립트는 Git에서 검토할 수 있다
  - stage.ps1은 항상 종료 코드 0으로 끝내고 성공·실패는 JSON의 `ok`로 알린다. PowerShell 자체가 죽으면 n8n 노드가 오류로 멈춘다 (이 경우는 멈춤 기록이 남지 않음, 추정)
  - 재시도 규칙(5절)은 n8n IF 노드에 보이게 둔다: S3가 PASS가 아니면 "BLOCK이고 attempt < 3"일 때만 S2로 돌아감. 시도 번호는 n8n `$runIndex + 1`(그 노드가 몇 번째 실행인지)
  - 모든 단계 실패 분기는 "멈춤 기록"(stage end -Outcome stopped) → "멈춤"(Stop and Error)으로 모인다
  - 기록: `.pipeline/logs/run-<runId>.jsonl`(단계별 1줄), `.pipeline/STATUS.json`(현재 상태), `.pipeline/reviews/`(리뷰 원문)
  - 가짜 실행 결과 보고는 `.pipeline/fake/RESULT.md`에 쓴다 (최상위 RESULT.md를 시험 기록으로 더럽히지 않기 위해). 실제 실행만 최상위 RESULT.md
  - `-Mode real`은 아직 구현하지 않았고, S0·end 외에는 실행을 거부한다 (실수로 AI를 부르지 않게)
- S0 사전 확인 (AI 호출 0회): PROJECT_ROOT에 PROJECT.md·TASK.md가 있는지, claude.exe·codex.cmd(13절 고정 경로)가 있는지, `claude --version`, `codex --version`, `codex login status`의 종료 코드. → 13절의 "n8n에서 이 경로로 실행되는지"를 여기서 확인
- 가짜 시나리오 (설정 노드의 `scenario` 값을 바꿔 실행):
  | scenario | 기대 결과 | 확인하는 완료 조건 |
  |---|---|---|
  | pass | S0→S2→S3 PASS→S4→S5→S6→완료 기록 | 1, 4, 5 |
  | block1 | S3 1회차 BLOCK → S2 2회차 → S3 PASS → 끝까지 | 2 |
  | blockall | S3 BLOCK 3회(재시도 2회) 후 멈춤 | 5절 최대 2회 |
  | fail4 | S4 실패 → 멈춤 | 3 |
- 결정 (2026-11-22, 사용자): ⑤ 1차 검수가 BLOCK이어도 흐름은 ⑥으로 계속 간다 (⑤는 검사 결과를 남기는 단계이고 최종 판단은 ⑥·⑦이 함). 뼈대에서는 ⑤가 항상 PASS
- 확인 안 된 것 (추정): stage.ps1은 이 채팅 환경에 PowerShell이 없어 실행해 보지 못함. 워크플로 JSON의 노드 버전(IF 2.2, Set 3.4 등)이 n8n 2.48.7에서 그대로 가져와지는지. 첫 뼈대 실행에서 확인한다
- 사람이 할 일: `git init -b main`(PowerShell), n8n을 start-n8n.ps1로 다시 시작(PROJECT_ROOT 반영), 워크플로 가져오기, 시나리오 4개 실행
- 뼈대 실행 기록 (2026-11-22):
  - 처음 4회(pass·block1·blockall·fail4)는 "시작"만 실행되고 끝남 → 원인 확인: 워크플로 JSON에 "시작 → 설정" 연결이 빠져 있었음(Claude 작성 실수). 두 노드가 가까워 화면에서는 연결된 것처럼 보였고, "설정" 노드 INPUT의 "No input connected"로 확인. n8n 화면에서 직접 연결, JSON 파일도 수정함
  - 참고: 노드 안의 Execute step은 그 노드까지만 실행한다. 흐름 전체는 캔버스 아래 Execute workflow로 실행한다
  - ✅ pass (run 20261122-070332, 21:03:33~35): S0→S2→S3 PASS→S4→S5 PASS→S6→완료 기록, 모두 ok. STATUS.json `end/done/pass`, `.pipeline/fake/RESULT.md` 생성, AI 호출 Claude 0·Codex 0. 한글(Windows 오류 메시지)도 UTF-8로 깨지지 않고 기록됨
  - 발견 1: S0 기록에 `codex login status`의 정상 출력이 PowerShell 오류 형식(NativeCommandError)으로 섞임. codex가 stderr로 출력하고 PowerShell 5.1이 이를 오류 객체로 감싸서 생김(추정, 종료 코드는 0). stage.ps1에서 문자열로 바꿔 기록하도록 수정함(재실행 확인 전)
  - 발견 2: runId `070332`인데 실제 시각은 21:03 → n8n 시간대가 한국과 14시간 차이(미국 동부로 추정). PowerShell이 쓰는 시각(`at`)은 한국 시간이라 이름과 시각이 어긋남 → start-n8n.ps1에 `$env:GENERIC_TIMEZONE = "Asia/Seoul"` 추가 (2026-11-22, 사용자 결정). n8n 재시작 후 runId로 확인
  - 남은 시험: block1, blockall, fail4
- 실제 호출 전환 (2026-11-22 결정, 사용자): ② 개발부터 바꾼다 (다른 단계가 검사할 코드가 ②에서 처음 생기므로). TASK.md(work/hello.py)를 실제 작업으로 확정
  - 방식: "설정" 노드의 `mode` 값으로 고름. `fake` = 전부 가짜, `real:s2` = S2만 실제·나머지 가짜, `real` = 전부 실제. 워크플로는 바꾸지 않음 (mode는 이미 모든 단계에 전달되므로)
  - 아직 구현 안 된 단계를 실제로 지정하면 AI를 부르지 않고 멈춤. 지금 구현된 것: S2
  - S2 실제: `claude -p` (Haiku, dontAsk, 허용 `Edit(./work/**)`·`Edit(./REPORT.md)`, 명령 실행 허용 없음, 최대 10턴). 2회차부터는 직전 S3 리뷰 파일을 먼저 읽게 함. 판정은 종료 코드·is_error·permission_denials (5·14절). 원문은 `.pipeline/logs/run-<runId>-s2-<시도>.json`
  - 결과 보고: 전부 실제(`real`)일 때만 최상위 RESULT.md, 일부만 실제면 `.pipeline/fake/RESULT.md`
  - ✅ (2026-11-22) 위 두 가지 확인: `Edit(./REPORT.md)`로 REPORT.md 새로 생성됨, Read는 허용 명단 없이 됨 (TASK.md를 읽고 작업함). permission_denials 0건
  - 첫 시도 실패: stage.ps1을 노트북에 보낼 때 이전 사본이 들어가 `real:s2`가 입력값 검사에서 거부됨 (Claude 파일 전달 실수, 다시 보내고 크기로 확인). 이 오류는 스크립트 시작 전에 나서 기록이 남지 않음 → 사각지대, 보완 예정
  - ✅ real:s2 (run 20261122-212441, 21:24:42~25:08): S2만 실제, 나머지 가짜로 끝까지 통과. Claude 1회 (Haiku, 7턴, 17초, exit 0, is_error false)
    - 결과물: `work/hello.py` (스크립트 위치 기준으로 `runs/output.txt`에 `pipeline ok`를 줄바꿈 없이 씀), REPORT.md 맨 위 섹션 (만든 것, 실행 안 함, 완료 조건별 확인 방법)
    - 토큰: input 8 / cache_write 36,249 / cache_read 152,420 / output 2,867 (그중 thinking 1,196). 8절 측정 호출(평균 약 1.5만/5.1만/260)보다 큼 → 실제 작업은 턴이 많아 1회 비용이 큼. 사용량 %는 미확인
    - 참고: n8n 마지막 노드 출력의 `ai_claude: 0`은 end 단계 자신의 호출 수. 실행 전체 합계는 RESULT의 "AI calls"에 나옴
  - ✅ real:s4 (run 20261122-212833, 21:29:06~26): S4만 실제. Claude 1회 (Haiku, 5턴, 12초, exit 0, 거부 0건). 허용 `Bash(python work/hello.py)`·`Edit(./REPORT.md)`
    - stage.ps1이 직접 확인: `runs/output.txt`가 이 단계 중에 새로 쓰임(True), 내용 `pipeline ok`(11바이트, 줄바꿈 없음) → n8n 환경에서 python 실행됨
    - REPORT.md 맨 위에 S4 섹션 추가됨. 다만 종료 코드는 Claude가 "출력이 없어 0으로 봄, 직접 확인 못 함"이라고 씀 → Claude 보고는 추정이 섞일 수 있음. 판정은 스크립트의 파일 확인으로 함
    - 토큰: cache_write 16,601 / cache_read 123,632 / output 1,351
    - S2(실제)와 S4 실제를 공통 함수 Invoke-Claude로 묶음
- 결정 (2026-11-22, 사용자): ④ 실행은 AI 없이 stage.ps1이 직접 한다 (B안)
  - 이유: 정해진 명령 하나만 실행하는 단계라 AI가 필요 없음. 위 real:s4 시험에서 Claude가 종료 코드를 확인하지 못하고 추정으로 적음 → 스크립트가 직접 재면 정확하고 AI 호출 0회
  - 방식: TASK.md의 `RUN:` 줄을 읽어 `cmd /c`로 실행 (프로젝트 폴더만 바꾸면 쓰는 공통 흐름 유지, 1절). stdout·stderr는 `.pipeline/logs/run-<runId>-s4.*.txt`, REPORT.md 맨 위에 명령·종료 코드·출력을 스크립트가 기록. 판정 = 종료 코드 0
  - 영향: v1 1회 실행의 Claude 최대 호출이 5회 → 4회 (②·⑥ + ② 재작업 2회). 2·3·14절 표 수정
  - 한계 (추정): PROJECT_ROOT 경로에 공백이 있으면 출력 저장이 깨질 수 있음 (지금 경로는 공백 없음). `RUN:`은 한 줄 명령만
  - ✅ B안 시험 (run 20261122-213538, real:s4): AI 0회로 끝까지 통과. `python work/hello.py` 종료 코드 0(스크립트가 측정), `runs/output.txt` = `pipeline ok`, stdout·stderr 비어 있음
    - 발견·수정: REPORT.md 섹션이 한 줄로 붙어 기록됨. 원인: PowerShell에서 `,`가 `+`보다 먼저 묶여 배열이 문자열로 합쳐짐. stage.ps1에 괄호 추가, 해당 REPORT.md 줄도 바로잡음 (수정본 재실행 확인 전)
  - ③ 실제(Codex) 구현 (2026-11-22): `codex exec --sandbox read-only --skip-git-repo-check --ephemeral --json -o <파일>` (8절과 같음). Codex 답을 스크립트가 `.pipeline/reviews/review-<runId>-s3-<시도>.md`로 저장. 멈춤 = 종료 코드≠0, turn.failed/error, 판정 줄 없음. BLOCK은 TASK 완료 조건을 깨는 문제에만 쓰게 지시
  - ❌ 첫 real:s3 (run 20261122-213815): S3에서 1시간 넘게 멈춤. 원인 확인: stderr에 `Reading additional input from stdin...` → codex exec가 표준 입력(stdin)을 끝까지 기다림. n8n에서 실행하면 stdin이 닫히지 않아 영원히 대기. 8절 측정은 PowerShell 창에서 직접 돌려서 이 문제가 안 보였음
    - 수정: stage.ps1에서 codex에 빈 입력을 넘겨 stdin을 바로 닫음 (`"" | & $codex ...`). 재실행 확인 전
    - 사용량 (추정): 입력을 기다리는 단계에서 멈춰 Codex 요청은 보내지 않았을 가능성이 큼
    - 결정 (2026-11-22, 사용자): 시간 제한 **3분**. 5절 "시간이 넘으면 멈춘다" 규칙 구현
      - 방식: claude·codex·④ 실행 명령을 모두 공통 함수 Invoke-Native로 실행. 표준 입력은 시작하자마자 닫음(위 stdin 문제도 같이 해결), 3분이 넘으면 `taskkill /T /F`로 하위 프로세스까지 종료하고 실패로 기록 → 흐름 멈춤
      - 이유: 지금까지 실측은 Claude 12~17초, Codex 9~17초라 3분이면 여유 있음 (사용자 판단: 10분은 너무 김)
      - ✅ codex는 확인 (아래 real:s3). claude·python은 Invoke-Native로 아직 안 돌려 봄
  - ✅ real:s3 (run 20261122-223102): Codex 1회, 약 23초, exit 0, 실패 이벤트 없음, 판정 `VERDICT: PASS` (문제 None). 리뷰 파일은 스크립트가 저장. Codex는 PowerShell로 TASK.md·work 파일을 읽기만 함
    - 토큰: input 50,974 (캐시 32,640) / output 357 (reasoning 160)
    - stderr에 `Reading additional input from stdin...`은 여전히 찍히지만, 입력이 바로 닫혀 기다리지 않고 진행됨
    - 관찰 (원인 미확인): runId 22:31:02 → S0 끝 22:33:54, S0이 약 3분 걸림 (전에는 1초). S0의 버전·로그인 확인은 시간 제한 함수를 안 거침. 이전에 멈췄던 codex가 남아 있었을 가능성(추정)
- 결정·구현 (2026-11-22, 사용자): S0도 3분 제한 함수로, ⑤·⑥은 한 번에 실제로 전환
  - S0: claude·codex 버전과 codex 로그인 확인을 Invoke-Native로 실행 (3분 제한, 입력 바로 닫음). AI 호출 0회 그대로
  - ⑤ 1차 검수 실제: Codex 읽기 전용. TASK.md·REPORT.md 맨 위 섹션·work·runs를 대조, 첫 줄 VERDICT. 리뷰 원문은 스크립트가 `review-<runId>-s5.md`로 저장. BLOCK이어도 ⑥으로 감 (위 결정)
  - ⑥ 2차 검수 실제: Claude 새 세션, 허용 도구 없음(읽기만). ③ 마지막 리뷰와 ⑤ 리뷰를 읽고 한국어 15줄 이내로 ①지적의 중요도 ②놓친 문제 ③⑤와의 이견 표 ④마지막 줄 `RECOMMEND: PASS/BLOCK`(사람 판정용 권고). 답은 `review-<runId>-s6.md`로 저장하고 end 단계가 RESULT에 "S6 second review"로 붙임
  - ③·⑤는 공통 함수 Invoke-Codex로 묶음
  - 이제 모든 단계 실제 구현됨. `mode`=`real`이면 결과 보고는 최상위 RESULT.md
  - 확인 전 (추정): ⑥이 허용 도구 없이 .pipeline/reviews/ 파일을 읽을 수 있는지(15절 추정), Claude·python이 Invoke-Native로도 전처럼 도는지
- ✅ 첫 전체 실제 실행 (mode=real, run 20261122-224021, 22:40:21~41:53, 약 1분 30초): S0→②→③ PASS→④→⑤ PASS→⑥→완료. 최상위 RESULT.md 처음 생성
  - AI 호출: Claude 2회(②·⑥), Codex 2회(③·⑤). 위 "확인 전" 두 가지도 확인: ⑥은 허용 도구 없이 .pipeline/reviews/ 파일을 읽음, Claude·python도 Invoke-Native로 정상
  - ⑥ 토큰이 가장 큼: cache_write 24,962 / cache_read 175,294 / output 6,167, 18턴, 29초
  - ⑥이 짚은 기록 공백 (확인: 지적 내용은 사실과 맞음): ① S0에 python 버전 기록 없음 ② ④ 종료 코드가 REPORT에만 있고 리뷰어가 볼 수 있는 원자료에는 없음 ③ runs/output.txt가 이번 실행에서 새로 쓰였는지 증거 없음. ⑥은 ⑤의 "run log에 종료 코드" 표현이 부정확하다고 이견 표에 적음 → 2차 검수가 실제로 1차를 검증함
  - 참고 (확인): ② S2가 hello.py를 pathlib 방식으로 다시 씀. REPORT에는 "새 파일"이라 적었지만 실제로는 기존 파일을 바꾼 것 → 리뷰어 3명 모두 못 잡음 (작은 부정확)
  - 6절 완료 조건: 1 ✅(실제) / 2 가짜 실행으로만 확인(block1) / 3 가짜 실행으로만 확인(fail4) / 4 ✅ RESULT.md / 5 ✅ 호출 수 기록
- 다음에 이어서 (2026-11-22 22:43 기준, 오늘 작업 종료):
  - 상태: 모든 단계 실제 구현, mode=real 전체 실행 1회 PASS (run 20261122-224021). n8n "설정" 노드 mode는 마지막에 `real`로 둠
  - 결정할 것:
    1. ⑦ 판정: run 20261122-224021의 RESULT.md를 보고 PASS 확정 여부
    2. ⑥이 짚은 기록 공백 3개 보완 여부 (AI 호출 없이 stage.ps1만 수정): S0에 python 버전, ④ 종료 코드를 원자료 파일로, ④ 실행 전 이전 runs 출력 삭제
    3. 완료 조건 2·3을 실제 호출로도 확인할지, 가짜 실행 확인으로 충분한지
    4. 10절 Git 로컬 커밋 단계를 v1에 넣을지
  - 그 밖에 남은 것: 워크플로 JSON을 n8n에서 내보내(export) 파일과 맞추기(화면에서 시작→설정 연결을 직접 이음), PROJECT_ROOT가 없거나 입력값 검사 실패처럼 스크립트 시작 전 오류는 기록이 안 남는 사각지대, PowerShell 오류 메시지 한글 깨짐(CP949)

## 17. n8n 판정 구조 간소화 (2026-11-23)
- 목적: 단계마다 붙어 있던 IF 7개를 공통 판정 노드 1개로 합쳐 **실행 제어 구조만** 단순화한다. 역할 분담(2·3절)·권한(14절)·검수 독립성·stage.ps1 규칙(16절)은 바꾸지 않는다.
- 결정 (2026-11-23, 사용자):
  1. B안 12개 노드. 실패면 결과 기록 → IF → Stop and Error로 명시적으로 멈춘다 (n8n 실행 목록에도 실패로 표시). stage.ps1 "항상 종료 코드 0" 규칙 유지. 노드 수(10개)보다 안정성·일관성 우선
  2. 역할은 그대로: ② 개발 Claude Code, ③ 코드 리뷰·⑤ 1차 검수 Codex, ⑥ 2차 검수 Claude 새 세션. ① 기획·TASK 작성은 n8n 밖 사람 단계
  3. 이번 범위는 워크플로 구조 변경만. 다음은 구조 검증 후 별도 작업: S0 python 버전 기록, S4 종료 코드 원자료 보존, S4 실행 전 이전 출력 삭제, stage.ps1 입력값 검사 구조
- 노드 구성 (18개 → 12개):
  | 구분 | 이전 | 이후 |
  |---|---|---|
  | 시작·설정 | 2 | 2 (설정에 `maxAttempts` = 3 추가) |
  | 단계 실행 (S0·S2~S6) | 6 | 6 (명령 그대로) |
  | 판정 | IF 7 | Switch 1 (`판정`) |
  | 결과 기록 | 완료 기록·멈춤 기록 2 | `결과 기록` 1 |
  | 멈춤 | Stop 1 | IF `정상 완료?` 1 + Stop `멈춤` 1 |
- 연결: 단계 6개는 모두 `판정`으로 간다. `판정`이 다음 단계를 고른다.
- 판정 규칙 (위에서부터 처음 맞는 규칙 하나만 적용, 이전 IF 조건을 그대로 옮김):
  | 방금 끝난 단계 | 조건 | 다음 | 이전 노드 |
  |---|---|---|---|
  | s0 | ok | S2 | S0 통과? |
  | s2 | ok | S3 | S2 통과? |
  | s3 | ok, verdict = PASS | S4 | S3 PASS? |
  | s3 | ok, verdict = BLOCK, attempt < maxAttempts | S2 (재작업) | S3 다시 할 수 있나? |
  | s4 | ok | S5 | S4 통과? |
  | s5 | ok (PASS·BLOCK 상관없음, 16절 결정) | S6 | S5 통과? |
  | 그 밖 전부 | S6 끝, 모든 실패, 재시도 초과, 판정 줄 이상 | 결과 기록 | 각 IF의 false 갈래 |
- 결과 기록: 이전 완료 기록·멈춤 기록과 같은 `stage.ps1 -Stage end`. Outcome = 방금 끝난 단계가 s6이고 ok면 `pass`, 아니면 `stopped`
- 정상 완료?: 결과 기록의 ok가 true면 그대로 끝(성공), 아니면 `멈춤`(실패 표시)
- 재시도 한도: 설정 노드 `maxAttempts` = 3 (처음 1회 + 재시도 2회, 5절) 한 곳에서 관리. 이전에는 IF 안에 숫자 3. 시도 번호는 그대로 각 노드의 `$runIndex + 1`
- stage.ps1 수정: 없음 (end가 이미 `-Outcome pass|stopped`를 받으므로)
- 사전 확인 (2026-11-23, AI 호출 0회):
  - ✅ n8n 2.48.7이 쓰는 n8n-nodes-base 2.48.4에 Switch 3~3.5가 있음. npm 패키지 소스로 확인 (노트북 설치본은 직접 열어 보지 못함)
  - ✅ Switch 3.2와 IF 2.2는 같은 판정 엔진 버전(filter 2)을 쓴다. 대소문자 옵션(Ignore Case, 기본 켬)과 느슨한 타입 비교 설정 방식도 같다 → 조건을 옮겨도 판정 방식이 같음
  - ✅ Switch는 기본으로 처음 맞는 규칙 하나에만 보내고, 맞는 규칙이 없으면 추가 출력(fallback)으로 보낸다
  - 참고 (소스 확인): Ignore Case 기본값 때문에 이전 IF도 대소문자를 구분하지 않았다 (`block` = `BLOCK`). 새 구조도 같음
- 비교 시뮬레이션 (2026-11-23, AI 호출 0회): n8n-workflow 2.48.3의 실제 판정 함수로 이전·새 JSON을 같은 가짜 단계 출력으로 돌려 실행 순서·Outcome·n8n 실행 상태를 비교. 시나리오 4개 + 추가 11건(각 단계 실패, S3 판정 줄 없음, S5 BLOCK, S6 실패 등) = 15건 중 14건 같음
  - 다른 1건: S6까지 정상인데 **결과 기록 스크립트 자체가 오류**일 때. 이전: n8n은 '성공'으로 끝남(RESULT가 안 써져도 모름). 이후: '실패'로 멈춤. 의도된 차이 (사용자 확인 필요)
  - 한계 (추정): 연결과 판정만 재현했다. n8n 가져오기·실제 실행은 아래 시험으로 확인
- 사람이 할 일: n8n에 `workflows/ai-pipeline-v1-skeleton.json` 다시 가져오기 → 설정 mode = `fake`(파일 기본값) → pass·block1·blockall·fail4 실행
- 기대 결과 (이전 기록 run-20261122-070332·211615·211631·211656과 비교):
  | scenario | 단계 순서 | 결과 기록 | n8n 실행 상태 |
  |---|---|---|---|
  | pass | S0→S2→S3 PASS→S4→S5→S6 | PASS | 성공 |
  | block1 | S0→S2#1→S3#1 BLOCK→S2#2→S3#2 PASS→S4→S5→S6 | PASS | 성공 |
  | blockall | S0→(S2→S3 BLOCK)×3 | STOPPED, stopped at s3 (attempt 3) | 실패 (멈춤) |
  | fail4 | S0→S2→S3 PASS→S4 실패 | STOPPED, stopped at s4 | 실패 (멈춤) |
- 백업: `.pipeline/logs/PROJECT.md.bak-20261123-0800`, `.pipeline/logs/ai-pipeline-v1-skeleton.json.bak-20261123-0800`
- 실행 검증 (2026-11-23, 사람이 n8n에서 실행, AI 호출 0회):
  - 처음 가져오기는 기존 워크플로를 열어 둔 채 했다. n8n은 이때 노드를 기존 캔버스에 붙여 넣는다(추정, 화면으로 확인). 그 상태로 실행한 run 20261123-080359는 mode=real로 돌아 AI 4회(Claude 2, Codex 2)가 쓰였고 최상위 RESULT.md·REPORT.md에 기록됨 (정상 실행 기록이라 그대로 둠). 이후 새 워크플로를 따로 만들어 다시 가져옴
  - 시나리오 4개 결과 (run log의 단계·시도·ok·verdict, RESULT의 stopped at, AI 호출 수를 이전 기록과 비교):
    | scenario | 새 run | 이전 run | 결과 |
    |---|---|---|---|
    | pass | 20261123-080717 | 20261122-070332 | 같음: S0→S2→S3 PASS→S4→S5 PASS→S6→end pass |
    | block1 | 20261123-080745 | 20261122-211615 | 같음: S3#1 BLOCK→S2#2→S3#2 PASS→…→end pass |
    | blockall | 20261123-080801 | 20261122-211631 | 같음: (S2→S3 BLOCK)×3→end stopped, stopped at s3 (attempt 3) |
    | fail4 | 20261123-080815 | 20261122-211656 | 같음: S4 실패→end stopped, stopped at s4 (attempt 1) |
  - 4개 모두 AI calls claude 0, codex 0
  - 파일로 확인 못 한 것: n8n 실행 목록의 상태 (기대: pass·block1 성공, blockall·fail4 실패). 사람이 화면에서 확인

## 18. v1 마무리 (2026-11-23 진행 중)
- 결정 (2026-11-23, 사용자):
  1. Git 로컬 커밋 단계를 v1에 넣는다 (10절, 포트폴리오 목적)
  2. 완료 조건 2·3(재작업·멈춤)은 실제 호출로 다시 확인하지 않는다. 가짜 실행 확인(16·17절)으로 충분 (AI 호출 절약)
  3. 17절에서 미룬 stage.ps1 보완 4개는 v1 안에서 끝낸다: S0 python 버전 기록, S4 종료 코드 원자료 보존, S4 실행 전 이전 출력 처리, 입력값 검사 구조
- 보류 (2026-11-23, 사용자): 코드 수정이 없는 재실행(일배치 등)에도 ②·③이 매번 도는 문제. 개발 흐름·운영 흐름 분리 여부는 시나리오가 생기면 정한다
- 현재 Git 상태 (확인): `main` 브랜치, 커밋 0개, `.gitignore` = `.pipeline/`, 원격 저장소 설정 없음
- 설계 확정 (2026-11-23, 사용자 결정 + 3번은 Claude 의견 채택):
  1. 커밋은 실행 끝에 **한 번**. mode=`real`이고 PASS일 때만, 결과 기록(end) 단계에서 stage.ps1이 직접 실행 (AI가 git을 다루지 않음 → 14절 권한 그대로). 노드 수 12개 그대로
     - 순서: RESULT.md 작성 → `git checkout -b run/<runId>` → `git add -A` → `git commit -F <UTF-8 메시지 파일>` (명령 줄 한글 깨짐을 피하려고 파일로 넘김)
     - 커밋 뒤 작업 폴더는 `run/<runId>` 브랜치에 그대로 둔다. ⑦ 승인 시 사람이 `git switch main` → `git merge --ff-only run/<runId>` → `git push` (10절)
     - git이 실패하면 RESULT 해당 섹션에 `git: FAILED` 한 줄을 남기고 결과 기록이 실패 → `멈춤`
  2. **정상 완료만 브랜치를 남긴다.** 멈춘 실행·fake·일부 real은 브랜치·커밋 없음 (바뀐 파일은 작업 폴더에 커밋 안 된 채 남음)
  3. 실행 전부터 바뀌어 있던 파일: S0이 **기록만 하고 진행**한다 (`.pipeline/logs/run-<runId>-s0-gitstatus.txt`). RESULT에 "changed before run"으로 표시 → 사람 손 변경이 커밋에 섞였는지 ⑦에서 확인. 이유: PROJECT.md는 Claude가 자주 고치고 REPORT.md는 매 실행 바뀌어서, 멈춤으로 하면 실행 전마다 사람이 커밋해야 함
- stage.ps1 보완 (2026-11-23 구현, 백업 `.pipeline/logs/stage.ps1.bak-20261123-0830`):
  | 항목 | 구현 |
  |---|---|
  | S0 python | `python --version` 기록만 (멈춤 조건 아님, 다른 프로젝트는 python을 안 쓸 수 있음) |
  | S0 git (모든 mode) | git 실행 가능, 첫 커밋 있음, 작성자(user.name·email) 설정 → 하나라도 없으면 S0 실패. 현재 브랜치와 실행 전 변경 파일 수 기록 |
  | S4 종료 코드 원자료 | `.pipeline/logs/run-<runId>-s4.json` (명령, 종료 코드, 시간 초과 여부, 시작·끝 시각, 출력 파일 위치). ⑤·⑥ 지시문에 이 파일을 읽으라고 한 줄 추가 (역할·허용 도구는 그대로) |
  | S4 이전 출력 | real 실행 전 `runs/` 안 파일을 `.pipeline/runs-prev/<runId>/`로 **옮김** (삭제 아님). 옮긴 수를 기록 |
  | 입력값 검사 | 인자 선언부 검사를 본문으로 옮김. 잘못된 값도 JSON 한 줄로 실패를 알리고 run log에 남음. 단 RunId 형식이 틀리면 로그 파일 이름을 만들 수 없어 기록 없이 JSON만 출력 |
- 시험 (2026-11-23, 이 채팅 작업 공간, AI 호출 0회): PowerShell 7.4로 문법 오류 0건. cmd.exe·claude·codex를 흉내 낸 대역과 임시 Git 저장소로 확인: 잘못된 인자 4종 → 실패 JSON, S0 git·python 기록, S4 이전 출력 옮김·원자료 기록, end fake(커밋 없음)·real stopped(브랜치 없음)·real pass(브랜치+커밋 1개, 한글 메시지 정상)·git 실패(RESULT에 FAILED, ok=false)
  - 한계 (추정): 노트북의 Windows PowerShell 5.1·실제 cmd.exe·Windows용 git에서는 아직 안 돌림. stage.ps1은 ASCII만 써서 5.1의 인코딩 문제는 피함
- 사람이 할 일 (순서대로):
  1. 노트북 PowerShell에서 `git config --global user.name`, `git config --global user.email` 확인 (비어 있으면 설정)
  2. 첫 커밋: `cd C:\dev\ai-pipeline` → `git add -A` → `git commit -m "v1 baseline before git stage"` (이게 없으면 S0이 멈춤)
  3. n8n 새 워크플로(12노드)에서 mode=`fake`로 pass·block1·blockall·fail4 다시 실행 → 17절과 같은 결과 + S0 note에 python·git 기록이 나오는지
  4. 커밋 확인용 real 실행 1회는 따로 결정 (AI 호출 Claude 2·Codex 2)
- ✅ 노트북 확인 (2026-11-23 08:42~08:45, AI 호출 0회):
  - 첫 커밋 (사람): `v1 baseline before git stage` (main, 작성자 설정됨). `.pipeline/`은 빠지고 scripts·workflows·tests·work 등 26개 파일
  - fake 4개 다시 실행 (Windows PowerShell 5.1, 실제 cmd.exe·git): pass 084458, block1 084521, blockall 084535, fail4 084550 → 단계·시도·판정·멈춘 위치 모두 17절과 같음
  - S0 새 기록 정상: `python=Python 3.12.10`, `git=git version 2.56.0.windows.4`, `head=ok`, `author=set`, `branch=main`, `changed before run=0`
  - RESULT에 `changed before run`·`git: no commit` 줄 정상. fake라 브랜치·커밋 생기지 않음 (main 커밋 1개 그대로)
  - 아직 확인 안 함: real PASS의 커밋(브랜치 생성·커밋), real S4의 이전 출력 옮기기·s4.json, 입력값 오류의 n8n 경로 (이 채팅 작업 공간에서만 확인)
- ✅ real 확인 (run 20261123-084736, 08:47:36~08:49:06, Claude 2·Codex 2):
  - PASS. `run/20261123-084736`에 커밋 `6f0ec5c` 1개 (PROJECT.md·REPORT.md·RESULT.md. hello.py·runs/output.txt는 내용이 같아 변경 없음). 한글 커밋 메시지 정상
  - S4: 이전 `runs/output.txt`를 `.pipeline/runs-prev/20261123-084736/`로 옮긴 뒤 새로 생성, `run-…-s4.json` 기록. ⑤ Codex가 이 파일로 종료 코드를 확인함 (리뷰 원문). ⑥이 읽었는지는 출력에 남지 않아 미확인
  - RESULT: `changed before run: 1 - M PROJECT.md`, `git: commit on branch …` 정상
  - ⑥ 지적: 완료 조건 3("어떻게 확인했는지")이 계획만 있고 결과가 없어 약함 (RECOMMEND PASS). "S0 변경 1개 vs 시작 시점 2개" 지적은 착오로 봄 — S0 기록은 PROJECT.md 1개, REPORT.md는 그 뒤 ②가 바꿈. Claude Code가 세션 시작 때 받는 git 상태가 ② 이후 시점이라 생긴 차이로 추정
  - ⑦ 판정 (사람): 승인, `git merge --ff-only`로 main 병합 (main = `6f0ec5c`)
  - 참고 (확인): 병합 뒤 작업 폴더 파일이 CRLF로 바뀜 — Windows git의 줄바꿈 자동 변환(autocrlf)으로 추정. 내용 변경은 없음(autocrlf 기준 git status 깨끗)
  - 참고: `refs/agents/…` "Agent host session" 커밋 3개가 있음. 파이프라인과 무관하고 main 이력에 없음. 노트북의 다른 AI 도구가 남긴 체크포인트로 추정(출처 미확인). main만 push하면 올라가지 않음
- GitHub (2026-11-23): 공개 저장소 https://github.com/zoobihn-youn/ai-pipeline 생성됨. 저장소에 README.md 커밋 1개가 이미 있어(GitHub 화면 확인) 로컬 main과 이력이 달라 그냥 push하면 거절됨 → 처리 방법 결정 필요
- 한글 깨짐 (2026-11-23 조사):
  - 로그 파일: 해결됨 (확인). 읽을 수 없는 로그 5개는 모두 11/22 초기의 PowerShell `2>` 리디렉션(UTF-16) 파일. Invoke-Native 도입 뒤 stderr는 전부 UTF-8, 깨진 글자 없음 → 16절 "PowerShell 오류 메시지 한글 깨짐"은 종료
  - **Codex가 한글을 못 읽음 (확인, 현재 문제)**: ③·⑤ 기록의 `Get-Content TASK.md` 결과가 `?�업`처럼 깨짐. `-Encoding UTF8`로 다시 읽어도 깨짐 → 읽기보다 PowerShell 5.1의 출력 인코딩(CP949)을 Codex가 UTF-8로 해석해서 생기는 문제로 추정. 영향: ③·⑤가 TASK.md의 한글 완료 조건을 못 본 채 영어 부분(RUN·파일·코드)만으로 판단했을 가능성. ②·⑥ Claude Code는 자체 읽기 도구라 문제없음 (⑥ 한글 인용 정확)
  - 결정 (사용자): C안 — 사용자 PowerShell 프로필에 UTF-8 출력 설정 (노트북의 모든 PowerShell 창에 적용, 사용자 동의). 이유: 모델이 지시를 따르는지와 무관하게 적용됨. Codex는 `powershell.exe -Command`를 프로필을 읽는 방식으로 실행함 (기록 확인). stage.ps1은 `-NoProfile`로 실행되므로 영향 없음
  - 확인 방법: n8n mode=`real:s3`(Codex 1회, 나머지 fake) → ③ 기록의 Get-Content 결과에 한글이 정상인지
  - ❌ C안 시험 (run 20261123-091443, mode=real:s3, Codex 1회): 여전히 깨짐. 프로필의 `Get-Content` 기본 인코딩도 적용되지 않음 → Codex가 실행한 PowerShell에 프로필이 적용되지 않은 것으로 봄
    - 조사 (codex 0.166.0 Windows 실행 파일의 문자열, 확인): Codex는 PowerShell 명령 앞에 이미 `try { [Console]::OutputEncoding=[System.Text.Encoding]::UTF8 } catch {}`를 붙이는 코드를 갖고 있음. 그런데도 깨짐 → 콘솔이 없는 상태(샌드박스 실행)라 이 설정이 오류로 무시되는 것으로 추정. 프로필에 넣은 같은 줄도 같은 이유로 효과가 없었을 가능성이 큼
    - 결론: PowerShell 출력 인코딩을 바꾸는 방식(A·B·C)으로는 해결이 어려움 (추정, 근거 위와 같음)
  - 결정 (사용자): 1번 — stage.ps1이 TASK.md(③·⑤)와 이번 실행의 REPORT.md 섹션(⑤)을 UTF-8로 읽어 Codex의 표준 입력으로 넘긴다. 프로필 세 줄은 평소 PowerShell 창에서 정상(65001, 한글 정상)이라 그대로 둠
    - 근거 (확인): codex 0.166.0 도움말 문구 "If stdin is piped and a prompt is also provided, stdin is appended as a `<stdin>` block"
    - 구현: Invoke-Native에 표준 입력 텍스트 인자 추가 (UTF-8 바이트를 직접 씀, BOM 없음). 지시문에 "stdin 블록의 글이 실제 내용이고 셸로 읽으면 한글이 깨져 보일 수 있다" 한 문장 추가. 넘긴 내용은 `.pipeline/logs/run-<runId>-s3-<시도>.stdin.txt`, `-s5.stdin.txt`에 남김. 역할·읽기 전용 권한은 그대로
    - 시험 (이 채팅 작업 공간, 대역 Codex): 받은 표준 입력이 저장본과 같고 한글 정상, UTF-8·BOM 없음. ⑤는 이번 실행의 REPORT 섹션만 받음(이전 실행 섹션 제외). fake는 영향 없음
    - 노트북 확인: n8n mode=`real:s3` (Codex 1회) → ③ 리뷰가 한글 완료 조건을 언급하는지, `.stdin.txt` 한글 정상인지
  - 노트북 확인 (run 20261123-092030, mode=real:s3, **Codex 3회** — BLOCK이 나서 재시도 규칙대로 3회까지 감):
    - ✅ 한글 전달 확인: `.stdin.txt` 한글 정상. 2·3회차 리뷰가 "완료 조건 3"을 한글로 인용함 → Codex가 표준 입력으로 한글 완료 조건을 읽음. 셸로 읽은 결과는 여전히 깨짐 (예상대로)
    - ✅ 재시도 규칙: BLOCK 3회 → 멈춤, 결과 기록·n8n 실패 표시 정상
    - 발견 1 (지시문): 1회차는 파일을 하나도 읽지 않고 "주어진 글에 TASK.md만 있다"며 BLOCK → 추가한 문장("stdin 블록이 실제 내용")을 Codex가 "이것만 보라"로 해석함. Claude 지시문 작성 실수
    - 발견 2 (시험 구성): 2·3회차 BLOCK 이유는 완료 조건 3 (REPORT.md 맨 위에 무엇을 만들었는지 없음). real:s3는 ②가 가짜라 이번 실행의 REPORT 섹션이 없음 → 이 시험 구성에서는 BLOCK이 맞는 판단. Codex가 한글 조건을 읽게 되면서 드러남
    - 발견 3 (③의 범위): 1회차가 "runs/output.txt 내용을 확인할 수 없다"를 BLOCK 이유로 씀. ③은 실행 전 코드 리뷰라 실행 결과 조건은 ④·⑤에서 확인할 일 → ③ 지시문에 범위를 적을 필요 (추정)
  - 지시문 수정 (2026-11-23, 사용자 승인, 역할·권한 그대로):
    1. 표준 입력 안내: "stdin 블록은 TASK.md(⑤는 이번 실행 REPORT 섹션 포함)의 정확한 글이다. 셸로 읽으면 한글이 깨질 수 있으니 그 글을 기준으로 하라. 이것은 문서 사본일 뿐이니 코드·runs·다른 파일은 직접 읽어라"
    2. ③ 범위: "이 리뷰는 코드 실행 전이다. 실행 결과 조건(runs 파일 내용, 종료 코드)은 ④·⑤에서 확인하니 여기서는 코드가 그 조건을 만족하도록 쓰였는지만 판단하고, 실행 결과가 아직 없다는 이유로 BLOCK하지 마라"
    - 대역 시험: 문법 오류 0, 새 문장이 Codex 명령 줄에 들어감, cmd 특수 문자(< > & | ^) 없음
    - 확인 계획: mode=`real:s2,s3` (②가 실제라 이번 실행 REPORT 섹션이 생김). Claude 1·Codex 1 이상
  - ✅ 확인 (run 20261123-092344, mode=real:s2,s3, Claude 1·Codex 1): ② 실제(hello.py 변경 없음, REPORT 섹션 추가) → ③ 1회차 PASS → 끝까지 정상
    - 수정 1 효과 (확인): ③이 셸로 파일을 직접 읽음 (`Get-ChildItem`, `work/hello.py`, `REPORT.md`)
    - 수정 2 효과 (추정): 실행 결과가 없다는 이유의 BLOCK이 사라짐. 1회 시험이라 근거는 약함
    - 리뷰 본문이 "none" 한 줄이라, 이번 판단에 한글 완료 조건을 썼는지는 리뷰로 확인 안 됨. 한글 조건을 읽는 것 자체는 run 092030에서 확인됨 (조건 3 인용)
  - 한글 깨짐 항목 결론: 로그는 해결(이전), Codex의 한글 기준 문서 읽기는 표준 입력 전달로 해결. 셸 출력 깨짐 자체는 남아 있음 (Codex 샌드박스 문제로 추정, v1 범위 밖)
- 결정 (2026-11-23, 사용자): 커밋·push 자동화는 v1이 아니라 고도화에서 한다. 범위는 둘 다
  1. 파이프라인 결과: ⑦ 판정을 n8n **승인 버튼 하나**로 바꾼다 (승인하면 병합·push 자동). 사람 승인 기록은 유지 (10절 원칙 유지). 확인할 것: n8n에서 git push가 노트북에 저장된 GitHub 로그인으로 되는지 (추정: 같은 Windows 계정이라 됨)
  2. 문서·스크립트 수정: 한 줄 실행 스크립트(예: `scripts/publish.ps1` — 변경 목록 표시 → 커밋 → push)로 간소화. Claude가 연결 통로에서 직접 커밋하지 않는 이유 (확인): 통로에서 파일 삭제가 막혀 git 잠금 파일 처리가 안 되고, 통로의 git은 줄바꿈 처리가 노트북과 달라 파일 전체가 바뀐 것처럼 커밋될 위험

## 19. v1 종료 (2026-11-23)
- 상태: **v1 종료**. 다음은 고도화 (대상 PoC·순서는 나중에 정함, 1절)
- 완료 조건 (6절):
  | 조건 | 결과 | 근거 |
  |---|---|---|
  | 1. [시작] 한 번으로 ②~⑥이 사람 손 없이 이어짐 | ✅ | real 전체 실행 PASS 3회 (224021, 080359, 084736) |
  | 2. 차단 → 재작업 → 재리뷰 | ✅ | fake block1·blockall (16·17절) + 실제 Codex로도 재시도 3회 후 멈춤 확인 (092030, 의도하지 않은 시험) |
  | 3. 실패 시 그 자리에서 멈춤 | ✅ | fake fail4, real 092030 (n8n 실패 표시 포함) |
  | 4. 사람이 읽을 결과 보고 하나 | ✅ | RESULT.md |
  | 5. 실행당 AI 호출 수 기록 | ✅ | run log·RESULT의 AI calls |
- v1에서 추가로 한 것: n8n 판정 구조 18→12노드 (17절), Git 로컬 커밋·브랜치 → ⑦ 병합 → GitHub 공개 저장소 push (18절, https://github.com/zoobihn-youn/ai-pipeline), stage.ps1 보완 4개, Codex 한글 기준 문서 표준 입력 전달 (18절)
- 고도화로 넘긴 것:
  1. ⑦ 승인 버튼(n8n) → 병합·push 자동, 문서·스크립트 수정 커밋을 한 줄 스크립트로 (18절)
  2. 포트폴리오용 README.md
  3. 개발 흐름과 운영(일배치) 흐름 분리 — 코드 변경 없을 때 ②·③ 생략 (18절 보류)
  4. Codex 셸 출력의 한글 깨짐 자체 (샌드박스 문제로 추정)
  5. 12절 v2 후보: 로컬 LLM(Ollama) 단계, MCP 서버, Skills·AGENTS.md
- 남은 사람 작업: 이전 18개 노드 n8n 워크플로 보관 또는 삭제

## 20. v2 시작: 템플릿화 (2026-11-23)
- 결정 (사용자):
  1. 이 흐름을 템플릿으로 만든다. 이유: 기획·개발·검수 역할을 나눈 구조를 PoC마다 새로 만들면 품질이 들쑥날쑥해짐. 사람마다 다른 기준으로 시작하면 문제가 생김
  2. 핵심은 **기준 문서** — 새 문서를 쓸 때 참조 문서부터 확인하듯, 새 PoC도 공용 기준을 먼저 따르고 시작한다 (fork는 예시였음)
  3. 첫 적용 대상: image-compare (C:\dev\image-compare)
- 방향 (Claude 제안, 세부는 합의 전): 공용 파이프라인(n8n·stage.ps1, ai-pipeline에 한 벌) + 공용 기준 문서·양식 + 프로젝트별 설정 파일. 파이프라인을 프로젝트마다 복사하지 않는 이유: 고칠 때 복사본마다 따로 고쳐야 해서 기준이 다시 갈라짐
- PoC 원칙: 진행 중인 PoC는 ai-pipeline v2 하나. image-compare는 적용 대상이고 image-compare PoC 자체를 다시 여는 것은 아님
- image-compare 현황 (2026-11-23 확인, 읽기만):
  - Git 없음. 160MB·파일 1,787개. `.env`(DB 비밀번호) 있음, `.gitignore`는 `.env`·`__pycache__/`만
  - 코드는 `plp/`·`api/`, 결과는 `data/`·`vision/`·`captures*/`·`screens/`·`runs/`, 보관용 `old/`(66MB)·`legacy/`
  - **위험 (확인)**: image-compare는 `runs/`를 자체 수집 결과 폴더로 씀 (`runs/fr/…`, 33MB). 지금 stage.ps1의 ④는 실행 전에 `runs/` 내용을 `.pipeline/runs-prev/`로 옮김 → 그대로 적용하면 image-compare 데이터를 옮겨 버림. 설정화 전에는 image-compare에서 real ④를 돌리면 안 됨
  - 실행 특성: 수집은 실제 사이트 접속(페이지 대기 12초)·화면 있는 브라우저, 비전은 로컬 Ollama → 3분 제한·한 줄 `RUN:`과 맞지 않음. 사이트 접속 없는 회귀 검사 명령 `python -m plp regress`가 있음
- 결정 (2026-11-23, 사용자): image-compare는 GitHub **비공개** 저장소로 올림. 첫 시험 TASK는 Guardrails "비전 설명 문장의 값이 실제 측정값과 맞는지 검사" + `python -m plp regress`로 확인 (사이트 접속·Ollama 없이). 기준 문서는 HTML 초안 없이 바로 파일로
- 진행 순서: ① 기준 문서 → ② 설정 파일화(stage.ps1이 pipeline.json을 읽게) → ③ image-compare 적용
- ✅ ① 기준 문서 작성 (2026-11-23): `standard/` — STANDARD.md v1.0 (역할·검수 독립성·문서·TASK 작성 규칙·판정·Git·사용량·기록), TASK.template.md(완료 조건에 확인 방법·확인 단계 열), PROJECT.template.md("기준 예외" 절), pipeline.template.json(안), gitignore.template, NEW-PROJECT-CHECKLIST.md. v1에서 확인된 규칙만 옮김, pipeline.json은 "안"으로 표시
- ✅ ② 설정 파일화 (2026-11-23, 백업 없음 — 직전 버전은 Git 커밋 a50ac1d에 있음):
  - stage.ps1이 `<PROJECT_ROOT>/pipeline.json`을 읽음: ② 쓰기 경로(허용 도구로 변환)·모델·턴 수, ⑥ 모델·턴 수, 단계별 시간 제한, ④ 실행 전에 옮길 폴더, 검수 지시문에 들어갈 코드·결과 위치. 파일이 없거나 잘못되면 S0에서 멈춤(결과 기록은 계속 돎). S0 기록에 읽은 설정을 남김
  - 경로 검사: 상대 경로만, `..`·절대 경로·따옴표·cmd 특수 문자 금지, write_paths에 REPORT.md 필수, move_before_run에 `.`·`.git`·`.pipeline` 금지
  - 이전 출력을 옮기는 곳이 `.pipeline/runs-prev/<runId>/` → `.pipeline/prev-output/<runId>/<폴더>/`로 바뀜 (여러 폴더 지원). 기존 runs-prev는 그대로 둠
  - ai-pipeline 자신의 `pipeline.json`: v1과 같은 값 (work/**·REPORT.md, haiku/10, runs 옮김, 180초)
  - STANDARD.md v1.1: 5절을 "안"에서 구현 내용(키·기본값·경로 규칙)으로 확정, 양식에 second_review 추가
  - 시험 (이 채팅 작업 공간, 대역 claude·codex·cmd, AI 0회): 문법 오류 0. ai-pipeline 설정으로 ② 허용 도구·모델·턴 수·③⑤⑥ 지시문의 경로가 이전과 같음, ④가 runs/를 옮김. image-compare식 설정(plp/**, sonnet/30, 옮김 없음, s4 900초)으로 runs/가 그대로 남음, ⑥ 모델 따로 적용, 단계별 시간 제한 적용. 잘못된 설정 7종 모두 S0/해당 단계에서 멈춤, 파일 없음도 멈춤
  - 노트북 확인 (예정): fake 4개 + `real:s4`(AI 0회, 옮기기 경로 확인)
  - ✅ 노트북 확인 (2026-11-23, AI 0회): fake 4개(100346·100404·100420·100434) 결과가 17절과 같음, S0 기록에 settings 줄 정상. `real:s4`(100746): runs/output.txt → `.pipeline/prev-output/20261123-100746/runs/output.txt`로 옮긴 뒤 새로 생성, s4.json에 moved_from·moved_files 기록, REPORT 줄 "moved old output files: 1 (folders: runs)" → **② 설정 파일화 완료**
- 결정 (2026-11-23, 사용자): 3단계(image-compare 적용)를 먼저 끝냄 → 그다음 채팅용 스킬 만들기 + task-observer 시험 (목적: 토큰 사용량 줄이기, 반복 작업 스킬화)
- ③ image-compare 적용 진행 (2026-11-23):
  - ✅ `.gitignore` (백업 `.gitignore.bak-20261123`): 코드·문서만 → 50개 파일, 약 566KB (계산, git status 확인 전). `.env` 제외 확인
  - ✅ image-compare PROJECT.md v0.25 (백업 `PROJECT.md.bak-20261123`): 맨 위 "기준: STANDARD.md v1.1", 13절 "ai-pipeline 적용"(Git 범위, 비공개, 기준 예외 2건: runs/는 누적 데이터라 옮기기 금지, 이전 TASK는 old/로)
  - 발견 (확인): 첫 시험 TASK로 정한 Guardrails ①("비전 설명 문장의 값이 실제 측정값과 맞는지")은 `plp/vision3.py`의 `guard_explain`으로 **이미 구현돼 있음** (실제값·기준값이 문장에 있는지, 입력에 없는 숫자·색 코드, 한국어 여부 검사, 실패 시 1번 재요청 후 대체). 3단계 설명 결과 28건(대체 0, 재요청 0). 다만 테스트 코드는 없고, B2 [수집] 경로(worker)에서는 설명을 만들지 않음 → PROJECT.md 12절의 "미완료" 뜻을 사용자에게 확인 필요
  - 결정 (2026-11-23, 사용자): 첫 시험 TASK는 **A안 — guard_explain 단위 테스트 추가** (12절 Guardrails ①의 뜻 = 테스트로 검증 가능하게 만들기). ②·⑥ 모델은 **Haiku**(사용량 절약), 최대 턴 20
  - ✅ image-compare TASK.md (STANDARD 양식): tests/test_guard_explain.py에 8가지 경우(정상·빈 답·영어·실제값 빠짐·기준값 빠짐·숫자 지어냄·색 코드 지어냄·색 코드+한글 조사), plp/ 코드 변경 금지, `RUN: python -m unittest discover -s tests -v && python -m plp regress`. 이전 TASK는 `old/TASK_B2단계_수집버튼_진행상황.md`로 옮김
  - ✅ image-compare pipeline.json: 쓰기 `tests/**`·`REPORT.md`, haiku/20(②·⑥), 옮김 없음, 기본 180초·④ 300초, 검수 코드 위치 `plp/`·`tests/`
  - 참고 (사용자 질문): 수집을 10장→2장으로 줄이면 B안(수집 경로 시험)의 실행 시간이 크게 줄어듦 (페이지 대기 12초·비전 1장 최대 120초가 장수에 비례). Claude 토큰과는 거의 무관 (수집·판정·비전은 노트북 코드와 로컬 Ollama). 20장은 딱지 종류가 골고루 들어가게 고른 것이라 2장은 판정 범위가 좁아짐. B안을 할 때 적용
  - ✅ image-compare 준비 (2026-11-23, 사람): python에 requests·Pillow 있음, `git status` 16개 항목(.env·data·captures·old 없음) → 첫 커밋 "image-compare baseline (ai-pipeline v2)", GitHub 비공개 https://github.com/zoobihn-youn/image-compare push (처음 원격 주소를 저장소 이름만 넣어 실패 → `git remote set-url`로 고침). n8n을 `start-n8n.ps1 -ProjectRoot C:\dev\image-compare`로 재시작
  - ✅ image-compare fake pass (run 20261123-103329, AI 0회): S0 기록에 python 3.12.10·git·head=ok·작성자·branch=main·변경 0개·settings(write=tests/**,REPORT.md, haiku/20, move=none, code=plp/, tests/, s4 300초) 정상, 끝까지 PASS. `.pipeline/`이 생겼고 Git 변경으로 잡히지 않음(.gitignore), `runs/fr/` 그대로
  - ✅ image-compare 첫 real (run 20261123-103437, 10:34:37~10:36:36 약 2분, Claude 2·Codex 2): S0 → ② (Haiku 10턴) → ③ PASS → ④ 8개 테스트 통과 + 회귀 검사 kr 20/0·it 7/13·es 10/10, 종료 코드 0 → ⑤ PASS → ⑥ RECOMMEND PASS → `run/20261123-103437`에 커밋 c7c692a (REPORT.md·RESULT.md·tests/test_guard_explain.py, plp/ 변경 없음)
    - 토큰 (②): cache_write 52,256 / cache_read 360,613 / output 7,724. (⑥): 37,118 / 257,711 / 6,711. v1 더미(② 36k/152k)의 약 2배 — 큰 코드를 읽은 영향 (추정)
    - ⑤가 git status로 plp/ 변경 없음을 확인함
    - ⑥ 지적 (확인): ① ④ 출력의 "회귀 검사: 통과"가 `?뚭? 寃?? ?듦낵`로 깨짐 — 파이썬이 UTF-8로 낸 출력을 stage.ps1이 CP949로 읽은 것으로 추정 (④는 utf8Out=false). 판정은 종료 코드라 영향 없음. ② 테스트 04~07은 assertIn이라 다른 오류가 함께 나와도 통과 (TASK의 "포함" 기대에는 맞음). ③ ⑤의 "회귀 출력이 기대값과 일치" 표현 정정 제안 → 2차 검수가 1차를 검증함
    - ⑥ 착오 (확인): "`.gitignore`에 `__pycache__/`만 있다"고 씀 — 실제 .gitignore는 결과물 폴더까지 포함. 백업 파일(.gitignore.bak-20261123)을 읽은 것으로 추정. 결론에는 영향 없음
    - 남은 일: ⑦ 판정(병합·push), ④ 출력 인코딩 보완 여부
  - ✅ ④ 출력 한글 깨짐 수정 (2026-11-23, 사용자 결정): ④는 출력을 바이트로 받아 **UTF-8로 먼저 읽고, UTF-8이 아니면 Windows ANSI 코드페이지(한국어 Windows는 CP949)로** 읽음. 어느 쪽인지 s4.json `output_encoding`에 기록. AI 도구·git 호출(UTF-8)은 그대로. 이유: ④ 명령은 프로젝트마다 다르고 프로그램마다 출력 인코딩이 다름 (파이썬 UTF-8, cmd 기본 명령 CP949)
    - 시험 (작업 공간, AI 0회): UTF-8 한글 → utf-8, CP949 한글 → codepage 949로 둘 다 정상, 영문·빈 출력 정상. 한글을 출력하는 ④ 실행에서 stdout·stderr 파일·REPORT 줄 모두 한글 정상. 문법 오류 0
    - 노트북 확인: image-compare ⑦ 병합 뒤 `real:s4` (AI 0회) — "회귀 검사: 통과"가 정상으로 남는지
  - ✅ 노트북 확인 (image-compare `real:s4`, run 20261123-110711, AI 0회): stdout 파일·REPORT 줄에 "회귀 검사: 통과" 정상, `output_encoding` = stdout utf-8. 그 전 실행(110604)은 설정 칸을 바꿔 넣어(scenario=`real:s4`, mode=`real`) 입력값 검사로 S0에서 멈춤 — 입력값 검사가 실제로 막은 첫 사례. mode=`real`이었으므로 scenario가 정상 값이었다면 전체 real(AI 4회)이 돌 뻔함
  - ✅ image-compare ⑦ 판정 (사람): 승인, main 병합·push (main = c7c692a)
- ✅ **③ image-compare 적용 완료 (2026-11-23)**: 기준 문서 → 설정 파일화 → 다른 프로젝트 적용까지 확인. 공용 파이프라인 한 벌로 ai-pipeline과 image-compare 두 프로젝트가 같은 기준으로 돎
  - 다음 (20절 결정): 채팅용 스킬 만들기 + task-observer 시험
