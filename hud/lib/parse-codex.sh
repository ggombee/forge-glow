#!/usr/bin/env bash
# forge-glow — parse-codex.sh
# Codex CLI 세션 JSONL 파싱 (~/.codex/sessions/**/*.jsonl)
# shellcheck disable=SC2034  # G_CODEX_* 변수들은 statusline.sh가 sourcing 후 사용
#
# 활성 세션 감지: mtime이 가장 최근인 JSONL을 현재 세션으로 간주 (5분 이내만).
# 검증된 on-disk 스키마 (2026-06, code-forge/docs/contracts/event-schema.md §3 Codex 매핑):
#   - 모델  : .type=="turn_context" 의 .payload.model  (verbatim — gpt-5.x 버전 드리프트하므로 리터럴 핀 금지)
#   - usage : .payload.type=="token_count" 의 .payload.info.total_token_usage (누적값 — 마지막 1건만, 합산 금지)
#             {input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens, total_tokens}
#   - ctx % : .payload.info.model_context_window 로 (total_tokens / window) 계산
#   ⚠ 과거 코드는 .type=="turn.completed" / .model / .count 를 봤으나 그 스키마는 디스크에 존재하지 않음(0건) → 패널이 항상 비어 있었음.
#
# 스파인 안전: 이 함수는 G_CODEX_* 를 진입 즉시 전부 초기화하고 모든 외부 호출을 2>/dev/null 로 감싼다.
#   → set -uo pipefail 하에서도 abort 불가. statusline.sh 는 추가로 `parse_codex || true` 로 호출.

parse_codex() {
  G_CODEX_AVAILABLE=false
  G_CODEX_MODEL=""
  G_CODEX_COST=""
  G_CODEX_TURNS=0
  G_CODEX_CACHE_HIT_PCT=""
  G_CODEX_CTX_PCT=""

  local codex_dir="${CODEX_HOME:-$HOME/.codex}"
  [ ! -d "$codex_dir/sessions" ] && return 0
  command -v jq >/dev/null 2>&1 || return 0

  # 최근 5분 이내 수정된 jsonl 중 가장 최근(활성 세션).
  # ls -t 로 mtime 정렬 → BSD/GNU/Git-Bash 모두 호환 (stat -f 의 BSD 전용 문제 제거, MM-10).
  local recent
  recent=$(find "$codex_dir/sessions" -name "*.jsonl" -type f -mmin -5 2>/dev/null)
  [ -z "$recent" ] && return 0
  local session_file
  session_file=$(printf '%s\n' "$recent" | tr '\n' '\0' | xargs -0 ls -t 2>/dev/null | head -1)
  { [ -z "$session_file" ] || [ ! -f "$session_file" ]; } && return 0

  G_CODEX_AVAILABLE=true

  # 모델: 최근 turn_context 의 .payload.model (verbatim)
  G_CODEX_MODEL=$(tail -200 "$session_file" 2>/dev/null \
    | jq -r 'select(.type == "turn_context") | .payload.model // empty' 2>/dev/null \
    | tail -1)

  # usage: 마지막 token_count 의 누적 total_token_usage (합산 X — last 만; issue-#950 91× 오버카운트 방지)
  local usage_data
  usage_data=$(tail -400 "$session_file" 2>/dev/null \
    | jq -rs '
      [ .[] | select(.payload.type == "token_count") | .payload.info.total_token_usage ]
      | last // {}
      | "\(.input_tokens // 0) \(.cached_input_tokens // 0) \(.output_tokens // 0) \(.total_tokens // 0)"
    ' 2>/dev/null)

  # turns 게이트용: token_count 이벤트 개수 (>0 이면 활성으로 표시)
  local turns
  turns=$(tail -400 "$session_file" 2>/dev/null \
    | jq -rs '[ .[] | select(.payload.type == "token_count") ] | length' 2>/dev/null)
  G_CODEX_TURNS="${turns:-0}"

  if [ -n "$usage_data" ]; then
    local inp cached out
    inp=$(echo "$usage_data" | awk '{print $1}')
    cached=$(echo "$usage_data" | awk '{print $2}')
    out=$(echo "$usage_data" | awk '{print $3}')

    # 모델별 대표 가격 ($/MTok). 데이터 기반 단일 소스화는 MM-6(Phase 2).
    local inp_price=3 out_price=15 cached_price=1.5
    case "$G_CODEX_MODEL" in
      *gpt-5*|*o5*)      inp_price=5;  out_price=25; cached_price=2.5 ;;
      *o3*)              inp_price=10; out_price=40; cached_price=5 ;;
      *o4-mini*|*mini*)  inp_price=1;  out_price=4;  cached_price=0.5 ;;
      *gpt-4.1*|*4.1*)   inp_price=3;  out_price=15; cached_price=1.5 ;;
    esac

    G_CODEX_COST=$(awk -v i="${inp:-0}" -v c="${cached:-0}" -v o="${out:-0}" \
      -v ip="$inp_price" -v op="$out_price" -v cp="$cached_price" \
      'BEGIN{ printf "%.2f", (i*ip + o*op + c*cp) / 1000000 }')

    if [ "${inp:-0}" -gt 0 ] 2>/dev/null; then
      G_CODEX_CACHE_HIT_PCT=$(awk -v c="${cached:-0}" -v i="${inp:-0}" \
        'BEGIN{ if (i+c > 0) printf "%.0f", (c/(i+c))*100; else print 0 }')
    fi
  fi

  # 컨텍스트 %: 마지막 token_count 의 last_token_usage(input+cached) / model_context_window
  # ⚠ total_token_usage 는 세션 누적(compaction 시 윈도우 초과 → 폭주)이라 점유율에 부적합.
  #    현재 점유는 마지막 턴의 input(+cached) 으로 계산.
  local ctx
  ctx=$(tail -400 "$session_file" 2>/dev/null \
    | jq -rs '
      [ .[] | select(.payload.type == "token_count") | .payload.info
        | select(.model_context_window and .model_context_window > 0)
        | ( ((.last_token_usage.input_tokens // 0) + (.last_token_usage.cached_input_tokens // 0))
            / .model_context_window * 100 | floor) ]
      | last // empty
    ' 2>/dev/null)
  [ -n "$ctx" ] && G_CODEX_CTX_PCT="$ctx"
}
