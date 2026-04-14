# forge-glow

> "대장장이는 불빛 색으로 철의 상태를 읽는다"

Claude Code 실시간 효율성 HUD. 컨텍스트 건강도, 비용, 캐시 효율, 토큰 낭비를 터미널 하단에 표시합니다.

```
🧠 Opus  📁 ad-center/feature/ggombee  💰 $2.41 ($0.83/h)
🧊 23% [████░░░░░░░░░░░░░░░░]  📝 +156 -23  🔧 Edit×4 Read×12
📊 opus:$1.80 sonnet:$0.52 haiku:$0.09  cache:87%  ⏱ 5h:12% 7d:41%
```

## 설치

```bash
git clone https://github.com/ggombee/forge-glow.git ~/Desktop/forge-glow
bash ~/Desktop/forge-glow/install.sh
```

Claude Code를 재시작하면 HUD가 표시됩니다.

### 요구사항

- Claude Code v2.1.80+
- `jq` (`brew install jq`)
- `bc` (macOS 기본 포함)

### 제거

```bash
bash ~/Desktop/forge-glow/uninstall.sh
```

## HUD 구성

### 1줄: 세션 정보

```
🧠 Opus  📁 프로젝트/브랜치  💰 비용 (시간당)
```

| 항목 | 설명 |
|------|------|
| 🧠 모델명 | 현재 세션 모델. 서브에이전트 실행 시 `→ 🔍 scout(haiku) 실행중` 표시 |
| 📁 프로젝트/브랜치 | 현재 작업 디렉토리 + Git 브랜치 |
| 💰/💸/🚨 비용 | 세션 누적 비용 + 시간당 비용. $2/h 이상 💸, $5/h 이상 🚨 |

### 2줄: 컨텍스트 + 활동

```
🧊 23% [████░░░░░░░░░░░░░░░░]  📝 +156 -23  🔧 Edit×4 Read×12
```

| 항목 | 설명 |
|------|------|
| 컨텍스트 바 | 20칸 프로그레스 바. 색상으로 건강도 표시 |
| 📝 코드 변경 | 추가/삭제된 라인 수 |
| 🔧 도구 활동 | 세션 내 도구 사용 집계 (transcript 파싱) |

### 3줄: 효율성 메트릭 (선택)

```
📊 opus:$1.80 sonnet:$0.52  cache:87%  ⏱ 5h:12% 7d:41%
```

| 항목 | 설명 |
|------|------|
| 📊 모델별 비용 | transcript에서 모델별 토큰 비용 분리 집계 |
| cache:N% | 캐시 히트율. 70%+ 초록, 40~70% 노랑, 40% 미만 빨강 |
| ⏱ rate limit | 5시간/7일 사용률. 60%+ ⚠️, 80%+ 🔴 |
| 🔨 에이전트/스킬 | code-forge 설치 시 에이전트/스킬 사용 통계 자동 표시 |

## 컨텍스트 경고 시스템

불빛 색이 변하듯, 컨텍스트 사용률에 따라 이모지와 바 색상이 변합니다:

| 사용률 | 상태 | 의미 |
|--------|------|------|
| 🧊 0~50% | 안전 (초록) | 성능 저하 없음 |
| ⚠️ 50~70% | 주의 (노랑) | Context Rot 시작 — 중간 정보 정확도 30%+ 하락 |
| 🔥 70~80% | 위험 (주황) | 품질 저하 가속. `/clear` 또는 `/compact` 권장 |
| 💀 80~83.5% | 임계 (빨강) | auto-compact 임박. 복잡한 작업 중단 |
| ♻️ 83.5%+ | 압축중 | auto-compact 자동 트리거 |

## 데이터 계층

forge-glow는 4단계 데이터 계층으로 동작합니다:

| 계층 | 소스 | 플러그인 의존 |
|------|------|------------|
| **L1** | statusLine stdin JSON | 없음 (모든 사용자) |
| **L2** | transcript.jsonl 파싱 | 없음 (모든 사용자) |
| **L3** | code-forge usage.jsonl | code-forge 설치 시 |
| **L4** | adapters/ | OMC, ECC 등 어댑터 추가 시 |

어떤 플러그인을 쓰든 L1+L2로 핵심 HUD가 동작합니다.

## 설정

`hud/config.json`에서 임계값과 표시 요소를 커스텀할 수 있습니다:

```json
{
  "thresholds": {
    "context": { "caution": 50, "danger": 70, "critical": 80 },
    "cost_per_hour": { "caution": 2.0, "danger": 5.0 },
    "rate_limit": { "caution": 60, "danger": 80 }
  }
}
```

## 구조

```
forge-glow/
├── .claude-plugin/plugin.json
├── hud/
│   ├── statusline.sh          # 메인 진입점
│   ├── lib/
│   │   ├── parse-stdin.sh     # L1: stdin JSON 파싱
│   │   ├── parse-transcript.sh # L2: transcript 파싱
│   │   ├── parse-forge.sh     # L3: code-forge 데이터
│   │   └── render.sh          # 색상, 프로그레스바, 이모지
│   ├── adapters/              # L4: 타 플러그인 어댑터
│   └── config.json            # 임계값, 표시 설정
├── install.sh
├── uninstall.sh
└── README.md
```

## 로드맵

- [x] Phase 1 — statusLine HUD MVP (L1)
- [ ] Phase 2 — transcript 파싱 + 모델별 비용 + 캐시 히트율 (L2)
- [ ] Phase 3 — code-forge 강화 (L3)
- [ ] Phase 4 — 어댑터 패턴 (L4)
- [ ] Phase 5 — 별도 TUI 대시보드 (멀티 도구 통합)

## 토큰 절약 팁

forge-glow가 보여주는 지표를 활용한 절약 방법:

- **캐시 히트율 80%+ 유지** — cache_read는 input 대비 10% 과금
- **50% 넘으면 주의** — Context Rot 시작, 중간 정보 정확도 하락
- **단순 작업은 haiku 서브에이전트** — Opus 대비 1/5 비용
- **Read보다 Grep** — 불필요한 컨텍스트 적재 방지
- **5분 이내 /compact** — 캐시 TTL(5분) 만료 전 실행

## License

MIT