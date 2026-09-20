#!/bin/bash
# forge-glow session-init — Claude Code 플러그인 SessionStart 훅
#
# 책임:
#   1. ~/.claude/settings.json에 statusLine.command를 현재 플러그인 경로로 등록·검증
#   2. 사라진 경로(이전 버전, 청소된 /tmp 등) 자동 정리
#   3. 다른 statusLine을 발견하면 덮어쓰거나 합치지 않고 안내만 출력
#   4. mkdir 락으로 동시 세션 race 방지
#
# 안전:
#   - jq 없으면 조용히 종료 (settings 손상 방지)
#   - mkdir 락으로 동시 세션 race 방지
#   - 설정 변경은 stderr 안내로 사용자에게 알림
#   - 업데이트는 Claude 플러그인 관리자에 맡기며 캐시를 직접 git pull하지 않음

set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
STATUSLINE="$PLUGIN_ROOT/hud/statusline.sh"
SETTINGS="$HOME/.claude/settings.json"
STATE="$HOME/.forge-glow"
LOCK="$STATE/init.lock"

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
# 케이스 분기
if [ -z "$EXISTING" ]; then
  # 1. 미등록 → 신규 등록
  jq --arg cmd "$STATUSLINE" '.statusLine = {
    "type": "command", "command": $cmd, "refreshInterval": 15, "padding": 1
  }' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "[forge-glow] statusLine 등록됨 → $STATUSLINE" >&2

elif [ "$EXISTING" = "$STATUSLINE" ]; then
  # 2. 같은 경로 등록됨 → 사용자의 refresh/padding 커스텀은 그대로 유지
  :

elif echo "$EXISTING" | grep -q "forge-glow"; then
  # 3. forge-glow지만 다른 경로 (버전 변경) → 명령만 갱신하고 사용자 옵션은 보존
  jq --arg cmd "$STATUSLINE" '.statusLine.command = $cmd' \
    "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "[forge-glow] statusLine 경로 갱신 (버전 변경 감지) → $STATUSLINE" >&2

else
  # 4. 다른 HUD를 자동으로 합치면 세션 경계가 모호해질 수 있다.
  echo "[forge-glow] 기존 statusLine을 발견해 자동 등록하지 않음: $EXISTING" >&2
  echo "[forge-glow] 교체하려면 bash '$PLUGIN_ROOT/install.sh'에서 명시적으로 선택하세요." >&2
fi

exit 0
