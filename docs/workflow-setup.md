# Workflow 패널 설정 (Phase 7)

`forge-glow-stats`의 워크플로우 패널은 효율성 메트릭(비용/캐시/모델) 옆에 **작업 컨텍스트**(현재/다음 sub-task, 결정 누적, 빌드 히스토리, 미결정 Q)를 함께 표시합니다.

> "지금 어떤 작업을 어떤 모델로 얼마 들여 어떤 chain으로 진행 중인지, 다음은 뭔지" — 단일 진입점.

---

## 활성 조건

- `~/.forge-glow/workflow.json` 파일 존재 → 자동 활성
- `--workflow` 플래그 → 강제 활성 (config 없으면 안내)
- `--no-workflow` 플래그 → 강제 비활성

Config 경로 override: `WORKFLOW_CONFIG_PATH` 환경 변수.

---

## 1분 시작

```bash
# 1. 예시 복사
mkdir -p ~/.forge-glow
python3 -c "import forge_glow_stats, shutil, pathlib; \
  src = pathlib.Path(forge_glow_stats.__file__).parent / 'examples' / 'workflow.example.json'; \
  shutil.copy(src, pathlib.Path.home() / '.forge-glow' / 'workflow.json')"

# 2. 자신의 프로젝트로 수정
$EDITOR ~/.forge-glow/workflow.json

# 3. 실행
forge-glow-stats --once
```

---

## sources v2 schema

```jsonc
{
  "version": 2,
  "trackers": {
    "main-jira":  { "type": "jira",          "host": "example.atlassian.net", "browseUrl": "https://example.atlassian.net/browse/{id}" },
    "gh-issues":  { "type": "github-issues", "repo": "octocat/hello-world",    "browseUrl": "https://github.com/octocat/hello-world/issues/{id}" }
  },
  "projects": [
    {
      "id": "demo-project",
      "displayName": "Demo Project",
      "path": "~/code/demo-project",
      "trackerRef": "main-jira",
      "epic":  { "id": "EXAMPLE-100", "title": "Demo epic" },
      "items": [
        { "id": "EXAMPLE-101", "title": "...", "status": "done",        "kind": "current", "commits": 12 },
        { "id": "EXAMPLE-102", "title": "...", "status": "in_progress", "kind": "next"                  },
        { "id": "EXAMPLE-103", "title": "...", "status": "ready",       "kind": "next", "dependsOn": "EXAMPLE-102" }
      ],
      "progress": {
        "file":   "docs/progress.md",
        "preset": "decision-log"
      },
      "sources": {
        "buildReportsDir": "e2e/reports",
        "policyDocsDirs":  [".policy/docs"]
      },
      "links": {
        "design": "https://www.figma.com/file/xxxx",
        "repo":   "https://github.com/octocat/hello-world"
      }
    }
  ]
}
```

### items.status / items.kind

| status | 아이콘 | 의미 |
|---|---|---|
| `done` | ✅ | 완료 |
| `in_progress` | 🔄 | 진행 중 |
| `blocked` | 🚧 | 차단 |
| `ready` 또는 미지정 | ⏸ | 대기 |

| kind | 라벨 |
|---|---|
| `current` | 현재 |
| `next` | 다음 |
| `blocked` | 대기 |

### tracker 타입

| type | 필수 필드 | URL 예시 |
|---|---|---|
| `jira` | `host`, `browseUrl` | `https://example.atlassian.net/browse/{id}` |
| `github-issues` | `repo`, `browseUrl` | `https://github.com/octocat/hello-world/issues/{id}` |
| `linear` | `browseUrl` | `https://linear.app/team/issue/{id}` |
| `custom` | `browseUrl` | 임의 URL 템플릿 |

`{id}` placeholder는 `item.id`로 치환됩니다.

---

## progress 문서 파싱 — preset vs selectors

### preset (95% 케이스)

```jsonc
"progress": { "file": "docs/progress.md", "preset": "decision-log" }
```

내장 프리셋 (`forge_glow_stats/presets/progress/`):

| preset | 문서 형식 |
|---|---|
| `decision-log` | 결정 누적(`## N. 사용자 결정` 표) + 미결정(`### 🔴/🟡` 표) |
| `simple-todo` | `- [ ]` / `- [x]` 체크박스 섹션 |
| `kanban-md` | `## TODO / DOING / DONE` bullet list |

### selectors 직접 정의

```jsonc
"progress": {
  "file": "docs/progress.md",
  "selectors": {
    "pending_urgent": { "section": "^### 🔴",         "format": "table", "idColumn": 0, "titleColumn": 1 },
    "pending_hold":   { "section": "^### 🟡 보류 중",  "format": "table" },
    "decisions":      { "section": "^## 6\\.",         "format": "table", "idPattern": "^D\\d+" },
    "lastUpdated":    { "regex": "마지막 업데이트:\\s*([^)]+)\\)" }
  }
}
```

- `section` (regex): 섹션 헤더 매칭. 다음 동급 헤더까지를 본문으로 잡음.
- `format`: `table` | `checkbox` | `bullet`
- `idColumn` / `titleColumn`: 표 열 인덱스 (0-based)
- `extraColumns`: `{ "decider": 2, "tempDirection": 3, "affected": 4 }`
- `idPattern`: id 필터 regex (`^D\\d+` 등)
- `regex` (section 대신): 단일 매칭. 주로 `lastUpdated`에 사용.

Placeholder row (`(없음)`, `—`, `N/A`)는 자동 스킵됩니다.

---

## CLI 옵션

| 옵션 | 효과 |
|---|---|
| (없음) | `~/.forge-glow/workflow.json` 존재 시 자동 활성 |
| `--workflow` | 강제 활성 |
| `--no-workflow` | 강제 비활성 |
| `--json` | workflow 데이터를 JSON 출력에 포함 |

JSON 출력 구조:
```json
{
  "snapshot": { ... },
  "workflow": {
    "available": true,
    "config_path": "/Users/me/.forge-glow/workflow.json",
    "projects": [
      {
        "id": "...",
        "branch": "...",
        "epic_id": "...",
        "items": [{ "id": "...", "title": "...", "status": "...", "kind": "..." }],
        "pending_urgent": [...],
        "pending_hold": [...],
        "decisions": [...],
        "builds": [...]
      }
    ]
  }
}
```

---

## 자매 도구

markdown 출력을 선호한다면 [workflow markdown builder](https://github.com/...) (별도 Node CLI)와 **동일 schema 공유**. 같은 `~/.forge-glow/workflow.json`으로 양쪽 도구를 동시에 활용 가능.

---

## 디버깅

| 증상 | 확인 |
|---|---|
| 패널이 안 뜬다 | `forge-glow-stats --workflow` 강제 활성으로 에러 메시지 확인 |
| `repo missing` 표시 | `path` 절대/상대 경로 확인 (`~/` 확장 지원) |
| URL link가 없다 | `trackerRef`가 `trackers` 키와 일치하는지 / `browseUrl` 템플릿에 `{id}` 포함하는지 |
| pending Q가 비어있다 | `progress.preset` 선택 확인. 직접 셀렉터는 `section` regex 매칭 여부 |
| 결정이 안 잡힌다 | `idPattern` 확인 (decision-log는 `^D\d+`) |
