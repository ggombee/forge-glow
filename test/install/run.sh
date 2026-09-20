#!/usr/bin/env bash
# install.sh / uninstall.sh가 사용자 설정을 보존하는지 격리된 HOME에서 검증한다.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/forge-glow-install-test.XXXXXX)"

cleanup() {
  case "$TEST_ROOT" in
    /tmp/forge-glow-install-test.*|/private/tmp/forge-glow-install-test.*)
      rm -rf -- "$TEST_ROOT"
      ;;
  esac
}
trap cleanup EXIT

command -v jq >/dev/null 2>&1 || {
  echo "SKIP: jq is required"
  exit 0
}

# 기존 HUD를 교체한 뒤 제거하면 statusLine 객체 전체가 원형 복원되어야 한다.
HOME_REPLACE="$TEST_ROOT/replace"
mkdir -p "$HOME_REPLACE/.claude"
printf '%s\n' '{"theme":"dark","statusLine":{"type":"command","command":"/tmp/custom-hud.sh","refreshInterval":7,"padding":4,"hideVimModeIndicator":true}}' \
  > "$HOME_REPLACE/.claude/settings.json"
BEFORE_REPLACE=$(jq -S -c . "$HOME_REPLACE/.claude/settings.json")

printf '1\n' | HOME="$HOME_REPLACE" FORGE_GLOW_SKIP_AUTOUPDATE=1 \
  bash "$ROOT/install.sh" >/dev/null
HOME="$HOME_REPLACE" bash "$ROOT/uninstall.sh" >/dev/null

AFTER_REPLACE=$(jq -S -c . "$HOME_REPLACE/.claude/settings.json")
[ "$AFTER_REPLACE" = "$BEFORE_REPLACE" ] || {
  echo "FAIL: previous statusLine was not restored exactly"
  exit 1
}

# statusLine이 없던 설정은 설치/제거 후 다른 키만 그대로 남아야 한다.
HOME_NEW="$TEST_ROOT/new"
mkdir -p "$HOME_NEW/.claude"
printf '%s\n' '{"theme":"light"}' > "$HOME_NEW/.claude/settings.json"

HOME="$HOME_NEW" FORGE_GLOW_SKIP_AUTOUPDATE=1 \
  bash "$ROOT/install.sh" >/dev/null
HOME="$HOME_NEW" bash "$ROOT/uninstall.sh" >/dev/null

AFTER_NEW=$(jq -S -c . "$HOME_NEW/.claude/settings.json")
[ "$AFTER_NEW" = '{"theme":"light"}' ] || {
  echo "FAIL: unrelated settings changed during install/uninstall"
  exit 1
}

# 플러그인 훅은 다른 HUD를 자동으로 합치거나 덮어쓰면 안 된다.
HOME_CONFLICT="$TEST_ROOT/conflict"
mkdir -p "$HOME_CONFLICT/.claude"
printf '%s\n' '{"statusLine":{"type":"command","command":"/tmp/another-hud.sh","refreshInterval":9,"padding":3}}' \
  > "$HOME_CONFLICT/.claude/settings.json"
BEFORE_CONFLICT=$(jq -S -c . "$HOME_CONFLICT/.claude/settings.json")
HOME="$HOME_CONFLICT" CLAUDE_PLUGIN_ROOT="$ROOT" \
  bash "$ROOT/hooks/session-init.sh" >/dev/null 2>&1
AFTER_CONFLICT=$(jq -S -c . "$HOME_CONFLICT/.claude/settings.json")
[ "$AFTER_CONFLICT" = "$BEFORE_CONFLICT" ] || {
  echo "FAIL: plugin hook overwrote another HUD"
  exit 1
}

# 플러그인 버전 경로가 바뀌면 forge-glow 명령만 새 경로로 이동한다.
HOME_MIGRATE="$TEST_ROOT/migrate"
mkdir -p "$HOME_MIGRATE/.claude"
printf '%s\n' '{"theme":"dark","statusLine":{"type":"command","command":"/tmp/cache/forge-glow/0.8.0/hud/statusline.sh","refreshInterval":5,"padding":2}}' \
  > "$HOME_MIGRATE/.claude/settings.json"
