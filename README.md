# forge-glow

> "대장장이는 불빛 색으로 철의 상태를 읽는다"

Claude Code의 **현재 세션만** 표시하는 실시간 status line입니다. Codex **CLI TUI**는
forge-glow가 전역 로그를 추측하지 않고 Codex native status line을 사용합니다.

```text
🧠 Opus  📁 myproject/feature  💰 ~$2.41 (~$0.83/h avg)
🧊 23% [████░░░░░░░░░░░░░░░░]  📝 +156 -23  🔧 Edit×4 Read×12
📊 ~opus:$1.80 sonnet:$0.52  cache:87%  ⏱ 5h:12% 7d:41%
```

## 세션 격리 원칙

- Claude: statusLine stdin의 `session_id`, `transcript_path`, context만 사용
- Claude OTel: 현재 `session.id`와 같은 이벤트만 사용
- Codex: 현재 TUI 세션을 아는 native `tui.status_line` 사용
- 5시간/주간 한도는 세션별이 아니라 각 계정의 공유 값

Claude HUD에 `~/.codex/sessions` 값을 합치지 않으므로 동시에 여러
Claude/Codex 세션을 열어도 모델과 컨텍스트가 섞이지 않습니다.

## 설치

### Claude Code 플러그인

```bash
claude plugin marketplace add ggombee/forge-glow
claude plugin install forge-glow@forge-glow
```

다음 Claude 세션에서 status line을 등록합니다. 이미 다른 status line이 있으면
자동으로 합치거나 덮어쓰지 않고 안내만 표시합니다. 명시적으로
교체하려면 클론한 디렉터리에서 `bash install.sh`를 실행하세요. 두 HUD를
한 status line에 합치는 모드는 제공하지 않습니다.

서드파티 마켓플레이스의 자동 업데이트는 기본으로 꺼져 있습니다. Claude Code의
`/plugin` → `Marketplaces` → `forge-glow`에서 auto-update를 켜거나 사용자
`settings.json`의 해당 항목에 `"autoUpdate": true`를 추가하세요. 새 버전이
받아진 실행 중 세션은 `/reload-plugins`로 다시 로드합니다.

### Codex CLI

```bash
codex plugin marketplace add ggombee/forge-glow --ref main
codex plugin add forge-glow@forge-glow
```

새 Codex 세션에서 `$forge-glow-statusline`을 실행하거나 `/statusline`에서 다음
항목을 선택합니다.

> 이 설정은 터미널에서 실행한 Codex CLI의 TUI footer에만 표시됩니다.
> Codex 데스크톱 앱, IDE 확장, API/Orca 같은 비-TTY 호스트에는
> `tui.status_line`을 삽입할 footer가 없으므로 forge-glow HUD가 나타나지 않습니다.

- `model-with-reasoning`
- `context-remaining`
- `five-hour-limit`
- `weekly-limit`
- `current-dir`
- `git-branch`
- `fast-mode`

이 순서로 모델과 현재 세션 컨텍스트 바로 뒤에 5시간·7일 한도를 붙입니다.
Codex가 계정에서 특정 한도를 받지 못하면 그 항목은 자동으로 생략합니다. 기간
라벨은 Codex native footer가 정하므로 현재 버전에서 주간 한도가 `weekly`로
표시될 수 있으며, `tui.status_line`에는 이를 `7d`로 바꾸는 alias 설정이 없습니다.

직접 설정하는 방법과 세션/계정 범위는 [Codex 세션별 HUD 설정](docs/codex-setup.md)을
참조하세요.

### 업데이트

Claude는 auto-update를 켜 두면 시작할 때 새 버전을 확인합니다. 즉시 확인하려면:

```bash
claude plugin marketplace update forge-glow
claude plugin update forge-glow@forge-glow
```

Codex는 현재 마켓플레이스 자동 갱신을 제공하지 않으므로 명시적으로 snapshot을
갱신하고 플러그인을 다시 설치한 뒤 새 세션을 엽니다.

```bash
codex plugin marketplace upgrade forge-glow
codex plugin add forge-glow@forge-glow
```

클론 안에서는 두 제품을 한 번에 설치·업데이트·진단할 수 있습니다.

```bash
bash tools/plugin-manager.sh install all
bash tools/plugin-manager.sh update all
bash tools/plugin-manager.sh check all
```

배포 방식과 버전 반영 시점은 [플러그인 배포와 업데이트](docs/plugin-distribution.md)를
참조하세요.

### 개발용 클론

```bash
git clone https://github.com/ggombee/forge-glow.git ~/work/forge-glow
cd ~/work/forge-glow
bash install.sh
```

개발용 Git clone에서만 clean tree를 ff-only로 갱신하는 1시간 스케줄러를
등록합니다. 원치 않으면 설치할 때 `FORGE_GLOW_SKIP_AUTOUPDATE=1 bash install.sh`를
사용하세요. 플러그인과 Homebrew 설치본은 각 패키지 관리자가 업데이트합니다.

마켓플레이스의 `forge-glow`와 개발용 클론을 동시에 활성화하면 다음 Claude 시작 때
캐시 hook이 status line 경로를 되돌릴 수 있습니다. installer 경고가 나오면 개발 중에는
해당 `forge-glow@...` 플러그인만 비활성화하고, 배포본 업데이트 뒤 다시 활성화하세요.

## HUD 구성

### 1줄: 세션 신원과 비용

```text
🧠 Opus  📁 project/branch  💰 ~$2.41 (~$0.83/h avg)
```

- 모델, 현재 작업 레포/브랜치
- Claude가 stdin으로 준 세션 누적 비용 추정값
- 세션 시작 후 wall-clock 평균 추정값이 $2/h, $5/h를 넘으면 💸, 🚨로 변경

