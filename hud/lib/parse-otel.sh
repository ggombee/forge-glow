#!/usr/bin/env bash
# forge-glow — parse-otel.sh
# L5: Claude Code OTel 이벤트 파싱 (가장 정확한 메트릭 소스)
# shellcheck disable=SC2034  # G_OTEL_* 변수들은 statusline.sh가 sourcing 후 사용
#
# 환경변수:
#   FORGE_GLOW_OTEL_LOG — OTLP file exporter 출력 경로 (설정 시 L5 활성)
#                        기본값: $HOME/.forge-glow/otel.log
#
# 소비 이벤트:
#   claude_code.api_request   — model, duration_ms, input/output_tokens, cache_read_tokens, cost_usd
#   claude_code.tool_result   — tool_name, duration_ms, success
#
# L5가 활성이면 L2 transcript 파싱의 모델별 비용/캐시 히트율을 대체 (더 정확).
# L5 없으면 L2/L3 fallback — 이 함수는 조용히 빈 값 반환.

parse_otel() {
  G_OTEL_AVAILABLE=false
  G_OTEL_MODEL_COSTS=""
  G_OTEL_CACHE_HIT_PCT=""
  G_OTEL_AVG_DURATION=""
  G_OTEL_TOOL_SUCCESS_PCT=""

  local log_file="${FORGE_GLOW_OTEL_LOG:-$HOME/.forge-glow/otel.log}"
  [ ! -f "$log_file" ] && return

  # 최근 500줄만 소비 (성능 + 오래된 세션 영향 최소화)
  local recent
  recent=$(tail -500 "$log_file" 2>/dev/null)
  [ -z "$recent" ] && return

  G_OTEL_AVAILABLE=true

  # ── claude_code.api_request 집계 ───────────────────────────
  # OTel file exporter는 이벤트당 한 줄 JSON. attributes.* 에서 값 추출.
  local api_data
  api_data=$(echo "$recent" | jq -rs '
    [ .[] | select(.name == "claude_code.api_request") |
      {
        model: (.attributes.model // "unknown"),
        duration_ms: (.attributes.duration_ms // 0),
        input: (.attributes.input_tokens // 0),
        output: (.attributes.output_tokens // 0),
        cache_read: (.attributes.cache_read_tokens // 0),
        cost: (.attributes.cost_usd // 0)
      }
    ] | .[] | "\(.model) \(.duration_ms) \(.input) \(.output) \(.cache_read) \(.cost)"
  ' 2>/dev/null)

  if [ -n "$api_data" ]; then
    # 모델별 비용 집계 (Anthropic이 이미 계산한 cost_usd 직접 사용)
    local result
    result=$(echo "$api_data" | awk '
    {
      m=$1; dur=$2; inp=$3; out=$4; cr=$5; cost=$6

      short=m
      if (m ~ /opus/) short="opus"
      else if (m ~ /sonnet/) short="sonnet"
      else if (m ~ /haiku/) short="haiku"

      model_cost[short] += cost
      total_duration += dur
      total_input += inp + cr
      total_cache_read += cr
      total_requests++
    }
    END {
      for (s in model_cost) {
        if (model_cost[s] > 0.001) printf "%s:$%.2f ", s, model_cost[s]
      }
      printf "\n"
      if (total_input > 0) printf "%.0f\n", (total_cache_read / total_input) * 100
      else printf "0\n"
      if (total_requests > 0) printf "%d\n", total_duration / total_requests
      else printf "0\n"
    }')

    G_OTEL_MODEL_COSTS=$(echo "$result" | sed -n '1p')
    G_OTEL_CACHE_HIT_PCT=$(echo "$result" | sed -n '2p')
    G_OTEL_AVG_DURATION=$(echo "$result" | sed -n '3p')
  fi

  # ── claude_code.tool_result 집계 ───────────────────────────
  local tool_stats
  tool_stats=$(echo "$recent" | jq -rs '
    [ .[] | select(.name == "claude_code.tool_result") |
      (.attributes.success // false)
    ] |
    {
      total: length,
      success: ([.[] | select(.)] | length)
    } |
    "\(.success) \(.total)"
  ' 2>/dev/null)

  if [ -n "$tool_stats" ]; then
    local success total
    success=$(echo "$tool_stats" | awk '{print $1}')
    total=$(echo "$tool_stats" | awk '{print $2}')
    if [ "${total:-0}" -gt 0 ] 2>/dev/null; then
      G_OTEL_TOOL_SUCCESS_PCT=$(awk -v s="$success" -v t="$total" 'BEGIN{printf "%.0f", (s/t)*100}')
    fi
  fi
}
