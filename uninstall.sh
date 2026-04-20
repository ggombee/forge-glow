#!/usr/bin/env bash
# forge-glow uninstaller — statusLine 등록 해제 + 자동 갱신 스케줄러 제거

set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"
PLIST_LABEL="io.ggombee.forge-glow.update"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"

# ── statusLine 제거 ──
if [ -f "$SETTINGS_FILE" ]; then
  UPDATED=$(jq 'del(.statusLine)' "$SETTINGS_FILE")
  echo "$UPDATED" > "$SETTINGS_FILE"
  echo "✅ statusLine 설정 삭제"
else
  echo "ℹ️  settings.json 없음 (statusLine 이미 제거됨)"
fi

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
