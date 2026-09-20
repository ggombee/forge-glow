#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════╗
# ║  forge-glow — Real-time efficiency HUD           ║
# ║  "대장장이는 불빛 색으로 철의 상태를 읽는다"       ║
# ╚══════════════════════════════════════════════════╝
#
# 기본: 현재 Claude 세션의 statusLine stdin + transcript.jsonl
# 선택: OTel logs file exporter
# OTel은 현재 session.id의 모델별 비용 추정/캐시 히트율을 보강한다.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ====== 라이브러리 로드 ======
source "$SCRIPT_DIR/lib/render.sh"
source "$SCRIPT_DIR/lib/parse-stdin.sh"
source "$SCRIPT_DIR/lib/parse-transcript.sh"
source "$SCRIPT_DIR/lib/parse-otel.sh"
source "$SCRIPT_DIR/lib/parse-update.sh"
source "$SCRIPT_DIR/lib/alerts.sh"

# ====== stdin JSON 읽기 ======
STDIN_JSON=$(cat)

# ====== 현재 Claude 세션 stdin ======
parse_stdin "$STDIN_JSON"

# ====== 현재 Claude 세션 transcript ======
parse_transcript "$G_TRANSCRIPT"

# ====== OTel 이벤트 (opt-in, session.id로 격리) ======
parse_otel "$G_SESSION_ID"

# ====== 자동 업데이트 가용 flag ======
parse_update

# ====== 실시간 알림 감지 (Slack webhook opt-in) ======
detect_alerts

# 현재 세션 OTel 이벤트가 있으면 transcript 근사값을 보강한다.
if [ "$G_OTEL_AVAILABLE" = true ]; then
  [ -n "$G_OTEL_MODEL_COSTS" ] && G_MODEL_COSTS="$G_OTEL_MODEL_COSTS"
  [ -n "$G_OTEL_CACHE_HIT_PCT" ] && G_CACHE_HIT_PCT="$G_OTEL_CACHE_HIT_PCT"
fi

# ====== 1줄째: 모델 + 프로젝트 + 비용 ======
LINE1=""

# 모델
if [ -n "$G_AGENT" ]; then
  LINE1="🧠 ${G_MODEL} → 🔍 ${G_AGENT} 실행중"
else
  LINE1="🧠 ${G_MODEL}"
fi

# 프로젝트/브랜치
LINE1+="  📁 ${G_PROJECT_NAME}"
[ -n "$G_BRANCH" ] && LINE1+="/${G_BRANCH}"

# 비용 (stdin 원값은 소수 10자리+ — 표시만 둘째 자리 반올림, 계산엔 원값 유지)
# FORGE_GLOW_COST=0 → 비용 표시 전체 off (구독제 사용자는 API 환산 참고치일 뿐 —
# 실질 게이지는 ⏱ rate limit. 기본은 on: 종량제 사용자에겐 실비)
if [ "${FORGE_GLOW_COST:-1}" != "0" ]; then
  COST_ICON=$(cost_indicator "$G_COST_PER_HOUR")
  COST_FMT=$(printf "%.2f" "$G_COST" 2>/dev/null || echo "$G_COST")
  LINE1+="  ${COST_ICON} ~\$${COST_FMT}"
  if [ "$G_COST_PER_HOUR" != "0" ] && [ -n "$G_COST_PER_HOUR" ]; then
    LINE1+=" (~\$${G_COST_PER_HOUR}/h avg)"
  fi
fi

# ====== 2줄째: 컨텍스트 바 + 코드 변경 + 도구/캐시 ======
CTX_ICON=$(context_indicator "$G_CTX_PCT_INT")
CTX_BAR_WIDTH=20
if [ "${G_COLUMNS:-0}" -gt 0 ] 2>/dev/null && [ "${G_COLUMNS:-0}" -lt 100 ] 2>/dev/null; then
  CTX_BAR_WIDTH=10
fi
CTX_BAR=$(progress_bar "$G_CTX_PCT_INT" "$CTX_BAR_WIDTH")

LINE2="${CTX_ICON} ${G_CTX_PCT_INT}% [${CTX_BAR}]"

# 코드 변경량
if [ "$G_LINES_ADD" -gt 0 ] 2>/dev/null || [ "$G_LINES_DEL" -gt 0 ] 2>/dev/null; then
  LINE2+="  📝 +${G_LINES_ADD} -${G_LINES_DEL}"
fi

# 최근 transcript 도구 활동
if [ -n "$G_TOOL_SUMMARY" ]; then
  LINE2+="  🔧 ${G_TOOL_SUMMARY}"
fi

# ====== 3줄째: 모델별 비용 추정 + 캐시 + rate limit ======
LINE3=""

# 모델별 비용 분리 (transcript/OTel 추정) — FORGE_GLOW_COST=0이면 함께 off
if [ -n "$G_MODEL_COSTS" ] && [ "${FORGE_GLOW_COST:-1}" != "0" ]; then
  LINE3+="📊 ~${G_MODEL_COSTS}"
fi

# 캐시 히트율
if [ -n "$G_CACHE_HIT_PCT" ] && [ "$G_CACHE_HIT_PCT" != "0" ]; then
  CACHE_DISP=$(cache_display "$G_CACHE_HIT_PCT")
  LINE3+=" ${CACHE_DISP}"
fi

# Rate limit (경고가 3줄째를 교체해도 보존)
RATE_5H=$(rate_limit_display "$G_RATE_5H" "5h")
RATE_7D=$(rate_limit_display "$G_RATE_7D" "7d")
RATE_TOKEN=""
if [ -n "$RATE_5H" ] || [ -n "$RATE_7D" ]; then
  RATE_TOKEN="⏱ ${RATE_5H}"
  [ -n "$RATE_7D" ] && RATE_TOKEN+=" ${RATE_7D}"
  LINE3+="  ${RATE_TOKEN}"
fi

# ====== 경고 동적 전환 (3줄째 교체) ======
# 우선순위: G_ALERT_TEXT (임계) > G_UPDATE_AVAILABLE (업데이트)
if [ -n "$G_ALERT_TEXT" ]; then
  LINE3="${G_ALERT_TEXT}"
elif [ -n "$G_UPDATE_AVAILABLE" ]; then
  LINE3="${G_UPDATE_AVAILABLE}"
fi
# 경고가 3줄째를 교체해도 rate limit 토큰은 보존한다.
if [ -n "$RATE_TOKEN" ] && [[ "$LINE3" != *"$RATE_TOKEN"* ]]; then
  LINE3+="  ${RATE_TOKEN}"
fi

# ====== 출력 ======
echo -e "$LINE1"
echo -e "$LINE2"
[ -n "$LINE3" ] && echo -e "$LINE3"

exit 0
