#!/usr/bin/env bash
# forge-glow installer
# settings.json에 statusLine 등록

set -euo pipefail

GLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="$HOME/.claude/settings.json"
STATUSLINE_CMD="$GLOW_DIR/hud/statusline.sh"

echo "🔥 forge-glow installer"
echo ""

# jq 체크
if ! command -v jq &>/dev/null; then
  echo "❌ jq가 필요합니다: brew install jq"
  exit 1
fi

# settings.json 존재 확인
if [ ! -f "$SETTINGS_FILE" ]; then
  echo "⚠️  $SETTINGS_FILE 없음. 생성합니다."
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  echo '{}' > "$SETTINGS_FILE"
fi

# 기존 statusLine 체크
EXISTING=$(jq -r '.statusLine.command // empty' "$SETTINGS_FILE" 2>/dev/null)
if [ -n "$EXISTING" ]; then
  echo "⚠️  기존 statusLine 감지: $EXISTING"
  echo ""
  read -p "forge-glow로 교체할까요? (y/n) " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "설치 취소."
    exit 0
  fi
fi

# statusLine 등록
UPDATED=$(jq --arg cmd "$STATUSLINE_CMD" '.statusLine = {
  "type": "command",
  "command": $cmd,
  "refreshInterval": 5,
  "padding": 1
}' "$SETTINGS_FILE")

echo "$UPDATED" > "$SETTINGS_FILE"

echo "✅ forge-glow 설치 완료!"
echo ""
echo "   statusLine: $STATUSLINE_CMD"
echo "   refreshInterval: 5초"
echo ""
echo "   Claude Code를 재시작하면 HUD가 표시됩니다."
echo ""
echo "   제거: bash $(dirname "$0")/uninstall.sh"