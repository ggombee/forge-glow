#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════╗
# ║  forge-glow — Real-time efficiency HUD           ║
# ║  "대장장이는 불빛 색으로 철의 상태를 읽는다"       ║
# ╚══════════════════════════════════════════════════╝
#
# L1: stdin JSON (모든 사용자)
# L2: transcript.jsonl (모든 사용자)
# L3: code-forge usage.jsonl (code-forge 사용자)
# L4: adapters/ (OMC, ECC 등)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ====== 라이브러리 로드 ======
source "$SCRIPT_DIR/lib/render.sh"
source "$SCRIPT_DIR/lib/parse-stdin.sh"
source "$SCRIPT_DIR/lib/parse-transcript.sh"
source "$SCRIPT_DIR/lib/parse-forge.sh"

# ====== stdin JSON 읽기 ======
STDIN_JSON=$(cat)

# ====== L1: stdin 파싱 ======
parse_stdin "$STDIN_JSON"

# ====== L2: transcript 파싱 ======
parse_transcript "$G_TRANSCRIPT"

# ====== L3: code-forge 파싱 ======
parse_forge "$G_SESSION_ID"

# ====== 1줄째: 모델 + 프로젝트 + 비용 ======
LINE1=""

# 모델
if [ -n "$G_AGENT" ]; then
  LINE1="🧠 ${G_MODEL} → 🔍 ${G_AGENT} 실행중"
elif [ -n "$G_SUBAGENT" ]; then
  LINE1="🧠 ${G_MODEL} → 🔍 ${G_SUBAGENT} 실행중"
else
  LINE1="🧠 ${G_MODEL}"
fi

# 프로젝트/브랜치
LINE1+="  📁 ${G_PROJECT_NAME}"
[ -n "$G_BRANCH" ] && LINE1+="/${G_BRANCH}"

# 비용
COST_ICON=$(cost_indicator "$G_COST_PER_HOUR")
LINE1+="  ${COST_ICON} \$${G_COST}"
if [ "$G_COST_PER_HOUR" != "0" ] && [ -n "$G_COST_PER_HOUR" ]; then
  LINE1+=" (\$${G_COST_PER_HOUR}/h)"
fi

# ====== 2줄째: 컨텍스트 바 + 코드 변경 + 도구/캐시 ======
CTX_ICON=$(context_indicator "$G_CTX_PCT_INT")
CTX_BAR=$(progress_bar "$G_CTX_PCT_INT")

LINE2="${CTX_ICON} ${G_CTX_PCT_INT}% [${CTX_BAR}]"

# 코드 변경량
if [ "$G_LINES_ADD" -gt 0 ] 2>/dev/null || [ "$G_LINES_DEL" -gt 0 ] 2>/dev/null; then
  LINE2+="  📝 +${G_LINES_ADD} -${G_LINES_DEL}"
fi

# 도구 활동 (L2)
if [ -n "$G_TOOL_SUMMARY" ]; then
  LINE2+="  🔧 ${G_TOOL_SUMMARY}"
fi

# ====== 3줄째: 모델별 비용 + 캐시 + rate limit + forge 메트릭 ======
LINE3=""

# 모델별 비용 분리 (L2)
if [ -n "$G_MODEL_COSTS" ]; then
  LINE3+="📊 ${G_MODEL_COSTS}"
fi

# 캐시 히트율 (L2)
if [ -n "$G_CACHE_HIT_PCT" ] && [ "$G_CACHE_HIT_PCT" != "0" ]; then
  CACHE_DISP=$(cache_display "$G_CACHE_HIT_PCT")
  LINE3+=" ${CACHE_DISP}"
fi

# code-forge 에이전트/스킬/게이트 (L3)
if [ "$G_FORGE_AVAILABLE" = true ]; then
  if [ -n "$G_FORGE_AGENTS" ] || [ -n "$G_FORGE_SKILLS" ]; then
    LINE3+="  🔨 ${G_FORGE_AGENTS}${G_FORGE_SKILLS}"
  fi
  if [ -n "$G_FORGE_GATE" ]; then
    LINE3+="  ✅ ${G_FORGE_GATE}"
  fi
fi

# Rate limit
RATE_5H=$(rate_limit_display "$G_RATE_5H" "5h")
RATE_7D=$(rate_limit_display "$G_RATE_7D" "7d")
if [ -n "$RATE_5H" ] || [ -n "$RATE_7D" ]; then
  LINE3+="  ⏱ ${RATE_5H}"
  [ -n "$RATE_7D" ] && LINE3+=" ${RATE_7D}"
fi

# ====== 어댑터 실행 (L4) ======
if [ -d "$SCRIPT_DIR/adapters" ]; then
  for adapter in "$SCRIPT_DIR/adapters"/*.sh; do
    [ -f "$adapter" ] && [ -x "$adapter" ] && {
      ADAPTER_OUT=$("$adapter" 2>/dev/null || true)
      [ -n "$ADAPTER_OUT" ] && LINE3+="  ${ADAPTER_OUT}"
    }
  done
fi

# ====== 출력 ======
echo -e "$LINE1"
echo -e "$LINE2"
[ -n "$LINE3" ] && echo -e "$LINE3"

exit 0