Claude Pro/Max 구독자에게 비용은 실제 청구액이 아니므로 `FORGE_GLOW_COST=0`으로
숨기고 rate limit을 보는 편이 낫습니다.

### 2줄: 컨텍스트와 최근 활동

```text
🧊 23% [████░░░░░░░░░░░░░░░░]  📝 +156 -23  🔧 Edit×4 Read×12
```

- 현재 세션의 context 사용률
- 세션 코드 추가/삭제량
- 현재 transcript 최근 500개 레코드의 nested `tool_use` 집계
- Claude Code가 준 `COLUMNS`가 100 미만이면 바를 10칸, 도구를 상위 3개로 축소

컨텍스트 표시는 0~49% 🧊, 50~69% ⚠️, 70~79% 🔥, 80% 이상 💀로
올라갑니다. 이 임계값은 경고 표시용이며 모델 품질을 보장하는 절대 기준은 아닙니다.

### 3줄: 효율 추정

```text
📊 ~opus:$1.80 sonnet:$0.52  cache:87%  ⏱ 5h:12% 7d:41%
```

- `~`가 붙은 모델별 비용은 청구 확정값이 아닙니다.
- transcript는 `message.id`로 반복 레코드를 중복 제거한 뒤 현재 가격표로 근사합니다.
- OTel을 켜면 현재 `session.id`의 `cost_usd` 이벤트로 모델별 근사값을 보강합니다.
- rate limit은 Claude가 statusLine stdin으로 준 값입니다.

## 데이터 소스

| 소스 | 용도 | 범위 |
|---|---|---|
| Claude statusLine stdin | 모델, context, 총비용, rate limit, 코드 변경 | 현재 세션 |
| `transcript_path` | 도구, 모델별 토큰/비용 근사, 캐시 | 현재 세션 |
| OTel logs file | 모델별 `cost_usd`, 캐시 | 현재 `session.id` |

OTel은 기본으로 꺼져 있습니다. 표준 OTLP/JSON `resourceLogs/scopeLogs/logRecords`
파일 설정은 [OTel 설정](docs/otel-setup.md)을 보세요.

## 설정

Claude `settings.json` 예시:

```json
{
  "env": {
    "FORGE_GLOW_COST": "0"
  }
}
```

| 변수 | 기본 | 효과 |
|---|---:|---|
| `FORGE_GLOW_COST` | `1` | `0`이면 1/3줄 비용 표시 숨김 |
| `FORGE_GLOW_OTEL_LOG` | `~/.forge-glow/otel.log` | OTel logs file 경로 |
| `FORGE_GLOW_SLACK_WEBHOOK` | 빈 값 | context 임계 경고를 Slack으로 전송 |
| `FORGE_GLOW_ALERT_COOLDOWN` | `600` | 같은 Claude 세션의 Slack 재전송 최소 간격(초) |

## 선택 도구

### tmux Codex 계정 배지와 전역 활동 요약

`tmux/status-right.sh`는 launcher가 현재 pane에 기록한 Codex 계정을
`👤 codex:개인` 또는 `👤 codex:회사`로 표시합니다. 계정 연동이 없으면 최근
5분 내 Claude/Codex 활동 **여부만** 표시합니다. 모델·비용·context는 넣지 않습니다.
설정은 [tmux 가이드](docs/tmux-setup.md)를 참조하세요.

### Python 집계 대시보드

```bash
PYTHONPATH=stats/src python3 -m forge_glow_stats --once
PYTHONPATH=stats/src python3 -m forge_glow_stats --json
```

이 대시보드는 최근 로컬 Claude 로그를 합산하는 **분석 뷰**이며 세션 HUD가
아닙니다. `~/.forge-glow/workflow.json`이 있으면 workflow 패널도 보여줍니다.

## 요구사항과 진단

- Claude Code v2.1.153+ (그 이전 버전도 동작하지만 폭 자동 조절 없음)
- Bash 3.2+
- `jq` 필수
- `bc` 선택: 없으면 시간당 비용만 생략

```bash
bash tools/diagnose.sh
bash test/parity/run.sh
```

## 제거

플러그인으로 설치했다면 먼저 Claude Code에서 HUD 설정을 비운 뒤 제거합니다.

```bash
# Claude Code 안에서 실행
/statusline clear

# 셸에서 실행
claude plugin uninstall forge-glow@forge-glow
```

개발용 클론이나 Homebrew의 `forge-glow install`로 직접 등록했다면:

```bash
bash uninstall.sh
```

`uninstall.sh`는 현재 `statusLine.command`가 forge-glow 소유일 때만 제거하며,
교체 설치에서 보관한 기존 status line이 있으면 복원합니다.

## 구조

```text
hud/statusline.sh              Claude HUD 진입점
hud/lib/parse-stdin.sh         현재 statusLine stdin
hud/lib/parse-transcript.sh    현재 transcript, message.id 중복 제거
hud/lib/parse-otel.sh          session.id 격리 OTLP/JSON
.claude-plugin/marketplace.json Claude 직접 marketplace
.agents/plugins/marketplace.json Codex 저장소 marketplace
plugins/forge-glow/            Codex plugin과 status-line 설정 skill
docs/codex-setup.md            Codex native status line
tools/plugin-manager.sh        두 제품의 설치·업데이트·상태 확인
tools/check-release.sh         배포 버전·경로 동기화 검사
tmux/status-right.sh           pane별 Codex 계정과 전역 활동 여부 표시
stats/                         Claude 로컬 집계 대시보드
test/parity/run.sh             렌더/스키마/세션 격리 회귀 테스트
test/install/run.sh            설치/제거/플러그인 훅 설정 보존 테스트
```

## License

MIT
