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
# L5: OTel file exporter (opt-in, CLAUDE_CODE_ENABLE_TELEMETRY=1)
#     — L5 활성 시 L2의 모델별 비용/캐시 히트율을 정확값으로 덮어쓰기

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ====== 라이브러리 로드 ======
source "$SCRIPT_DIR/lib/render.sh"
source "$SCRIPT_DIR/lib/parse-stdin.sh"
source "$SCRIPT_DIR/lib/parse-transcript.sh"
source "$SCRIPT_DIR/lib/parse-forge.sh"
source "$SCRIPT_DIR/lib/parse-routing.sh"
source "$SCRIPT_DIR/lib/parse-otel.sh"
source "$SCRIPT_DIR/lib/parse-codex.sh"
source "$SCRIPT_DIR/lib/parse-update.sh"
source "$SCRIPT_DIR/lib/alerts.sh"

# ====== stdin JSON 읽기 ======
STDIN_JSON=$(cat)

# ====== L1: stdin 파싱 ======
parse_stdin "$STDIN_JSON"

# ====== L2: transcript 파싱 ======
parse_transcript "$G_TRANSCRIPT"

# ====== L3: code-forge 파싱 ======
parse_forge "$G_SESSION_ID"
# L3.5: route.json 스냅샷 (parse_forge가 공유한 JSON 재사용 — 추가 호출 없음)
parse_routing

# ====== L5: OTel 파싱 (opt-in, 가장 정확) ======
parse_otel

# ====== Codex CLI 병렬 세션 감지 ======
# 스파인 가드: Codex 파서 결함이 Codex 패널만 비우고 HUD 전체 렌더를 중단시키지 않도록.
# (parse_codex 는 G_CODEX_* 를 진입 즉시 초기화 + 모든 외부호출 2>/dev/null → set -u abort 불가)
parse_codex || true

# ====== 자동 업데이트 가용 flag ======
parse_update

# ====== 실시간 알림 감지 (Slack webhook opt-in) ======
detect_alerts

# L5 활성 시 L2 근사값을 정확값으로 덮어쓰기
if [ "$G_OTEL_AVAILABLE" = true ]; then
  [ -n "$G_OTEL_MODEL_COSTS" ] && G_MODEL_COSTS="$G_OTEL_MODEL_COSTS"
  [ -n "$G_OTEL_CACHE_HIT_PCT" ] && G_CACHE_HIT_PCT="$G_OTEL_CACHE_HIT_PCT"
fi

# ====== 1줄째: 모델 + 프로젝트 + 비용 ======
LINE1=""

# 모델
if [ -n "$G_AGENT" ]; then
  LINE1="🧠 ${G_MODEL} → 🔍 ${G_AGENT} 실행중"
elif [ -n "$G_SUBAGENT" ]; then
  LINE1="🧠 ${G_MODEL} → 🔍 ${G_SUBAGENT} 실행중"
else
  LINE1="🧠 ${G_MODEL}"
  # FORGE_GLOW_VERSION_TAG=1: route.json model_version(verbatim, 표시 전용 — event-schema §5)을 병기 — 기본 off
  # 메인 모델 단독 표시일 때만 — 에이전트 실행 표시 뒤에 붙으면 서브에이전트 버전으로 오독됨
  if [ "${FORGE_GLOW_VERSION_TAG:-0}" = "1" ] && [ -n "${G_ROUTE_VERSION:-}" ]; then
    LINE1+=" (${G_ROUTE_VERSION})"
  fi
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
  LINE1+="  ${COST_ICON} \$${COST_FMT}"
  if [ "$G_COST_PER_HOUR" != "0" ] && [ -n "$G_COST_PER_HOUR" ]; then
    LINE1+=" (\$${G_COST_PER_HOUR}/h)"
  fi
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

# 모델별 비용 분리 (L2) — FORGE_GLOW_COST=0이면 함께 off
if [ -n "$G_MODEL_COSTS" ] && [ "${FORGE_GLOW_COST:-1}" != "0" ]; then
  LINE3+="📊 ${G_MODEL_COSTS}"
fi

# 캐시 히트율 (L2)
if [ -n "$G_CACHE_HIT_PCT" ] && [ "$G_CACHE_HIT_PCT" != "0" ]; then
  CACHE_DISP=$(cache_display "$G_CACHE_HIT_PCT")
  LINE3+=" ${CACHE_DISP}"
fi

