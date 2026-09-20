#!/usr/bin/env bash
# forge-glow installer — Claude settings.json에 statusLine 등록 (교체 / 취소)

set -euo pipefail

GLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="$HOME/.claude/settings.json"
STATUSLINE_CMD="$GLOW_DIR/hud/statusline.sh"
STATE_DIR="$HOME/.forge-glow"
PREVIOUS_STATUSLINE="$STATE_DIR/previous-statusline.json"
ENABLED_PLUGIN_ID=""

echo "🔥 forge-glow installer"
echo ""

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq가 필요합니다: brew install jq"
  exit 1
fi

if [ ! -f "$SETTINGS_FILE" ]; then
  echo "⚠️  $SETTINGS_FILE 없음. 생성합니다."
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  printf '{}\n' > "$SETTINGS_FILE"
fi

# 직접 설치본과 marketplace 플러그인을 동시에 켜 두면, 다음 SessionStart에서
# marketplace 캐시의 hook이 statusLine.command를 캐시 경로로 되돌릴 수 있다.
# 다른 플러그인은 건드리지 않고 동일 이름만 진단한다.
if [[ "$GLOW_DIR" != *"/.claude/plugins/cache/"* ]]; then
  ENABLED_PLUGIN_ID=$(jq -r '
    (.enabledPlugins // {})
    | to_entries[]?
    | select(.value == true and (.key | startswith("forge-glow@")))
    | .key
  ' "$SETTINGS_FILE" 2>/dev/null | head -1)
fi

EXISTING=$(jq -r '.statusLine.command // empty' "$SETTINGS_FILE" 2>/dev/null)
MODE="new"

if [ "$EXISTING" = "$STATUSLINE_CMD" ]; then
  MODE="existing"
elif echo "$EXISTING" | grep -q "forge-glow"; then
  MODE="migrate"
elif [ -n "$EXISTING" ]; then
  echo "⚠️  기존 statusLine 감지:"
  echo "   $EXISTING"
  echo ""
  echo "  [1] 교체 — forge-glow로 교체 (제거 시 기존 명령 복원)"
  echo "  [2] 취소"
  echo ""
  read -r -p "선택 (1/2): " -n 1 CHOICE
  echo ""
  case "$CHOICE" in
    1)
      MODE="replace"
      mkdir -p "$STATE_DIR"
      jq -c '.statusLine' "$SETTINGS_FILE" > "$PREVIOUS_STATUSLINE"
      ;;
    *)
      echo "설치 취소."
      exit 0
      ;;
  esac
fi

case "$MODE" in
  existing)
    echo "ℹ️  같은 statusLine이 이미 등록되어 사용자 옵션을 그대로 유지합니다."
    ;;
  migrate)
    UPDATED=$(jq --arg cmd "$STATUSLINE_CMD" '.statusLine.command = $cmd' "$SETTINGS_FILE")
    printf '%s\n' "$UPDATED" > "$SETTINGS_FILE.tmp"
    mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
    ;;
  *)
    UPDATED=$(jq --arg cmd "$STATUSLINE_CMD" '.statusLine = {
      "type": "command",
      "command": $cmd,
      "refreshInterval": 15,
      "padding": 1
    }' "$SETTINGS_FILE")
    printf '%s\n' "$UPDATED" > "$SETTINGS_FILE.tmp"
    mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
    ;;
esac

# 선택적 자동 업데이트 스케줄러 (macOS launchd / Linux cron)
UPDATE_SCRIPT="$GLOW_DIR/tools/self-update.sh"
PLIST_LABEL="io.ggombee.forge-glow.update"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
AUTOUPDATE_STATUS="미등록"

