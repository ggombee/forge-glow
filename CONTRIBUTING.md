# Contributing — 어댑터 작성 가이드

forge-glow는 **Claude Code 하네스 플러그인들을 감지해 추가 정보를 statusLine에 얹는** 어댑터 시스템을 제공합니다.
`hud/adapters/*.sh`에 실행 가능한 스크립트를 두면 `statusline.sh`가 자동 로드합니다.

---

## 어댑터 규약

| 항목 | 요구사항 |
|------|----------|
| 파일 위치 | `hud/adapters/{name}.sh` |
| 실행 권한 | `chmod +x` 필수 |
| 출력 | stdout 1줄 (비어있으면 무시됨) |
| 실패 | 항상 `exit 0` (statusLine 전체를 깨면 안 됨) |
| 실행 시간 | 10ms 이내 권장 (statusLine 총 예산 100ms) |
| 의존성 | `jq` 외 신규 런타임 도입 금지 |
| 감지 실패 시 | 대상 플러그인 미설치면 **조용히** 종료 |

---

## 최소 템플릿

```bash
#!/usr/bin/env bash
# forge-glow adapter — {플러그인명}
# https://github.com/{owner}/{repo}

TARGET_DIR="$HOME/.claude/{plugin-name}"
[ ! -d "$TARGET_DIR" ] && exit 0

# 데이터 수집
VERSION=""
if [ -f "$TARGET_DIR/VERSION" ]; then
  VERSION=$(head -1 "$TARGET_DIR/VERSION" 2>/dev/null | tr -d ' \n')
fi

# 출력
OUT="🎯 {플러그인}"
[ -n "$VERSION" ] && OUT="${OUT} v${VERSION}"
echo "$OUT"
```

---

## 이모지 선점표

다른 어댑터와 겹치지 않도록 선점된 이모지는 아래와 같습니다. 새 어댑터는 선점되지 않은 이모지를 사용하세요.

| 플러그인 | 이모지 |
|----------|--------|
| code-forge | 🔨 |
| OMC (oh-my-claudecode) | 🎭 |
| (다음 어댑터) | — |

---

## PR 체크리스트

- [ ] `hud/adapters/{name}.sh` 생성 및 실행 권한 부여
- [ ] shellcheck `-S warning` 통과 (`brew install shellcheck` 후 `shellcheck hud/adapters/{name}.sh`)
- [ ] 대상 플러그인 미설치 환경에서 아무 출력도 안 하는지 확인
- [ ] `CONTRIBUTING.md`의 이모지 선점표 업데이트
- [ ] `README.md`의 지원 플러그인 목록에 추가

---

## 테스트

```bash
# 어댑터만 단독 실행
./hud/adapters/{name}.sh

# statusLine 전체 테스트 (stdin JSON 필요)
echo '{"model":{"display_name":"Opus"},"workspace":{"project_dir":"/tmp"}}' | ./hud/statusline.sh
```

---

## 참고

- [Claude Code statusLine API](https://code.claude.com/docs/en/statusline)
- [OpenTelemetry file exporter](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter/fileexporter) (L5 연동용)
