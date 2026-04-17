#!/usr/bin/env bash
# forge-glow — parse-transcript.sh
# L2: transcript.jsonl 파싱 — 도구 활동, 서브에이전트, 모델별 비용, 캐시 히트율

parse_transcript() {
  local transcript="$1"

  G_TOOL_SUMMARY=""
  G_SUBAGENT=""
  G_MODEL_COSTS=""
  G_CACHE_HIT_PCT=""

  [ -z "$transcript" ] || [ ! -f "$transcript" ] && return

  # 도구 사용 집계 (최근 200줄)
  G_TOOL_SUMMARY=$(tail -200 "$transcript" 2>/dev/null \
    | jq -r 'select(.type=="tool_use") | .name // empty' 2>/dev/null \
    | sort | uniq -c | sort -rn | head -5 \
    | awk '{printf "%s×%s ", $2, $1}' 2>/dev/null)

  # 서브에이전트 실행 감지 (최근 50줄에서 시작했는데 끝 안 난 것)
  local agent_starts agent_stops
  agent_starts=$(tail -50 "$transcript" 2>/dev/null \
    | jq -r 'select(.type=="agent_start") | .name // empty' 2>/dev/null)
  agent_stops=$(tail -50 "$transcript" 2>/dev/null \
    | jq -r 'select(.type=="agent_stop") | .name // empty' 2>/dev/null)

  if [ -n "$agent_starts" ]; then
    # 시작됐지만 끝나지 않은 에이전트 찾기
    local running=""
    while IFS= read -r name; do
      if ! echo "$agent_stops" | grep -q "$name"; then
        running="$name"
        break
      fi
    done <<< "$agent_starts"
    G_SUBAGENT="$running"
  fi

  # 모델별 비용 + 캐시 히트율 (최근 500줄)
  local model_data
  model_data=$(tail -500 "$transcript" 2>/dev/null \
    | jq -r 'select(.type=="assistant" and .message.usage) |
      .message | "\(.model // "unknown") \(.usage.input_tokens // 0) \(.usage.output_tokens // 0) \(.usage.cache_read_input_tokens // 0) \(.usage.cache_creation_input_tokens // 0)"' 2>/dev/null)

  # 낭비 감지 (최근 20개 도구 호출 분석)
  G_WASTE_WARN=""
  local recent_tools
  recent_tools=$(tail -100 "$transcript" 2>/dev/null \
    | jq -r 'select(.type=="tool_use") | "\(.name) \(.model // "unknown")"' 2>/dev/null \
    | tail -20)

  if [ -n "$recent_tools" ]; then
    # opus에서 Read 5회 연속 → haiku 권장
    local opus_reads
    opus_reads=$(echo "$recent_tools" | grep -E "Read.*opus" | wc -l | tr -d ' ')
    if [ "$opus_reads" -ge 5 ]; then
      G_WASTE_WARN="opus Read ${opus_reads}회 — haiku 전환 권장"
    fi

    # Read 결과 2000+ 토큰 빈발 → Grep 추천
    local big_reads
    big_reads=$(tail -50 "$transcript" 2>/dev/null \
      | jq -r 'select(.type=="tool_result" and .content) | .content | length' 2>/dev/null \
      | awk '$1 > 2000 {c++} END {print c+0}')
    if [ "$big_reads" -ge 3 ] && [ -z "$G_WASTE_WARN" ]; then
      G_WASTE_WARN="대용량 Read ${big_reads}회 — Grep 추천"
    fi
  fi

  # 캐시 miss 연속 감지 (최근 3턴 모두 cache_read=0이면 경고)
  local cache_misses
  cache_misses=$(tail -100 "$transcript" 2>/dev/null \
    | jq -r 'select(.type=="assistant" and .message.usage) | .message.usage.cache_read_input_tokens // 0' 2>/dev/null \
    | tail -3 | awk '$1 == 0 {c++} END {print c+0}')
  if [ "$cache_misses" -ge 3 ] && [ -z "$G_WASTE_WARN" ]; then
    G_WASTE_WARN="cache miss 3턴 연속 — /compact 타이밍 조정"
  fi

  if [ -n "$model_data" ]; then
    # 모델별 비용 계산 + 캐시 히트율
    local result
    result=$(echo "$model_data" | awk '
    {
      m=$1; inp=$2; out=$3; cr=$4; cc=$5
      # 모델별 가격 ($/MTok)
      if (m ~ /opus/)       { ip=5; op=25; crp=0.5; ccp=6.25 }
      else if (m ~ /haiku/) { ip=1; op=5; crp=0.1; ccp=1.25 }
      else                  { ip=3; op=15; crp=0.3; ccp=3.75 }

      # 짧은 모델명
      short=m
      if (m ~ /opus/) short="opus"
      else if (m ~ /sonnet/) short="sonnet"
      else if (m ~ /haiku/) short="haiku"

      cost[short] += (inp*ip + out*op + cr*crp + cc*ccp) / 1000000
      total_cache_read += cr
      total_input += inp + cr + cc
    }
    END {
      # 모델별 비용
      for (s in cost) {
        if (cost[s] > 0.001) printf "%s:$%.2f ", s, cost[s]
      }
      printf "\n"
      # 캐시 히트율
      if (total_input > 0) printf "%.0f", (total_cache_read / total_input) * 100
      else printf "0"
    }')

    G_MODEL_COSTS=$(echo "$result" | head -1)
    G_CACHE_HIT_PCT=$(echo "$result" | tail -1)
  fi
}