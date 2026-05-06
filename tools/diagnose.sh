#!/usr/bin/env bash
# forge-glow — diagnose.sh
# 한 줄 실행으로 Windows/macOS/Linux 환경 자가 진단.
# 안 보이는/깨진 statusLine 원인을 사용자가 즉시 파악할 수 있도록 모든 정보 한 번에.
#
# 사용:
#   bash ~/.claude/plugins/cache/forge-market/forge-glow/*/tools/diagnose.sh
#   또는 git clone 받은 경우: bash <repo>/tools/diagnose.sh
#
# 출력:
#   stdout: 사람이 읽는 진단 리포트
#   exit code: 0 정상 / 1 문제 발견

set +e

ok()   { printf '  ✓ %s\n' "$1"; }
warn() { printf '  ⚠ %s\n' "$1"; ISSUES=$((${ISSUES:-0}+1)); }
err()  { printf '  ✗ %s\n' "$1"; ISSUES=$((${ISSUES:-0}+1)); }

ISSUES=0

echo "═══════════════════════════════════════════════════════════════"
echo "  forge-glow diagnose ($(date -u +"%Y-%m-%dT%H:%M:%SZ"))"
echo "═══════════════════════════════════════════════════════════════"

# ── 1. 시스템 ──────────────────────────────────────────────
echo
echo "[1] 시스템"
echo "  uname:    $(uname -a 2>/dev/null || echo unknown)"
echo "  bash:     $BASH_VERSION"
echo "  OSTYPE:   ${OSTYPE:-unknown}"

# ── 2. 필수 의존성 ─────────────────────────────────────────
echo
echo "[2] 필수 의존성"
if command -v jq >/dev/null 2>&1; then
  ok "jq: $(jq --version 2>&1 | head -1) ($(command -v jq))"
else
  err "jq 미설치 — Windows: 'choco install jq' 또는 'scoop install jq'"
fi

if command -v bc >/dev/null 2>&1; then
  ok "bc: $(echo 'print 1' | bc 2>&1 | head -1) ($(command -v bc))"
else
  warn "bc 미설치 — 시간당 비용 계산만 안 됨, 나머지 정상"
fi

if command -v git >/dev/null 2>&1; then
  ok "git: $(git --version 2>&1 | head -1)"
else
  err "git 미설치"
fi

# ── 3. forge-glow 설치 위치 / 버전 ─────────────────────────
echo
echo "[3] forge-glow"
PLUGIN_PATHS=(
  "$HOME/.claude/plugins/cache/forge-market/forge-glow"
  "$HOME/Desktop/workspace/forge-glow"
  "$HOME/work/forge-glow"
)
FOUND_INSTALL=""
for base in "${PLUGIN_PATHS[@]}"; do
  if [ -d "$base" ]; then
    # 캐시는 버전 디렉터리, dev clone은 직접
    if [ -f "$base/.claude-plugin/plugin.json" ]; then
      FOUND_INSTALL="$base"
      break
    fi
    # 캐시 디렉터리 안의 첫 버전 디렉터리
    for ver in "$base"/*/; do
      [ -f "$ver.claude-plugin/plugin.json" ] && FOUND_INSTALL="${ver%/}" && break 2
    done
  fi
done

if [ -n "$FOUND_INSTALL" ]; then
  VERSION=$(grep -o '"version":[[:space:]]*"[^"]*"' "$FOUND_INSTALL/.claude-plugin/plugin.json" 2>/dev/null \
    | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  ok "위치: $FOUND_INSTALL"
  ok "버전: ${VERSION:-unknown}"
  STATUSLINE="$FOUND_INSTALL/hud/statusline.sh"
  if [ -x "$STATUSLINE" ]; then
    ok "statusline.sh 존재 + 실행 권한"
  else
    err "statusline.sh 없음 또는 실행 권한 없음: $STATUSLINE"
  fi
else
  err "forge-glow 설치본을 찾을 수 없음 (~/.claude/plugins/cache/... 또는 dev clone 경로)"
fi

# ── 4. CRLF 검사 (Windows 특이 이슈) ──────────────────────
echo
echo "[4] CRLF 줄바꿈 검사 (Windows에서 깨질 수 있음)"
if [ -n "$FOUND_INSTALL" ] && [ -f "$STATUSLINE" ]; then
  if head -1 "$STATUSLINE" 2>/dev/null | grep -q $'\r'; then
    err "statusline.sh에 CRLF 잔존 — 다음 세션 시작 시 자동 복구되거나 수동 명령:"
    echo "       cd \"$FOUND_INSTALL\" && git config core.autocrlf false && git rm --cached -r . && git reset --hard"
  else
    ok "shebang LF 정상"
  fi
fi

# ── 5. Claude Code settings.json statusLine 등록 ─────────
echo
echo "[5] Claude Code settings.json"
SETTINGS="$HOME/.claude/settings.json"
if [ ! -f "$SETTINGS" ]; then
  warn "$SETTINGS 없음 — Claude Code 설치/사용 흔적 없음"
else
  REGISTERED=$(grep -o '"command":[[:space:]]*"[^"]*"' "$SETTINGS" 2>/dev/null \
    | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  if [ -z "$REGISTERED" ]; then
    warn "statusLine 미등록 — Claude Code 재시작 시 forge-glow plugin이 자동 등록 시도"
  elif echo "$REGISTERED" | grep -q "forge-glow"; then
    ok "statusLine 등록됨: $REGISTERED"
    if [ ! -x "$REGISTERED" ]; then
      err "  └─ 그러나 등록된 경로에 실행 가능한 파일 없음 — settings.json 정리 필요"
    fi
  else
    warn "다른 도구의 statusLine 등록됨: $REGISTERED"
    echo "       (forge-glow는 자동 wrap 시도 — 그래도 안 보이면 수동 교체)"
  fi
fi

# ── 6. statusline.sh 실제 실행 (실데이터 모방) ─────────────
echo
echo "[6] statusline.sh 실제 실행"
if [ -n "$FOUND_INSTALL" ] && [ -x "$STATUSLINE" ]; then
  TEST_STDIN='{"session_id":"diag","cwd":"'"$PWD"'","model":{"display_name":"Opus 4.7","id":"claude-opus-4-7"},"workspace":{"project_dir":"'"$PWD"'"},"cost":{"total_cost_usd":0.5,"total_duration_ms":1800000},"context_window":{"used_percentage":35}}'
  OUTPUT=$(echo "$TEST_STDIN" | bash "$STATUSLINE" 2>&1)
  EXIT=$?
  if [ "$EXIT" -eq 0 ] && [ -n "$OUTPUT" ]; then
    ok "정상 실행 (exit 0):"
    echo "$OUTPUT" | sed 's/^/      /'
  else
    err "실행 실패 (exit $EXIT):"
    echo "$OUTPUT" | sed 's/^/      /'
  fi
fi

# ── 7. 종합 ────────────────────────────────────────────────
echo
echo "═══════════════════════════════════════════════════════════════"
if [ "$ISSUES" -eq 0 ]; then
  echo "  ✅ 모두 정상. statusLine이 안 보이면 다음 세션 재시작 후 입력 대기(❯) 화면 확인."
else
  echo "  ⚠️  $ISSUES 개 이슈 발견. 위 메시지의 해결 명령 참조."
  echo
  echo "  잘 모르겠으면 이 출력을 그대로 복사해 보내주세요."
fi
echo "═══════════════════════════════════════════════════════════════"

exit "$ISSUES"
