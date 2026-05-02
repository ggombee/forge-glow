#!/bin/bash
# forge-glow session-init — Claude Code 플러그인 SessionStart 훅
#
# 책임:
#   0. **자체 git pull** (캐시 디렉터리에서 main을 ff-only 갱신) — 본인이 push하면 모든 사용자가 다음 세션 자동 반영
#   1. ~/.claude/settings.json에 statusLine.command를 현재 캐시 경로로 등록·검증
#   2. 사라진 경로(이전 버전, 청소된 /tmp 등) 자동 정리
#   3. 기존 다른 statusLine 있으면 자동 wrap (둘 다 표시)
#   4. 1회만 실행 (마커 파일로 race 방지). 단 경로 mismatch면 재등록.
#
# 안전:
#   - jq 없으면 조용히 종료 (settings 손상 방지)
#   - mkdir 락으로 동시 세션 race 방지
#   - 모든 변경은 stdout 안내 1줄로 사용자에게 알림
#   - dirty tree / ff 불가 시 git pull 스킵 (사용자 작업 보호)

set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
STATUSLINE="$PLUGIN_ROOT/hud/statusline.sh"
SETTINGS="$HOME/.claude/settings.json"
STATE="$HOME/.forge-glow"
LOCK="$STATE/init.lock"
MARKER="$STATE/registered-path"
CACHE_VER="$PLUGIN_ROOT/.plugin-cache-version"

# ─────────────────────────────────────────────────────────────
# 0. 자체 git pull — code-forge 패턴과 동일
#    캐시 디렉터리(~/.claude/plugins/cache/.../)는 .git 보유 → ff-only로 안전 갱신
# ─────────────────────────────────────────────────────────────
self_update() (
  # 서브쉘 — cwd / 함수 변경이 호출자에 영향 없음
  [ ! -d "$PLUGIN_ROOT/.git" ] && exit 0
  cd "$PLUGIN_ROOT" || exit 0

  git fetch origin --quiet 2>/dev/null || exit 0

  local local_head remote_head
  local_head=$(git rev-parse HEAD 2>/dev/null || echo "")
  remote_head=$(git rev-parse origin/main 2>/dev/null || echo "")
  [ -z "$local_head" ] || [ -z "$remote_head" ] && exit 0

  local local_ver
  local_ver=$(grep -o '"version": *"[^"]*"' "$PLUGIN_JSON" 2>/dev/null | head -1 | grep -o '[0-9][0-9.]*')

  if [ "$local_head" = "$remote_head" ]; then
    [ -n "$local_ver" ] && echo "$local_ver" > "$CACHE_VER" 2>/dev/null
    exit 0
  fi

  # dirty tree 보호
  git diff --quiet 2>/dev/null || exit 0
  git diff --cached --quiet 2>/dev/null || exit 0

  # ff-only 갱신
  git pull origin main --ff-only --quiet 2>/dev/null || exit 0

  local new_ver prev_ver
  new_ver=$(grep -o '"version": *"[^"]*"' "$PLUGIN_JSON" 2>/dev/null | head -1 | grep -o '[0-9][0-9.]*')
  prev_ver="${local_ver}"
  [ -f "$CACHE_VER" ] && prev_ver=$(cat "$CACHE_VER" 2>/dev/null || echo "$local_ver")

  if [ "$prev_ver" != "$new_ver" ]; then
    echo "⚡ forge-glow updated: v${prev_ver} → v${new_ver}" >&2
    local changes
    changes=$(git log --oneline "${local_head}..HEAD" --no-decorate 2>/dev/null | head -3)
    [ -n "$changes" ] && echo "Changes:" >&2 && echo "$changes" >&2
  fi
  echo "$new_ver" > "$CACHE_VER" 2>/dev/null
)

self_update

# 자체 갱신 후 statusline.sh 경로가 갱신됐을 수 있으니 변수 다시 평가
STATUSLINE="$PLUGIN_ROOT/hud/statusline.sh"

