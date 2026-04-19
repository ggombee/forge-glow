# forge-glow — 로드맵

## 비전

Claude Code + Codex CLI 사용자를 위한 **실시간 효율성 HUD + 멀티모델 분석 대시보드**.

"대장장이가 불빛 색으로 철의 상태를 읽듯이, 개발자는 HUD 색으로 AI 세션의 상태를 읽는다."

---

## Phase 1 — statusLine MVP ✅ (완료)

Claude Code statusLine API에 붙는 기본 HUD.

- [x] `hud/statusline.sh` — stdin JSON 파싱 + 렌더링
- [x] `hud/lib/parse-stdin.sh` — L1 데이터 계층
- [x] `hud/lib/render.sh` — 색상, 프로그레스바, 이모지
- [x] `hud/config.json` — 임계값 설정
- [x] `install.sh` / `uninstall.sh` — settings.json 자동 등록

**표시 내용:**
- 모델, 프로젝트/브랜치, 세션 비용 (시간당)
- 컨텍스트 사용률 프로그레스바 (🧊→⚠️→🔥→💀)
- 코드 변경량 (+156 -23)
- Rate limit (5h/7d)

---

## Phase 2 — transcript 파싱 + 효율성 지표 ✅ (완료)

**목표:** 모델별 비용 분리, 캐시 히트율, 낭비 패턴 감지.

- [x] `hud/lib/parse-transcript.sh` 완성
- [x] 도구 사용 집계 (Edit×4 Read×12 Bash×3)
- [x] 실행중인 서브에이전트 감지 (tool_use name=Agent 추적)
- [x] 모델별 비용 분리 (assistant 레코드의 model + usage 필드)
- [x] 캐시 히트율 계산 (cache_read / total_input)
- [x] **낭비 감지 경고**:
  - opus에서 단순 Read 5회 연속 → haiku 권장
  - Read 결과 > 2000 tokens → Grep 추천
  - cache miss 3턴 연속 → /compact 타이밍 조정
- [x] 3줄째 동적 전환 (평상시 통계 / 경고 시 액션 가이드)

---

## Phase 3 — code-forge 강화 (L3) ✅ (완료, v4.2.0+)

**목표:** code-forge 사용자에게 전용 메트릭 제공.

- [x] `bellows-log.sh` v2 필드 (`model`, `session_id`, `duration_ms`, `success`) — code-forge 본체 반영
- [x] `bellows-log.sh` v2.5 — `agent_end` 이벤트 (SubagentStop 훅에서 transcript ts 기반 duration 계산)
- [x] `quality-gate.sh` → `.claude/state/quality.jsonl` 로깅 — code-forge 본체 반영
- [x] `hud/lib/parse-forge.sh` — `bin/forge status --json` surface 경유 (계약 준수)
- [x] code-forge 감지 시 자동 L3 활성화
- [x] 3줄째에 에이전트/스킬 통계 + 게이트 통과율 표시

---

## Phase 4 — 어댑터 패턴 (L4) ⚠️ (프레임워크 + 레퍼런스 1개)

**목표:** 다른 하네스 플러그인 지원.

- [x] `hud/adapters/` 디렉토리 자동 스캔 (statusline.sh)
- [x] `adapters/omc.sh` — oh-my-claudecode 지원 (레퍼런스 어댑터)
- [ ] `adapters/ecc.sh` — everything-claude-code 지원
- [ ] `adapters/harness.sh` — claude-code-harness 지원
- [x] 어댑터 작성 가이드 (`CONTRIBUTING.md`)
- [x] statusLine 충돌 해결 UI — `install.sh`의 교체/래핑/취소 3택

---

## Phase 5 — Codex CLI + Standalone TUI

**목표:** Claude Code + Codex CLI 통합. 별도 TUI 대시보드.

### 5-1. Codex CLI 데이터 파싱 ✅ (완료)

- [x] `hud/lib/parse-codex.sh` — `~/.codex/sessions/**/*.jsonl` 파싱
- [x] `turn.completed.usage.*` (input/cached/output_tokens) 사용 — 누적 델타 아님 (2026 Q1+ 표준)
- [x] 모델 자동 감지 (`turn_context.model`)
- [x] 비용 계산 (gpt-5/o3/mini/gpt-4.1 가격표 내장)
- [x] Windows `token_count` 버그 fallback

### 5-2. tmux 통합 ✅ (완료)

- [x] `tmux/status-right.sh` — Claude + Codex 통합 상태
- [x] 최근 활성 세션 자동 감지 (mtime 5분)
- [x] tmux 설정 가이드 (`docs/tmux-setup.md`)
- [x] 비tmux 환경 대안 (starship, zsh RPROMPT)

### 5-3. Standalone TUI 대시보드

`forge-glow stats` 명령으로 멀티 도구 통합 분석 뷰.

