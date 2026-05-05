#!/usr/bin/env bash
# forge-glow — parse-stdin.sh
# L1: statusLine stdin JSON 파싱
# shellcheck disable=SC2034  # G_* 변수들은 statusline.sh가 sourcing 후 사용
#
# 견고성:
#   - eval 패턴 제거 → mapfile로 인덱스 할당 (word splitting / 공백 / 특수문자 무영향)
#   - jq 미설치: 기본값 유지 + G_MODEL에 "(jq missing)" 표시
#   - bc 미설치: 시간당 비용만 0으로 표시. 나머지 정상
#   - Windows Git Bash 호환 (mapfile은 bash 4.0+ 표준)

parse_stdin() {
  local json="$1"

  # 모든 G_* 변수 선제 초기화 (안전망)
  G_MODEL="?"; G_MODEL_ID="?"
  G_COST="0"; G_DURATION_MS="0"; G_API_DURATION_MS="0"
  G_LINES_ADD="0"; G_LINES_DEL="0"
  G_CTX_PCT="0"; G_CTX_REMAIN="0"; G_CTX_SIZE="200000"
  G_CTX_INPUT="0"; G_CTX_OUTPUT="0"
  G_CACHE_READ="0"; G_CACHE_CREATE="0"
  G_RATE_5H=""; G_RATE_7D=""
  G_CWD=""; G_PROJECT_DIR=""; G_SESSION_ID=""
  G_TRANSCRIPT=""; G_VERSION=""; G_AGENT=""; G_WORKTREE=""

  # jq 미설치 — Windows에서 흔함. 안내 표시 후 git 브랜치만 추출하고 종료.
  if ! command -v jq >/dev/null 2>&1; then
    G_MODEL="(jq missing — install: choco/scoop/brew install jq)"
    _extract_project_and_branch
    return
  fi

  # jq 1회 호출, 줄바꿈 구분 출력 → while read로 안전하게 받기.
  # mapfile은 bash 4+ 한정이라 macOS 기본 3.2 / 구형 환경에서 안 됨.
  # while read는 bash 3.x도 OK. 빈 필드도 빈 문자열로 정확히 보존.
  local jq_out
  jq_out=$(jq -r '
    [
      (.model.display_name // "?"),
      (.model.id // "?"),
      ((.cost.total_cost_usd // 0) | tostring),
      ((.cost.total_duration_ms // 0) | tostring),
      ((.cost.total_api_duration_ms // 0) | tostring),
      ((.cost.total_lines_added // 0) | tostring),
      ((.cost.total_lines_removed // 0) | tostring),
      ((.context_window.used_percentage // 0) | tostring),
      ((.context_window.remaining_percentage // 0) | tostring),
      ((.context_window.context_window_size // 200000) | tostring),
      ((.context_window.total_input_tokens // 0) | tostring),
      ((.context_window.total_output_tokens // 0) | tostring),
      ((.context_window.current_usage.cache_read_input_tokens // 0) | tostring),
      ((.context_window.current_usage.cache_creation_input_tokens // 0) | tostring),
      ((.rate_limits.five_hour.used_percentage // "") | tostring),
      ((.rate_limits.seven_day.used_percentage // "") | tostring),
      (.cwd // ""),
      (.workspace.project_dir // ""),
      (.session_id // ""),
      (.transcript_path // ""),
      (.version // ""),
      (.agent.name // ""),
      (.worktree.name // "")
    ] | .[]
  ' 2>/dev/null <<< "$json")

  if [ -z "$jq_out" ]; then
    # jq 파싱 실패 — 기본값 유지
    _extract_project_and_branch
    return
  fi

  local -a V=()
  local line
  while IFS= read -r line; do
    V+=("$line")
  done <<< "$jq_out"

  # 인덱스 기반 할당 (eval 없음 → 모델명 'Opus 4.7' 등 공백 안전)
  G_MODEL="${V[0]:-?}"
  G_MODEL_ID="${V[1]:-?}"
  G_COST="${V[2]:-0}"
  G_DURATION_MS="${V[3]:-0}"
  G_API_DURATION_MS="${V[4]:-0}"
  G_LINES_ADD="${V[5]:-0}"
  G_LINES_DEL="${V[6]:-0}"
  G_CTX_PCT="${V[7]:-0}"
  G_CTX_REMAIN="${V[8]:-0}"
  G_CTX_SIZE="${V[9]:-200000}"
  G_CTX_INPUT="${V[10]:-0}"
  G_CTX_OUTPUT="${V[11]:-0}"
  G_CACHE_READ="${V[12]:-0}"
  G_CACHE_CREATE="${V[13]:-0}"
  G_RATE_5H="${V[14]:-}"
  G_RATE_7D="${V[15]:-}"
  G_CWD="${V[16]:-}"
  G_PROJECT_DIR="${V[17]:-}"
  G_SESSION_ID="${V[18]:-}"
  G_TRANSCRIPT="${V[19]:-}"
  G_VERSION="${V[20]:-}"
  G_AGENT="${V[21]:-}"
  G_WORKTREE="${V[22]:-}"

  _extract_project_and_branch
  _calc_cost_per_hour
  G_CTX_PCT_INT=$(printf "%.0f" "$G_CTX_PCT" 2>/dev/null || echo "0")
}

# 프로젝트명 + git 브랜치 추출 (jq 의존 없음)
_extract_project_and_branch() {
  if [ -n "$G_PROJECT_DIR" ]; then
    G_PROJECT_NAME=$(basename "$G_PROJECT_DIR")
  elif [ -n "$G_CWD" ]; then
    G_PROJECT_NAME=$(basename "$G_CWD" 2>/dev/null || echo "?")
  else
    G_PROJECT_NAME="?"
  fi

  G_BRANCH=""
  if [ -d "${G_PROJECT_DIR:-.}/.git" ]; then
    G_BRANCH=$(git -C "${G_PROJECT_DIR:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null)
  fi

  G_CTX_PCT_INT=$(printf "%.0f" "${G_CTX_PCT:-0}" 2>/dev/null || echo "0")
}

# 시간당 비용 계산 (bc 의존, Windows에서 없을 수 있음)
_calc_cost_per_hour() {
  G_COST_PER_HOUR="0"
  if ! command -v bc >/dev/null 2>&1; then
    return  # bc 없으면 스킵 — 나머지는 정상 표시
  fi
  if [ "$G_DURATION_MS" -gt 0 ] 2>/dev/null; then
    local hours
    hours=$(echo "scale=4; $G_DURATION_MS / 3600000" | bc -l 2>/dev/null)
    if [ -n "$hours" ] && echo "$hours > 0" | bc -l 2>/dev/null | grep -q 1; then
      G_COST_PER_HOUR=$(printf "%.2f" "$(echo "scale=4; $G_COST / $hours" | bc -l 2>/dev/null)" 2>/dev/null || echo "0")
    fi
  fi
}
