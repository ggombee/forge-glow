#!/usr/bin/env bash
# forge-glow uninstaller — statusLine 등록 해제 + 자동 갱신 스케줄러 제거

set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"
STATE_DIR="$HOME/.forge-glow"
PREVIOUS_STATUSLINE="$STATE_DIR/previous-statusline.json"
PLIST_LABEL="io.ggombee.forge-glow.update"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"

# ── statusLine 제거 ──
if [ -f "$SETTINGS_FILE" ]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "❌ jq가 없어 settings.json을 안전하게 수정할 수 없습니다."
    exit 1
  fi
  REGISTERED=$(jq -r '.statusLine.command // empty' "$SETTINGS_FILE" 2>/dev/null)
  if echo "$REGISTERED" | grep -q "forge-glow"; then
    if [ -s "$PREVIOUS_STATUSLINE" ] && \
       jq -e 'type == "object" and (.command | type == "string")' \
         "$PREVIOUS_STATUSLINE" >/dev/null 2>&1; then
      UPDATED=$(jq --slurpfile previous "$PREVIOUS_STATUSLINE" \
        '.statusLine = $previous[0]' "$SETTINGS_FILE")
      printf '%s\n' "$UPDATED" > "$SETTINGS_FILE.tmp"
      mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
      echo "✅ 기존 statusLine 전체 설정 복원"
    else
      UPDATED=$(jq 'del(.statusLine)' "$SETTINGS_FILE")
      printf '%s\n' "$UPDATED" > "$SETTINGS_FILE.tmp"
      mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
      echo "✅ forge-glow statusLine 설정 삭제"
    fi
  else
    echo "ℹ️  현재 statusLine은 forge-glow 소유가 아니므로 변경하지 않음"
  fi
else
  echo "ℹ️  settings.json 없음 (statusLine 이미 제거됨)"
fi

rm -f "$PREVIOUS_STATUSLINE" 2>/dev/null || true

# ── 자동 갱신 스케줄러 제거 ──
case "$(uname -s)" in
  Darwin)
    if [ -f "$PLIST_PATH" ]; then
      launchctl bootout "gui/$(id -u)/${PLIST_LABEL}" 2>/dev/null || true
      rm -f "$PLIST_PATH"
      echo "✅ launchd 자동 갱신 해제"
    fi
    ;;
  Linux)
    if command -v crontab &>/dev/null; then
      if crontab -l 2>/dev/null | grep -q "forge-glow/tools/self-update.sh"; then
        crontab -l 2>/dev/null | grep -v "forge-glow/tools/self-update.sh" | crontab -
        echo "✅ cron 자동 갱신 해제"
      fi
    fi
    ;;
esac

echo ""
echo "forge-glow 제거 완료."
echo "레포 디렉터리와 $HOME/.forge-glow는 수동으로 삭제하세요 (원하면):"
echo "  rm -rf ~/.forge-glow"
