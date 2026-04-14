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

## Phase 2 — transcript 파싱 + 효율성 지표

**목표:** 모델별 비용 분리, 캐시 히트율, 낭비 패턴 감지.

- [ ] `hud/lib/parse-transcript.sh` 완성 — `~/.claude/projects/**/*.jsonl` 파싱
- [ ] 도구 사용 집계 (Edit×4 Read×12 Bash×3)
- [ ] 실행중인 서브에이전트 감지 (tool_use name=Agent 추적)
- [ ] 모델별 비용 분리 (assistant 레코드의 model + usage 필드)
- [ ] 캐시 히트율 계산 (cache_read / total_input)
- [ ] **낭비 감지 경고**:
  - 캐시 히트율 < 40% → 빨강 경고
  - 컨텍스트 5분간 +10%p↑ → 🔥 경고
  - opus에서 단순 Read 5회 연속 → haiku 권장
  - Read 결과 > 2000 tokens → Grep 추천
- [ ] 3줄째 동적 전환 (평상시 통계 / 경고 시 액션 가이드)

**구현 포인트:**
- transcript는 `tail -500` 으로 최근만 읽기 (성능)
- `awk`로 모델별 비용 집계 (가격표는 config.json)
- 5초 refreshInterval 대비 100ms 이내 완료

---

## Phase 3 — code-forge 강화 (L3)

**목표:** code-forge 사용자에게 전용 메트릭 제공.

- [ ] `bellows-log.sh` 확장 (별도 PR로 code-forge 본체에):
  - `model`, `session_id`, `duration_ms`, `success` 필드 추가
  - `agent_end` 이벤트 (SubagentStop 훅에서)
- [ ] `quality-gate.sh` 확장:
  - `quality.jsonl` 파일로 결과 로깅 (현재는 stderr만)
- [ ] `hud/lib/parse-forge.sh` 완성
- [ ] code-forge 감지 시 자동 L3 활성화
- [ ] 3줄째에 에이전트/스킬 통계 + 게이트 통과율 표시

---

## Phase 4 — 어댑터 패턴 (L4)

**목표:** 다른 하네스 플러그인 지원.

- [ ] `hud/adapters/` 디렉토리 자동 스캔
- [ ] `adapters/omc.sh` — oh-my-claudecode 지원
- [ ] `adapters/ecc.sh` — everything-claude-code 지원
- [ ] `adapters/harness.sh` — claude-code-harness 지원
- [ ] 어댑터 작성 가이드 (CONTRIBUTING.md)
- [ ] statusLine 충돌 감지 및 해결 UI (/setup 시)

---

## Phase 5 — Codex CLI + Standalone TUI

**목표:** Claude Code + Codex CLI 통합. 별도 TUI 대시보드.

### 5-1. Codex CLI 데이터 파싱

- [ ] `hud/lib/parse-codex.sh` — `~/.codex/` 세션 JSONL 파싱
- [ ] Codex의 `token_count` 이벤트 델타 계산 (누적합 방식)
- [ ] 모델 자동 감지 (`turn_context.model`)
- [ ] 비용 계산 (GPT-4.1, o3, o4-mini 가격표)

### 5-2. tmux 통합 (실시간 HUD)

Codex CLI는 statusLine이 없으므로, tmux 하단바로 통합 HUD 제공.

- [ ] `tmux/status-right.sh` — Claude Code + Codex 통합 상태
- [ ] 최근 활성 세션 자동 감지 (modification time 기준)
- [ ] tmux 설정 가이드 (.tmux.conf 예시)
- [ ] 비tmux 환경 대안 (starship, zsh prompt)

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

## Phase 6 — 고급 기능 (장기)

### 6-1. OTel 연동

- [ ] `CLAUDE_CODE_ENABLE_TELEMETRY=1` 활성화 가이드
- [ ] OTel exporter → Grafana/Datadog 대시보드 템플릿
- [ ] 조직 단위 집계 (Admin Analytics API)

### 6-2. 실시간 알림

- [ ] 컨텍스트 임계 초과 시 터미널 알림
- [ ] 시간당 비용 폭증 시 Slack 알림
- [ ] rate limit 임박 시 경고

### 6-3. 플러그인 마켓플레이스 등록

- [ ] Claude Code 플러그인 마켓플레이스 제출
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