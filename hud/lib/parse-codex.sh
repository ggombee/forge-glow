#!/usr/bin/env bash
# forge-glow — parse-codex.sh
# Codex CLI 세션 JSONL 파싱 (~/.codex/sessions/**/*.jsonl)
# shellcheck disable=SC2034  # G_CODEX_* 변수들은 statusline.sh가 sourcing 후 사용
#
# 활성 세션 감지: mtime이 가장 최근인 JSONL을 현재 세션으로 간주 (5분 이내만).
# usage 필드 소스:
#   - turn.completed 이벤트의 .usage.input_tokens / cached_input_tokens / output_tokens
#     → 공식 이벤트별 usage (2026 Q1+ 표준). 누적 아닌 개별값.
#   - token_count 이벤트: 컨텍스트 표시용 fallback (Windows 버그 영향 받음)

parse_codex() {
  G_CODEX_AVAILABLE=false
  G_CODEX_MODEL=""
  G_CODEX_COST=""
  G_CODEX_TURNS=0
  G_CODEX_CACHE_HIT_PCT=""
  G_CODEX_CTX_PCT=""

  local codex_dir="${CODEX_HOME:-$HOME/.codex}"
  [ ! -d "$codex_dir/sessions" ] && return

  # 최근 5분 이내 수정된 jsonl 1개 (활성 세션)
  local session_file
  session_file=$(find "$codex_dir/sessions" -name "*.jsonl" -type f -mmin -5 -print0 2>/dev/null \
    | xargs -0 stat -f "%m %N" 2>/dev/null \
    | sort -rn | head -1 | awk '{print $2}')

  [ -z "$session_file" ] || [ ! -f "$session_file" ] && return

  G_CODEX_AVAILABLE=true

  # turn_context.model (가장 최근 값)
  G_CODEX_MODEL=$(tail -100 "$session_file" 2>/dev/null \
    | jq -r 'select(.type == "turn_context") | .model // empty' 2>/dev/null \
    | tail -1)

  # turn.completed.usage 집계 (최근 200줄)
  local usage_data
  usage_data=$(tail -200 "$session_file" 2>/dev/null \
    | jq -rs '
      [ .[] | select(.type == "turn.completed") |
        {
          input: (.usage.input_tokens // 0),
          cached: (.usage.cached_input_tokens // 0),
          output: (.usage.output_tokens // 0)
        }
      ] |
      {
        total_input: ([.[].input] | add // 0),
        total_cached: ([.[].cached] | add // 0),
        total_output: ([.[].output] | add // 0),
        turns: length
      } |
      "\(.total_input) \(.total_cached) \(.total_output) \(.turns)"
    ' 2>/dev/null)

  if [ -n "$usage_data" ]; then
    local inp cached out turns
    inp=$(echo "$usage_data" | awk '{print $1}')
    cached=$(echo "$usage_data" | awk '{print $2}')
    out=$(echo "$usage_data" | awk '{print $3}')
    turns=$(echo "$usage_data" | awk '{print $4}')

    G_CODEX_TURNS="${turns:-0}"

    # 모델별 가격 (OpenAI Codex 주력 모델 기준, $/MTok)
    # 참고: 정확 가격은 OpenAI pricing 페이지. 여기선 대표값만.
    local inp_price=3 out_price=15 cached_price=1.5
    case "$G_CODEX_MODEL" in
      *gpt-5*|*o5*)         inp_price=5;  out_price=25; cached_price=2.5 ;;
      *o3*)                 inp_price=10; out_price=40; cached_price=5 ;;
      *o4-mini*|*mini*)     inp_price=1;  out_price=4;  cached_price=0.5 ;;
      *gpt-4.1*|*4.1*)      inp_price=3;  out_price=15; cached_price=1.5 ;;
    esac

    G_CODEX_COST=$(awk -v i="$inp" -v c="$cached" -v o="$out" \
      -v ip="$inp_price" -v op="$out_price" -v cp="$cached_price" \
      'BEGIN{ printf "%.2f", (i*ip + o*op + c*cp) / 1000000 }')

    # 캐시 히트율
    if [ "${inp:-0}" -gt 0 ] 2>/dev/null; then
      G_CODEX_CACHE_HIT_PCT=$(awk -v c="$cached" -v i="$inp" \
        'BEGIN{ if (i+c > 0) printf "%.0f", (c/(i+c))*100; else print 0 }')
    fi
  fi

  # 컨텍스트 % — token_count 이벤트 최신값 (Windows에서 누락 가능)
  local ctx
  ctx=$(tail -50 "$session_file" 2>/dev/null \
    | jq -r 'select(.type == "token_count") |
        if .model_context_window and .model_context_window > 0 then
          ((.count // 0) / .model_context_window * 100 | floor)
        else empty end' 2>/dev/null \
    | tail -1)
  [ -n "$ctx" ] && G_CODEX_CTX_PCT="$ctx"
}
