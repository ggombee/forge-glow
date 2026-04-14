# forge-glow 재개 프롬프트

이 파일은 다른 머신/새 세션에서 forge-glow 개발을 이어갈 때 Claude/Codex에게 붙여넣을 프롬프트입니다.

---

## 복붙용 프롬프트

```
forge-glow 프로젝트를 이어서 개발한다.

이 프로젝트는 Claude Code + Codex CLI 사용자를 위한 실시간 효율성 HUD + 멀티모델 분석 대시보드다.
"대장장이가 불빛 색으로 철의 상태를 읽듯이, 개발자는 HUD 색으로 AI 세션의 상태를 읽는다"는 컨셉.

## 현재 상태

Phase 1 완료 (statusLine MVP):
- hud/statusline.sh: Claude Code statusLine에 붙는 3줄 HUD
- hud/lib/parse-stdin.sh: stdin JSON 파싱 (L1)
- hud/lib/parse-transcript.sh: transcript.jsonl 파싱 뼈대 (L2, 미완성)
- hud/lib/parse-forge.sh: code-forge usage.jsonl 파싱 (L3)
- hud/lib/render.sh: ANSI 색상, 프로그레스바, 이모지
- hud/config.json: 임계값 + 모델 가격표
- install.sh / uninstall.sh: ~/.claude/settings.json에 statusLine 자동 등록

## 아키텍처 (4계층 데이터)

- L1: statusLine stdin JSON (플러그인 무관, 모든 Claude Code 사용자)
- L2: transcript.jsonl 파싱 (플러그인 무관)
- L3: code-forge usage.jsonl (code-forge 설치 시)
- L4: adapters/ 디렉토리의 타 플러그인 어댑터 (OMC, ECC 등)

## 핵심 설계 원칙

1. 쉘 스크립트 기반 (의존성: jq, bc만)
2. statusLine 렌더링 100ms 이내
3. 대용량 JSONL은 tail -N으로 방어
4. 범용성 우선, 플러그인 강화는 선택
5. 컨텍스트 경고: 🧊(0~50%) → ⚠️(50~70%) → 🔥(70~80%) → 💀(80~83.5%) → ♻️(83.5%+)
6. Context Rot 연구 기반 임계값 (50%부터 중간 정보 정확도 30% 하락)

## 모델 가격표 (2026년 4월 기준, config.json에 있음)

| 모델 | Input | Output | Cache Read | Cache Write |
|------|-------|--------|------------|-------------|
| Opus 4.6 | $5 | $25 | $0.5 | $6.25 |
| Sonnet 4.6 | $3 | $15 | $0.3 | $3.75 |
| Haiku 4.5 | $1 | $5 | $0.1 | $1.25 |

## 다음 작업 (PLAN.md 참고)

Phase 2: transcript 파싱 완성 + 효율성 지표
- 모델별 비용 분리 (transcript의 assistant 레코드)
- 캐시 히트율 (cache_read / total_input)
- 낭비 패턴 감지 (캐시 미활용, 컨텍스트 급속 소모, opus로 단순 작업 등)

Phase 5: Codex CLI 통합 + Standalone TUI
- ~/.codex/ 세션 JSONL 파싱
- tmux status bar 통합
- forge-glow stats TUI 대시보드

## 프로젝트 구조

forge-glow/
├── .claude-plugin/plugin.json
├── hud/
│   ├── statusline.sh        # 메인
│   ├── lib/
│   │   ├── parse-stdin.sh   # L1
│   │   ├── parse-transcript.sh # L2 (미완성)
│   │   ├── parse-forge.sh   # L3
│   │   └── render.sh        # 색상/렌더링
│   ├── adapters/            # L4 (미작성)
│   └── config.json
├── install.sh
├── uninstall.sh
├── PLAN.md                  # 전체 로드맵
├── RESUME_PROMPT.md         # 이 파일
└── README.md

## 참고 문서 (필독)

- PLAN.md: 전체 로드맵 (Phase 1~6)
- README.md: 사용자용 설명
- docs/hud-design.md: 원본 설계안 (code-forge 레포에 있음, 참고만)

## 참고 외부 프로젝트

- claude-status-bar (github.com/kangraemin): 쉘 기반 statusLine 기본
- claude-hud (github.com/jarrodwatts): TS, transcript 파싱
- tokscale (github.com/junhoyeo): Rust TUI, 멀티 도구 통합
- ccusage (github.com/ryoppippi): JSONL 파싱

## 지금 해야 할 것

PLAN.md를 읽고 Phase 2부터 구현을 시작한다.
먼저 하기 전에 현재 파일 구조를 확인하고, Phase 2의 세부 태스크를 TodoList로 만든다.
```

---

## 사용법

1. 새 머신에서 forge-glow 레포 clone
2. Claude Code 또는 Codex CLI 실행
3. 위 프롬프트 복사 → 붙여넣기
4. "Phase 2 구현 시작" 명령

---

## 주요 결정 사항 (잊지 말 것)

### 왜 쉘 스크립트인가
- Claude Code statusLine은 외부 명령 실행 방식 — Node/Python 런타임 오버헤드 없이 jq만으로 충분
- 100ms 이내 응답 필수 (300ms 디바운싱)
- 의존성 0 전략

### 왜 별도 레포인가 (code-forge 내장 아님)
- L1+L2는 플러그인 무관하게 동작하도록 설계됨
- OMC, ECC 등 타 하네스 사용자도 쓸 수 있어야 함
- TUI 대시보드(Phase 5)까지 가면 code-forge와 성격이 완전히 다름

### 왜 tmux 통합인가 (Codex 지원)
- Codex CLI는 Claude Code의 statusLine 같은 기능이 없음
- tmux 하단바가 가장 자연스러운 통합 지점
- 비tmux 사용자는 `forge-glow stats` Standalone TUI로 대체

### 컨텍스트 경고 임계값 근거
- 50%: Stanford "Lost in the Middle" — 중간 정보 정확도 30% 하락 시작
- 70%: 품질 저하 가속 구간
- 80%: auto-compact(83.5%) 임박 — 복잡한 작업 중단
- 83.5%: Claude Code AUTOCOMPACT_BUFFER_PCT=16.5% 기본값

### 캐시 TTL 주의
- 2026년 3월부터 기본 5분 (이전 1시간)
- 5분 이내 /compact 해야 캐시 효율 유지
- cache_read는 input의 10% 과금 (90% 절감)