```
┌─ Token Dashboard ────────────────────────────────────┐
│ Today: $8.42  │  Week: $41.20  │  Month: $156.80    │
│                                                       │
│ ┌─ By Model ──────────────────────────────────────┐ │
│ │ claude-opus-4-6    $3.20  ████████░░  38%       │ │
│ │ claude-sonnet-4-6  $4.10  ██████████  49%       │ │
│ │ claude-haiku-4-5   $0.52  █░░░░░░░░░  6%        │ │
│ │ gpt-4.1 (codex)    $0.60  █░░░░░░░░░  7%        │ │
│ └─────────────────────────────────────────────────┘ │
│                                                       │
│ ┌─ Efficiency ────────────────────────────────────┐ │
│ │ Cache Hit Rate:  87% ████████░░  (목표: >80%)   │ │
│ │ Avg $/task:      $1.20           (업계: $6)     │ │
│ │ Context Resets:  3회/일          (권장: <5)     │ │
│ │ Haiku Delegation: 42%           (권장: >40%)   │ │
│ └─────────────────────────────────────────────────┘ │
│                                                       │
│ ┌─ Savings Tips ──────────────────────────────────┐ │
│ │ 💡 어제 opus로 단순 Read 47회 — haiku면 $2.1 절약│ │
│ │ 💡 cache miss 3회 연속 — /compact 타이밍 조정   │ │
│ └─────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────┘
```

**구현 선택지:**
- **Node.js + ink** (추천) — React 패턴, 빠른 개발
- **Rust + ratatui** (tokscale처럼) — 고성능, 무거움
- **Python + textual** — 빠른 프로토타이핑

**기능:**
- [ ] 일/주/월 비용 추이
- [ ] 모델별 사용 패턴 (히트맵)
- [ ] 세션별 효율성 점수
- [ ] 절약 팁 자동 생성 (rule-based)
- [ ] JSON 내보내기 (`--json`)
- [ ] 리더보드 (선택적, privacy-first)

---

## Phase 6 — OTel / 관찰성 (L5 신설, 2026-04 리서치 반영)

### 6-1. OTel 연동 ✅ (기본 완료, v0.2.0)

- [x] `parse-otel.sh` L5 레이어 — `claude_code.api_request`/`tool_result` 이벤트 소비
- [x] L5 활성 시 L2 근사값을 정확값으로 덮어쓰기
- [x] `docs/otel-setup.md` — Collector file exporter 가이드
- [x] `CLAUDE_CODE_ENABLE_TELEMETRY=1` + `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1` 활성화 가이드
- [ ] Grafana/Datadog 대시보드 템플릿 (미구현, 후속)
- [ ] Admin Analytics API 연동 (`/v1/organizations/usage_report/claude_code`) — TUI Phase에서 구현

### 6-2. 실시간 알림 (미착수)

- [ ] 컨텍스트 임계 초과 시 터미널 알림
- [ ] 시간당 비용 폭증 시 Slack 알림
- [ ] rate limit 임박 시 경고

### 6-3. 배포 (미착수)

- [ ] Claude Code 플러그인 마켓플레이스 제출 (공식 프로세스 현재 Anthropic 내부 관리)
- [ ] npm 패키지 배포 (`npx forge-glow`)
- [ ] Homebrew formula

---

## 기술 스택 결정 사항

| 영역 | 선택 | 이유 |
|------|------|------|
| 쉘 HUD | Bash + jq + bc | 의존성 최소화, Claude Code statusLine 표준 |
| TUI 앱 | 미정 (Phase 5) | Node.js(ink) vs Rust(ratatui) 비교 필요 |
| 파싱 | `tail -N` + `jq` | 대용량 transcript도 안전 |
| 색상 | ANSI-C quoting (`$'\033[32m'`) | POSIX 호환 |
| 설정 | JSON | 모든 도구에서 읽기 쉬움 |

---

## 성능 예산

| 작업 | 목표 시간 |
|------|----------|
| statusLine 전체 렌더링 | < 100ms |
| transcript 파싱 (tail -500) | < 30ms |
| 모델별 비용 집계 | < 20ms |
| TUI 초기 로딩 | < 500ms |

---

## 참고 프로젝트

| 프로젝트 | URL | 참고 포인트 |
|---------|-----|-----------|
| claude-status-bar | https://github.com/kangraemin/claude-status-bar | 쉘 기반 statusLine 기본 |
| claude-hud | https://github.com/jarrodwatts/claude-hud | TS, transcript 파싱, 프리셋 |
| tokscale | https://github.com/junhoyeo/tokscale | Rust TUI, 멀티 도구 통합 |
| ccusage | https://github.com/ryoppippi/ccusage | JSONL 파싱, 일별 집계 |

---

## 라이선스 / 배포

- MIT
- 개인 GitHub 레포로 공개
- 마켓플레이스 등록은 Phase 5 이후 검토