register_autoupdate() {
  if [ ! -x "$UPDATE_SCRIPT" ]; then
    echo "⚠️  tools/self-update.sh 없음 — 자동 갱신 스킵"
    AUTOUPDATE_STATUS="미등록 (updater 없음)"
    return
  fi

  case "$(uname -s)" in
    Darwin)
      mkdir -p "$(dirname "$PLIST_PATH")" "$STATE_DIR"
      cat > "$PLIST_PATH" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${PLIST_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${UPDATE_SCRIPT}</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>FORGE_GLOW_DIR</key><string>${GLOW_DIR}</string>
    <key>PATH</key><string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>3600</integer>
  <key>StandardErrorPath</key><string>${STATE_DIR}/launchd.err.log</string>
  <key>StandardOutPath</key><string>${STATE_DIR}/launchd.out.log</string>
</dict>
</plist>
PLIST_EOF
      launchctl bootout "gui/$(id -u)/${PLIST_LABEL}" 2>/dev/null || true
      if launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null; then
        echo "✅ launchd 자동 갱신 등록 완료 (1시간 간격)"
        AUTOUPDATE_STATUS="1시간 간격 (개발용 Git clone)"
      else
        echo "⚠️  launchctl 등록 실패 — 수동 실행: bash $UPDATE_SCRIPT"
        AUTOUPDATE_STATUS="미등록 (launchctl 실패)"
      fi
      ;;
    Linux)
      local cron_line="0 * * * * FORGE_GLOW_DIR=$GLOW_DIR /bin/bash $UPDATE_SCRIPT"
      if command -v crontab >/dev/null 2>&1; then
        (crontab -l 2>/dev/null | grep -v "forge-glow/tools/self-update.sh"; echo "$cron_line") | crontab -
        echo "✅ cron 자동 갱신 등록 완료 (매시 정각)"
        AUTOUPDATE_STATUS="1시간 간격 (개발용 Git clone)"
      else
        echo "⚠️  crontab 없음. 수동 등록 필요: $cron_line"
        AUTOUPDATE_STATUS="미등록 (crontab 없음)"
      fi
      ;;
    *)
      echo "⚠️  자동 갱신은 macOS/Linux만 지원. 수동 실행: bash $UPDATE_SCRIPT"
      AUTOUPDATE_STATUS="미등록 (지원하지 않는 OS)"
      ;;
  esac
}

if [ "${FORGE_GLOW_SKIP_AUTOUPDATE:-0}" = "1" ]; then
  echo "ℹ️  FORGE_GLOW_SKIP_AUTOUPDATE=1 — 자동 갱신 등록 스킵"
  AUTOUPDATE_STATUS="미등록 (명시적으로 스킵)"
elif [ ! -d "$GLOW_DIR/.git" ] || [[ "$GLOW_DIR" == *"/.claude/plugins/cache/"* ]]; then
  echo "ℹ️  플러그인/Homebrew/tarball 설치본은 해당 패키지 관리자가 업데이트합니다."
  AUTOUPDATE_STATUS="패키지 관리자 사용"
else
  register_autoupdate
fi

echo ""
echo "✅ forge-glow 설치 완료 (모드: $MODE)"
echo ""
echo "   statusLine: $STATUSLINE_CMD"
CURRENT_REFRESH=$(jq -r '.statusLine.refreshInterval // empty' "$SETTINGS_FILE" 2>/dev/null)
if [ -n "$CURRENT_REFRESH" ]; then
  echo "   refreshInterval: ${CURRENT_REFRESH}초 + Claude 이벤트 즉시 갱신"
else
  echo "   refreshInterval: Claude 이벤트 기반 (기존 사용자 옵션 보존)"
fi
echo "   자동 갱신: $AUTOUPDATE_STATUS"
echo ""
echo "   실행 중인 Claude Code는 설정 감지 후 다음 상호작용에서 HUD가 갱신됩니다."
echo "   계속 비어 있으면 workspace trust를 확인한 뒤 Claude Code를 재시작하세요."
if [ -n "$ENABLED_PLUGIN_ID" ]; then
  echo ""
  echo "⚠️  $ENABLED_PLUGIN_ID 가 활성 상태입니다."
  echo "   다음 Claude 시작 때 marketplace 캐시가 이 경로를 되돌릴 수 있습니다."
  echo "   로컬 개발본을 유지하려면: claude plugin disable $ENABLED_PLUGIN_ID"
fi
echo "   OTel 모델별 추정값 보강: docs/otel-setup.md 참조"
echo ""
echo "   제거: bash $(dirname "$0")/uninstall.sh"