# code-forge 에이전트/스킬/게이트 (L3)
GATE_TOKEN=""
if [ "$G_FORGE_AVAILABLE" = true ]; then
  if [ -n "$G_FORGE_AGENTS" ] || [ -n "$G_FORGE_SKILLS" ]; then
    LINE3+="  🔨 ${G_FORGE_AGENTS}${G_FORGE_SKILLS}"
  fi
  # FORGE_GLOW_GATE_LAST=1: 누적 카운트 대신 "이번 턴 검증" 1건 표시 (route.json last_gate)
  if [ "${FORGE_GLOW_GATE_LAST:-0}" = "1" ] && [ -n "${G_ROUTE_GATE_STATUS:-}" ]; then
    case "$G_ROUTE_GATE_STATUS" in
      pass)    GATE_TOKEN="gate:✅" ;;
      fail)    GATE_TOKEN="gate:❌${G_ROUTE_GATE_BLOCKS:+(${G_ROUTE_GATE_BLOCKS})}" ;;
      skipped) GATE_TOKEN="gate:⏭" ;;
      *)       GATE_TOKEN="gate:${G_ROUTE_GATE_STATUS}" ;;
    esac
  fi
  if [ -n "$GATE_TOKEN" ]; then
    LINE3+="  ${GATE_TOKEN}"
  elif [ -n "$G_FORGE_GATE" ]; then
    LINE3+="  ✅ ${G_FORGE_GATE}"
  fi
fi

# FORGE_GLOW_SHOW_EFFORT=1: /start 복잡도→effort 권고 표시 (route.json, 권고 전용) — 기본 off
# gate/rate 토큰과 동일 패턴으로 조립 — 경고가 3줄째를 교체해도 보존
EFFORT_TOKEN=""
if [ "${FORGE_GLOW_SHOW_EFFORT:-0}" = "1" ] && [ -n "${G_ROUTE_EFFORT:-}" ]; then
  EFFORT_TOKEN="🎚 ${G_ROUTE_COMPLEXITY:+${G_ROUTE_COMPLEXITY}→}${G_ROUTE_EFFORT}"
  LINE3+="  ${EFFORT_TOKEN}"
fi

# Rate limit (토큰으로 조립 — 경고가 3줄째를 교체해도 보존하기 위해, gate 토큰과 동일 패턴)
RATE_5H=$(rate_limit_display "$G_RATE_5H" "5h")
RATE_7D=$(rate_limit_display "$G_RATE_7D" "7d")
RATE_TOKEN=""
if [ -n "$RATE_5H" ] || [ -n "$RATE_7D" ]; then
  RATE_TOKEN="⏱ ${RATE_5H}"
  [ -n "$RATE_7D" ] && RATE_TOKEN+=" ${RATE_7D}"
  LINE3+="  ${RATE_TOKEN}"
fi

# Codex 활성 세션 표시 (병렬 작업 중일 때)
if [ "$G_CODEX_AVAILABLE" = true ] && [ "${G_CODEX_TURNS:-0}" -gt 0 ] 2>/dev/null; then
  CODEX_DISP="🤖 codex"
  [ -n "$G_CODEX_MODEL" ] && CODEX_DISP="${CODEX_DISP}(${G_CODEX_MODEL})"
  [ -n "$G_CODEX_COST" ] && CODEX_DISP="${CODEX_DISP} \$${G_CODEX_COST}"
  [ -n "$G_CODEX_CTX_PCT" ] && CODEX_DISP="${CODEX_DISP} ctx:${G_CODEX_CTX_PCT}%"
  LINE3+="  ${CODEX_DISP}"
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

# ====== 경고 동적 전환 (3줄째 교체) ======
# 우선순위: G_ALERT_TEXT (임계) > G_WASTE_WARN (낭비) > G_UPDATE_AVAILABLE (업데이트)
if [ -n "$G_ALERT_TEXT" ]; then
  LINE3="${G_ALERT_TEXT}"
elif [ -n "$G_WASTE_WARN" ]; then
  LINE3="💡 ${G_WASTE_WARN}"
elif [ -n "$G_UPDATE_AVAILABLE" ]; then
  LINE3="${G_UPDATE_AVAILABLE}"
fi
# 경고가 3줄째를 교체해도 "이번 턴 검증"·rate limit 토큰은 보존 (없으면 빈 문자열 — 출력 무변화)
if [ -n "$RATE_TOKEN" ] && [[ "$LINE3" != *"$RATE_TOKEN"* ]]; then
  LINE3+="  ${RATE_TOKEN}"
fi
if [ -n "$GATE_TOKEN" ] && [[ "$LINE3" != *"$GATE_TOKEN"* ]]; then
  LINE3+="  ${GATE_TOKEN}"
fi
if [ -n "$EFFORT_TOKEN" ] && [[ "$LINE3" != *"$EFFORT_TOKEN"* ]]; then
  LINE3+="  ${EFFORT_TOKEN}"
fi

# ====== 출력 ======
echo -e "$LINE1"
echo -e "$LINE2"
[ -n "$LINE3" ] && echo -e "$LINE3"

exit 0