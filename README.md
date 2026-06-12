# forge-glow

> "대장장이는 불빛 색으로 철의 상태를 읽는다"

Claude Code 실시간 효율성 HUD. 컨텍스트 건강도, 비용, 캐시 효율, 토큰 낭비를 터미널 하단에 표시합니다.

```
🧠 Opus  📁 myproject/feature/branch  💰 $2.41 ($0.83/h)
🧊 23% [████░░░░░░░░░░░░░░░░]  📝 +156 -23  🔧 Edit×4 Read×12
📊 opus:$1.80 sonnet:$0.52 haiku:$0.09  cache:87%  ⏱ 5h:12% 7d:41%
```

## 설치

### ✅ 권장: Claude Code 플러그인 (한 줄, 자동 갱신)

```bash
# 마켓플레이스 등록 (최초 1회)
claude plugin marketplace add https://github.com/ggombee/forge-market.git

# 설치
claude plugin install forge-glow
```

다음 Claude Code 세션부터 statusLine이 **자동 등록**됩니다 (별도 setup 불필요). 매 세션 시작 시 마켓플레이스가 git pull로 **자동 갱신**.

### 개발자 / Codex 단독 사용자: git clone

플러그인 외 부가 기능(tmux 통합, Python 대시보드)은 어떤 설치 경로에서든 동일하게 작동합니다. 코드 수정·기여를 원하면:

```bash
git clone https://github.com/ggombee/forge-glow.git ~/work/forge-glow
# 본인 설정 후 push → 모든 플러그인 사용자 캐시가 자동 갱신
```

### Python 대시보드만 (선택)

```bash
pip install forge-glow-stats   # 또는 stats/에서 직접 PYTHONPATH=src python3 -m forge_glow_stats
forge-glow-stats               # rich 자동 갱신 대시보드
forge-glow-stats --once        # 1회 렌더
forge-glow-stats --json        # JSON 출력
forge-glow-stats --org         # Admin Analytics API (ANTHROPIC_ADMIN_API_KEY 필요)
forge-glow-stats --workflow    # 워크플로우 패널 강제 활성 (~/.forge-glow/workflow.json 필요)
```

### Workflow 패널 (Phase 7, 선택)

작업 컨텍스트(현재/다음 sub-task, 결정 누적, 빌드 히스토리, 미결정 Q)를 효율성 메트릭 옆에서 함께 표시합니다.

```bash
# config 작성 (예시 복사 후 수정)
mkdir -p ~/.forge-glow
cp $(python3 -c "import forge_glow_stats, pathlib; print(pathlib.Path(forge_glow_stats.__file__).parent / 'examples' / 'workflow.example.json')") ~/.forge-glow/workflow.json
$EDITOR ~/.forge-glow/workflow.json

forge-glow-stats           # config 존재 시 자동 활성
```

자세한 schema/preset 가이드는 [`docs/workflow-setup.md`](docs/workflow-setup.md).

### tmux 통합 (선택)

`~/.tmux.conf`에 추가 (플러그인 설치 후):
```tmux
set -g status-right "#($CLAUDE_PLUGIN_ROOT_FORGE_GLOW/tmux/status-right.sh)"
set -g status-interval 5
```
또는 절대 경로 직접 입력. 자세한 건 `docs/tmux-setup.md`.

### 요구사항

- Claude Code v2.1.80+
- `jq`
  - macOS: `brew install jq`
  - Windows: `choco install jq` 또는 `scoop install jq`
  - Linux: `apt install jq` / `dnf install jq`
- `bc`
  - macOS/Linux 기본 포함
  - Windows: Git Bash 환경에서도 동작 (없으면 시간당 비용만 미표시, 나머지 정상)

### Windows 사용자 메모

**필수 사전 설치**:
```powershell
choco install jq    # 또는 scoop install jq
```
jq 없으면 statusLine 모델/비용/컨텍스트 자리에 `(jq missing)` 표시.

**자동으로 처리되는 것**:
- CRLF → LF 변환 (session-init.sh가 첫 세션에서 자동)
- 매 세션 git pull로 새 버전 자동 반영

**호환성**:
- bash 3.2+ (Git Bash 기본 포함)
- jq 1.6+ (필수)
- bc (Git Bash 기본 포함, 없어도 시간당 비용만 미표시)

**증상별 빠른 진단**:
| 증상 | 원인 | 해결 |
|------|------|------|
| `🧠 (jq missing)` | jq 미설치 | `choco install jq` |
| `🧠 ?` + `🧊 0%` (모든 값 빈 채) | CRLF 안 풀림 또는 v0.6.0 미만 사용 중 | `claude plugin uninstall forge-glow && claude plugin install forge-glow` 1회 |
| 브랜치만 보이고 모델/비용 안 보임 | jq stdin 파싱 실패 (구버전 eval 패턴) | v0.7.0+ 자동 반영 또는 위 reinstall |
| 부모 디렉터리에서 작업 중인데 다른 레포의 브랜치가 표시됨 | 멀티 레포 워크스페이스 인식 | v0.8.0+ 자동 반영 (cwd 기준 git toplevel 자동 탐지) |

