#!/usr/bin/env bash
# forge-glow uninstaller

set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"

if [ ! -f "$SETTINGS_FILE" ]; then
  echo "settings.json 없음. 이미 제거된 상태입니다."
  exit 0
fi

UPDATED=$(jq 'del(.statusLine)' "$SETTINGS_FILE")
echo "$UPDATED" > "$SETTINGS_FILE"

echo "✅ forge-glow 제거 완료. statusLine 설정이 삭제되었습니다."