HOME="$HOME_MIGRATE" CLAUDE_PLUGIN_ROOT="$ROOT" \
  bash "$ROOT/hooks/session-init.sh" >/dev/null 2>&1
jq -e --arg cmd "$ROOT/hud/statusline.sh" \
  '.theme == "dark" and .statusLine.command == $cmd and .statusLine.refreshInterval == 5 and .statusLine.padding == 2' \
  "$HOME_MIGRATE/.claude/settings.json" >/dev/null || {
    echo "FAIL: plugin cache path migration was incorrect"
    exit 1
  }

# 같은 경로를 사용 중이면 사용자가 조정한 statusLine 옵션을 보존한다.
HOME_CUSTOM="$TEST_ROOT/custom"
mkdir -p "$HOME_CUSTOM/.claude"
jq -n --arg cmd "$ROOT/hud/statusline.sh" \
  '{statusLine:{type:"command",command:$cmd,refreshInterval:3,padding:8,hideVimModeIndicator:true}}' \
  > "$HOME_CUSTOM/.claude/settings.json"
BEFORE_CUSTOM=$(jq -S -c . "$HOME_CUSTOM/.claude/settings.json")
HOME="$HOME_CUSTOM" CLAUDE_PLUGIN_ROOT="$ROOT" \
  bash "$ROOT/hooks/session-init.sh" >/dev/null 2>&1
AFTER_CUSTOM=$(jq -S -c . "$HOME_CUSTOM/.claude/settings.json")
[ "$AFTER_CUSTOM" = "$BEFORE_CUSTOM" ] || {
  echo "FAIL: plugin hook changed user-customized statusLine options"
  exit 1
}

# install.sh 재실행도 같은 경로의 사용자 옵션을 보존해야 한다.
HOME_REINSTALL="$TEST_ROOT/reinstall"
mkdir -p "$HOME_REINSTALL/.claude"
jq -n --arg cmd "$ROOT/hud/statusline.sh" \
  '{statusLine:{type:"command",command:$cmd,refreshInterval:4,padding:6,hideVimModeIndicator:true}}' \
  > "$HOME_REINSTALL/.claude/settings.json"
BEFORE_REINSTALL=$(jq -S -c . "$HOME_REINSTALL/.claude/settings.json")
HOME="$HOME_REINSTALL" FORGE_GLOW_SKIP_AUTOUPDATE=1 \
  bash "$ROOT/install.sh" >/dev/null
AFTER_REINSTALL=$(jq -S -c . "$HOME_REINSTALL/.claude/settings.json")
[ "$AFTER_REINSTALL" = "$BEFORE_REINSTALL" ] || {
  echo "FAIL: reinstall changed user-customized statusLine options"
  exit 1
}

# 직접 설치본과 동일 이름의 marketplace 플러그인이 함께 켜져 있으면 경로 재변경을 경고한다.
# 무관한 플러그인의 상태는 바꾸지 않는다.
HOME_PLUGIN_CONFLICT="$TEST_ROOT/plugin-conflict"
mkdir -p "$HOME_PLUGIN_CONFLICT/.claude"
printf '%s\n' '{"enabledPlugins":{"forge-glow@old-market":true,"unrelated@other-market":true}}' \
  > "$HOME_PLUGIN_CONFLICT/.claude/settings.json"
PLUGIN_CONFLICT_OUTPUT=$(HOME="$HOME_PLUGIN_CONFLICT" FORGE_GLOW_SKIP_AUTOUPDATE=1 \
  bash "$ROOT/install.sh")
printf '%s\n' "$PLUGIN_CONFLICT_OUTPUT" | grep -q 'claude plugin disable forge-glow@old-market' || {
  echo "FAIL: direct install did not warn about an enabled marketplace copy"
  exit 1
}
jq -e '
  .enabledPlugins["forge-glow@old-market"] == true
  and .enabledPlugins["unrelated@other-market"] == true
' "$HOME_PLUGIN_CONFLICT/.claude/settings.json" >/dev/null || {
  echo "FAIL: installer changed plugin enablement unexpectedly"
  exit 1
}

echo "ALL INSTALL TESTS GREEN"