**한 줄 자동 진단** (이 한 줄만 실행하면 위 표 전부 자동 체크):

```bash
# Windows Git Bash / macOS / Linux 모두 동일
bash ~/.claude/plugins/cache/forge-market/forge-glow/*/tools/diagnose.sh
```

출력의 `✗`/`⚠` 메시지에 해결 명령이 포함됩니다. 모르겠으면 출력 그대로 복사해 GitHub Issue로.

### 제거

```bash
claude plugin uninstall forge-glow
# 다음 세션 시작 시 session-init.sh가 settings.json의 statusLine을 자동 정리
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
| gate:✅/❌/⏭ | 이번 턴 품질 게이트 결과 (`FORGE_GLOW_GATE_LAST=1` — §표시 토글) |
| 🎚 HIGH→xhigh | /start 복잡도→effort 권고 (`FORGE_GLOW_SHOW_EFFORT=1` — §표시 토글) |

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

forge-glow는 5단계 데이터 계층으로 동작합니다:

| 계층 | 소스 | 플러그인 의존 | 정확도 |
|------|------|------------|--------|
| **L1** | statusLine stdin JSON | 없음 (모든 사용자) | 실시간 |
| **L2** | transcript.jsonl 파싱 + 가격표 곱셈 | 없음 (모든 사용자) | 근사 |
| **L3** | code-forge `bin/forge status --json` + usage.jsonl | code-forge 설치 시 | — |
| **L4** | adapters/ | OMC, ECC 등 어댑터 추가 시 | — |
| **L5** | Claude Code OTel 이벤트 (`claude_code.api_request`의 `cost_usd`) | OTel collector 실행 시 | **정확값** (Anthropic 계산) |

L5가 활성이면 L2 근사값을 정확값으로 덮어씁니다. L5 없으면 L2/L3 fallback.
OTel 설정: [docs/otel-setup.md](docs/otel-setup.md)

### Codex CLI 병렬 감지

`~/.codex/sessions/` 활성 세션 자동 감지 → Codex model/cost/ctx/turns도 같은 statusLine에 표시.
tmux 하단바 통합: [docs/tmux-setup.md](docs/tmux-setup.md)

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

### 표시 토글 (환경변수)

Claude Code `settings.json`의 `env`에 넣으면 HUD에 바로 반영됩니다:

| 변수 | 기본 | 효과 |
|------|------|------|
| `FORGE_GLOW_COST=0` | `1` (표시) | 비용 표시 전체 off (1줄 💸 + 3줄 모델별 📊). 구독제(Max)에선 API 환산 참고치일 뿐이라 끄고 ⏱ rate limit을 실질 게이지로 쓰는 용도. 종량제는 기본값 유지 권장 |
| `FORGE_GLOW_GATE_LAST=1` | `0` | 3줄에 "이번 턴 품질 게이트" 표시 — `gate:✅` / `gate:❌(blocks)` / `gate:⏭`. code-forge `route.json`의 `last_gate` 소비 |
| `FORGE_GLOW_VERSION_TAG=1` | `0` | 1줄 모델명에 정확한 model id 병기 — 예: `🧠 Fable 5 (claude-fable-5[1m])`. 서브에이전트 실행 표시 중엔 오독 방지를 위해 생략 |
| `FORGE_GLOW_SHOW_EFFORT=1` | `0` | 3줄에 /start 복잡도→effort 권고 표시 — 예: `🎚 HIGH→xhigh`. code-forge `route.json`의 `complexity`/`effort_level` 소비 (권고 전용 — 적용은 사용자가 /effort로) |

```json
{ "env": { "FORGE_GLOW_COST": "0", "FORGE_GLOW_GATE_LAST": "1" } }
```

게이트/버전/effort 토큰은 3줄이 경고로 교체돼도 보존됩니다. code-forge 미설치 환경에선 해당 토큰이 조용히 비표시 — 켜두어도 무해합니다.

## 구조

```
forge-glow/
├── .claude-plugin/plugin.json
├── hud/
│   ├── statusline.sh           # 메인 진입점
│   ├── lib/
│   │   ├── parse-stdin.sh      # L1: stdin JSON 파싱
│   │   ├── parse-transcript.sh # L2: transcript 파싱
│   │   ├── parse-forge.sh      # L3: code-forge (bin/forge surface 경유)
│   │   ├── parse-otel.sh       # L5: OTel 이벤트 (opt-in, 가장 정확)
│   │   ├── parse-codex.sh      # Codex CLI 세션 파싱
│   │   └── render.sh           # 색상, 프로그레스바, 이모지
│   ├── adapters/               # L4: 타 플러그인 어댑터
│   │   └── omc.sh              # oh-my-claudecode (레퍼런스)
│   └── config.json             # 임계값, 표시 설정
├── tmux/
│   └── status-right.sh         # tmux 하단바 통합 (Claude + Codex)
├── docs/
│   ├── otel-setup.md           # L5 OTel collector 설정
│   └── tmux-setup.md           # tmux 통합 가이드
├── install.sh                  # statusLine 등록 (교체/래핑/취소 3택)
├── uninstall.sh
├── CONTRIBUTING.md             # 어댑터 작성 가이드
└── README.md
```

## 자동 업데이트

`tools/self-update.sh`가 스케줄러에서 1시간마다 실행되어 `git pull --ff-only`합니다.
**Claude Code 플러그인화 없이** 멀티모델 철학을 유지하면서 자동 갱신되는 구조.

| 안전 가드 | 동작 |
|-----------|------|
| clean tree | `git diff`가 더러우면 스킵 (사용자 작업 보호) |
| upstream tracking | `@{u}` 없거나 detached HEAD면 스킵 |
| fast-forward only | 로컬에 커밋 있으면 스킵 (강제 rebase 없음) |
| mkdir 락 | 동시 실행 방지 |
| network failure | 조용히 스킵 (다음 주기 재시도) |

### 커스터마이즈

```bash
export FORGE_GLOW_UPDATE_INTERVAL=7200   # 2시간 (기본 3600초)
export FORGE_GLOW_DIR=/custom/path       # 레포 경로 변경
export FORGE_GLOW_STATE_DIR=~/.my-state  # 상태 파일 경로
```

### 수동 실행

```bash
bash ~/Desktop/workspace/forge-glow/tools/self-update.sh
cat ~/.forge-glow/update.log   # 갱신 이력
```

### 해제

```bash
bash ~/Desktop/workspace/forge-glow/uninstall.sh
```

---

## 로드맵

- [x] **Phase 1** — statusLine HUD MVP (L1)
- [x] **Phase 2** — transcript 파싱 + 모델별 비용 + 캐시 히트율 + 낭비 감지 (L2)
- [x] **Phase 3** — code-forge 강화 (L3, bin/forge surface 경유)
- [x] **Phase 4** — 어댑터 프레임워크 + 레퍼런스 1개 (OMC) + install.sh 래핑 모드
- [x] **Phase 5-1/5-2** — Codex CLI 파싱 + tmux 통합
- [x] **Phase 5-3** — Python rich 대시보드 (`forge-glow-stats`)
- ~~Standalone TUI / Node 렌더러 재작성~~ — 취소 (2026-06, 단일 플랫폼 사용자에게 과한 장식 — 2nd platform 사용자 실존 시 부활)
- [x] **Phase 6-1** — OTel L5 레이어 + Grafana 템플릿 + Admin Analytics API
- [x] **Phase 6-2** — 실시간 알림 (컨텍스트/비용/rate limit) + Slack webhook opt-in + update-available HUD
- [x] **Phase 6-3** — Homebrew formula + PyPI 패키지 + GitHub Release 자동화 + `tools/metrics-report.sh`

## 토큰 절약 팁

forge-glow가 보여주는 지표를 활용한 절약 방법:

- **캐시 히트율 80%+ 유지** — cache_read는 input 대비 10% 과금
- **50% 넘으면 주의** — Context Rot 시작, 중간 정보 정확도 하락
- **단순 작업은 haiku 서브에이전트** — Opus 대비 1/5 비용
- **Read보다 Grep** — 불필요한 컨텍스트 적재 방지
- **5분 이내 /compact** — 캐시 TTL(5분) 만료 전 실행

## Integration

forge-glow는 단독으로도 동작하지만, 자매 도구들과 결합 시 더 풍부한 정보를 제공합니다.

| 자매 도구 | 상태 | 접점 | 효과 |
|---|---|---|---|
| [code-forge](https://github.com/ggombee/code-forge) | 🟢 wired | `bin/forge status --json` (L3 surface) + `.claude/state/quality.jsonl` | 에이전트/스킬 사용, 품질 게이트, REFLECT flag, effort 권고를 HUD 3줄차에 자동 표시 |
| flow-toolkit | 📐 designed (휴면) | `flow run report` 결과 → `.policy/runs/<cycle>/result.json` | 사이클 통과율·영향 TC 결과를 워크플로우 패널에서 확인 (flow CLI 활성 시) |
| forge-hearth | 📐 designed (휴면) | 동일 `sources.json` v2 schema 공유 (`~/.forge-glow/workflow.json`) | `forge-glow-stats --workflow` 패널에서 다중 프로젝트 progress를 같은 위치에서 |

🟢 = 오늘 실제 연결되어 동작 / 📐 = 계약·코드는 준비, 해당 도구가 휴면이라 데이터 생산 0 (연결 자체는 graceful — 없으면 조용히 비표시)

전체 데이터 계약은 본인 PC `code-forge/docs/contracts/INTEGRATION.md` 참고.

## License

MIT