# ─────────────────────────────────────────────────────────────
# Windows CRLF 자동 복구
# Windows에서 git pull 시 CRLF로 변환된 .sh가 jq stdin/shebang을 깨뜨림.
# (증상: HUD에 모델명 '?', 컨텍스트 '0%'만 표시)
# 이미 받아진 파일에 \r이 있으면 in-place 제거 (1회).
# ─────────────────────────────────────────────────────────────
if [ -f "$STATUSLINE" ] && head -1 "$STATUSLINE" 2>/dev/null | grep -q $'\r'; then
  echo "[forge-glow] CRLF 감지 — Unix LF로 복구 중..." >&2
  find "$PLUGIN_ROOT" \( -name '*.sh' -o -name '*.json' -o -name '*.md' \) -type f 2>/dev/null \
    | while IFS= read -r f; do
        # macOS BSD sed와 GNU sed 모두 호환되는 인플레이스 제거
        if sed -i.bak 's/\r$//' "$f" 2>/dev/null; then
          rm -f "$f.bak" 2>/dev/null
        fi
      done
  # core.autocrlf를 false로 고정해 다음 pull부터 재발 방지
  ( cd "$PLUGIN_ROOT" && git config core.autocrlf false 2>/dev/null ) || true
  echo "[forge-glow] CRLF 복구 완료. 다음 세션부터 정상 표시." >&2
fi

# jq 필수 — 없으면 안내만 하고 종료
if ! command -v jq >/dev/null 2>&1; then
  echo "[forge-glow] jq 미설치 — statusLine 자동 등록 스킵. 'brew install jq' 후 재실행하세요." >&2
  exit 0
fi

# statusline.sh 존재 확인 (플러그인 캐시가 깨졌으면 정리)
if [ ! -x "$STATUSLINE" ]; then
  # settings에서 forge-glow 경로면 제거
  if [ -f "$SETTINGS" ]; then
    EXISTING=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null)
    if echo "$EXISTING" | grep -q "forge-glow"; then
      jq 'del(.statusLine)' "$SETTINGS" > "$SETTINGS.tmp" 2>/dev/null && mv "$SETTINGS.tmp" "$SETTINGS"
      echo "[forge-glow] statusline.sh 사라짐 → settings에서 정리됨" >&2
    fi
  fi
  exit 0
fi

mkdir -p "$STATE"

# 동시 세션 race 방지
if ! mkdir "$LOCK" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

# settings.json 없으면 생성
if [ ! -f "$SETTINGS" ]; then
  mkdir -p "$(dirname "$SETTINGS")"
  echo '{}' > "$SETTINGS"
fi

# 현재 등록된 statusLine 확인
EXISTING=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null)
PREV_REGISTERED=$(cat "$MARKER" 2>/dev/null || echo "")

# 케이스 분기
if [ -z "$EXISTING" ]; then
  # 1. 미등록 → 신규 등록
  jq --arg cmd "$STATUSLINE" '.statusLine = {
    "type": "command", "command": $cmd, "refreshInterval": 5, "padding": 1
  }' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "$STATUSLINE" > "$MARKER"
  echo "[forge-glow] statusLine 등록됨 → $STATUSLINE" >&2

elif [ "$EXISTING" = "$STATUSLINE" ]; then
  # 2. 같은 경로 등록됨 → 마커만 갱신
  echo "$STATUSLINE" > "$MARKER"

elif echo "$EXISTING" | grep -q "forge-glow"; then
  # 3. forge-glow지만 다른 경로 (버전 변경) → 새 경로로 갱신
  jq --arg cmd "$STATUSLINE" '.statusLine.command = $cmd' \
    "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "$STATUSLINE" > "$MARKER"
  echo "[forge-glow] statusLine 경로 갱신 (버전 변경 감지) → $STATUSLINE" >&2

elif [ -n "$EXISTING" ] && [ "$EXISTING" != "$PREV_REGISTERED" ]; then
  # 4. 다른 도구의 statusLine — 자동 wrap (사용자 의사 존중)
  WRAPPER="$STATE/wrapper.sh"
  cat > "$WRAPPER" <<WRAP_EOF
#!/bin/bash
# forge-glow wrapper — 자동 생성 ($(date -u +"%Y-%m-%dT%H:%M:%SZ"))
STDIN=\$(cat)
echo "\$STDIN" | "$EXISTING" 2>/dev/null
echo "\$STDIN" | "$STATUSLINE" 2>/dev/null
WRAP_EOF
  chmod +x "$WRAPPER"
  jq --arg cmd "$WRAPPER" '.statusLine.command = $cmd' \
    "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "$STATUSLINE" > "$MARKER"
  echo "[forge-glow] 기존 statusLine 감지 → 자동 wrap 모드 (둘 다 표시)" >&2
  echo "[forge-glow]   기존: $EXISTING" >&2
  echo "[forge-glow]   추가: $STATUSLINE" >&2
fi

exit 0
