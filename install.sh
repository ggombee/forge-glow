#!/usr/bin/env bash
# forge-glow installer
# settings.json에 statusLine 등록 (교체 / 래핑 / 취소 3택)

set -euo pipefail

GLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="$HOME/.claude/settings.json"
STATUSLINE_CMD="$GLOW_DIR/hud/statusline.sh"
WRAPPER_CMD="$GLOW_DIR/hud/wrapper.sh"

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
MODE="replace"

if [ -n "$EXISTING" ]; then
  echo "⚠️  기존 statusLine 감지:"
  echo "   $EXISTING"
  echo ""
  echo "어떻게 처리할까요?"
  echo "  [1] 교체 — forge-glow로 완전 교체 (기존 출력 사라짐)"
  echo "  [2] 래핑 — 기존 출력 + forge-glow 3줄 append (둘 다 표시)"
  echo "  [3] 취소"
  echo ""
  read -r -p "선택 (1/2/3): " -n 1 CHOICE
  echo ""
  case "$CHOICE" in
    1) MODE="replace" ;;
    2) MODE="wrap" ;;
    *)
      echo "설치 취소."
      exit 0
      ;;
  esac
fi

# ── 래핑 모드: wrapper.sh 생성 ─────────────────────────────
if [ "$MODE" = "wrap" ]; then
  echo "📦 래핑 wrapper 생성: $WRAPPER_CMD"
  cat > "$WRAPPER_CMD" <<WRAPPER_EOF
#!/usr/bin/env bash
# forge-glow wrapper — 기존 statusLine 출력 + forge-glow 출력 결합
# 자동 생성: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

# stdin을 한 번만 읽어 양쪽에 전달 (tee는 파이프 안 됨)
STDIN_BUF=\$(cat)

# 기존 statusLine 출력
echo "\$STDIN_BUF" | "$EXISTING"

# forge-glow 출력
echo "\$STDIN_BUF" | "$STATUSLINE_CMD"
WRAPPER_EOF
  chmod +x "$WRAPPER_CMD"
  FINAL_CMD="$WRAPPER_CMD"
else
  FINAL_CMD="$STATUSLINE_CMD"
fi

# statusLine 등록
UPDATED=$(jq --arg cmd "$FINAL_CMD" '.statusLine = {
  "type": "command",
  "command": $cmd,
  "refreshInterval": 5,
  "padding": 1
}' "$SETTINGS_FILE")

echo "$UPDATED" > "$SETTINGS_FILE"

# ── 자동 업데이트 스케줄러 등록 (macOS launchd / Linux cron) ──
UPDATE_SCRIPT="$GLOW_DIR/tools/self-update.sh"
PLIST_LABEL="io.ggombee.forge-glow.update"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"

register_autoupdate() {
  if [ ! -x "$UPDATE_SCRIPT" ]; then
    echo "⚠️  tools/self-update.sh 없음 — 자동 갱신 스킵"
    return
  fi

  case "$(uname -s)" in
    Darwin)
      mkdir -p "$(dirname "$PLIST_PATH")"
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
  <key>StandardErrorPath</key><string>${HOME}/.forge-glow/launchd.err.log</string>
  <key>StandardOutPath</key><string>${HOME}/.forge-glow/launchd.out.log</string>
</dict>
</plist>
PLIST_EOF
      mkdir -p "$HOME/.forge-glow"
      launchctl bootout "gui/$(id -u)/${PLIST_LABEL}" 2>/dev/null || true
      if launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null; then
        echo "✅ launchd 자동 갱신 등록 완료 (1시간 간격)"
      else
        echo "⚠️  launchctl 등록 실패 — 수동 실행 가능: bash $UPDATE_SCRIPT"
      fi
      ;;
    Linux)
      CRON_LINE="0 * * * * FORGE_GLOW_DIR=$GLOW_DIR /bin/bash $UPDATE_SCRIPT"
      if command -v crontab &>/dev/null; then
        (crontab -l 2>/dev/null | grep -v "forge-glow/tools/self-update.sh"; echo "$CRON_LINE") | crontab -
        echo "✅ cron 자동 갱신 등록 완료 (매시 정각)"
      else
        echo "⚠️  crontab 없음. 수동 등록 필요:"
        echo "   $CRON_LINE"
      fi
      ;;
    *)
      echo "⚠️  자동 갱신은 macOS/Linux만 지원. 수동 실행: bash $UPDATE_SCRIPT"
      ;;
  esac
}

register_autoupdate

echo ""
echo "✅ forge-glow 설치 완료 (모드: $MODE)"
echo ""
echo "   statusLine: $FINAL_CMD"
echo "   refreshInterval: 5초"
echo "   자동 갱신: 1시간 간격 (clean tree + ff-only)"
echo ""
if [ "$MODE" = "wrap" ]; then
  echo "   기존 statusLine과 함께 동작합니다."
  echo "   래핑 해제하려면: bash $(dirname "$0")/uninstall.sh"
fi
echo ""
echo "   Claude Code를 재시작하면 HUD가 표시됩니다."
echo "   OTel L5 활성화: docs/otel-setup.md 참조"
echo ""
echo "   제거: bash $(dirname "$0")/uninstall.sh"
