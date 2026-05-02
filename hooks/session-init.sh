#!/bin/bash
# forge-glow session-init — Claude Code 플러그인 SessionStart 훅
#
# 책임:
#   1. ~/.claude/settings.json에 statusLine.command를 현재 캐시 경로로 등록·검증
#   2. 사라진 경로(이전 버전, 청소된 /tmp 등) 자동 정리
#   3. 기존 다른 statusLine 있으면 자동 wrap (둘 다 표시)
#   4. 1회만 실행 (마커 파일로 race 방지). 단 경로 mismatch면 재등록.
#
# 안전:
#   - jq 없으면 조용히 종료 (settings 손상 방지)
#   - mkdir 락으로 동시 세션 race 방지
#   - 모든 변경은 stdout 안내 1줄로 사용자에게 알림

set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
STATUSLINE="$PLUGIN_ROOT/hud/statusline.sh"
SETTINGS="$HOME/.claude/settings.json"
STATE="$HOME/.forge-glow"
LOCK="$STATE/init.lock"
MARKER="$STATE/registered-path"

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
