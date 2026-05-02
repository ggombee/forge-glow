#!/usr/bin/env bash
# forge-glow — parse-stdin.sh
# L1: statusLine stdin JSON 파싱 (단일 jq 호출)
# shellcheck disable=SC2034  # G_* 변수들은 statusline.sh가 sourcing 후 사용

parse_stdin() {
  local json="$1"

  # 모든 G_ 변수 선제 초기화 (set -u 방어 + jq 실패 시 안전망)
  G_MODEL="?"; G_MODEL_ID="?"
  G_COST="0"; G_DURATION_MS="0"; G_API_DURATION_MS="0"
  G_LINES_ADD="0"; G_LINES_DEL="0"
  G_CTX_PCT="0"; G_CTX_REMAIN="0"; G_CTX_SIZE="200000"
  G_CTX_INPUT="0"; G_CTX_OUTPUT="0"
  G_CACHE_READ="0"; G_CACHE_CREATE="0"
  G_RATE_5H=""; G_RATE_7D=""
  G_CWD=""; G_PROJECT_DIR=""; G_SESSION_ID=""
  G_TRANSCRIPT=""; G_VERSION=""; G_AGENT=""; G_WORKTREE=""

  # jq @sh 필터로 각 값을 single-quote 처리 → 모델명 'Opus 4.7' 같은 공백 안전.
  # eval 패턴 유지하되 모든 값이 quoted라 word splitting 없음.
  eval "$(echo "$json" | jq -r '
    "G_MODEL=" + ((.model.display_name // "?") | @sh),
    "G_MODEL_ID=" + ((.model.id // "?") | @sh),
    "G_COST=" + ((.cost.total_cost_usd // 0) | tostring | @sh),
    "G_DURATION_MS=" + ((.cost.total_duration_ms // 0) | tostring | @sh),
    "G_API_DURATION_MS=" + ((.cost.total_api_duration_ms // 0) | tostring | @sh),
    "G_LINES_ADD=" + ((.cost.total_lines_added // 0) | tostring | @sh),
    "G_LINES_DEL=" + ((.cost.total_lines_removed // 0) | tostring | @sh),
    "G_CTX_PCT=" + ((.context_window.used_percentage // 0) | tostring | @sh),
    "G_CTX_REMAIN=" + ((.context_window.remaining_percentage // 0) | tostring | @sh),
    "G_CTX_SIZE=" + ((.context_window.context_window_size // 200000) | tostring | @sh),
    "G_CTX_INPUT=" + ((.context_window.total_input_tokens // 0) | tostring | @sh),
    "G_CTX_OUTPUT=" + ((.context_window.total_output_tokens // 0) | tostring | @sh),
    "G_CACHE_READ=" + ((.context_window.current_usage.cache_read_input_tokens // 0) | tostring | @sh),
    "G_CACHE_CREATE=" + ((.context_window.current_usage.cache_creation_input_tokens // 0) | tostring | @sh),
    "G_RATE_5H=" + ((.rate_limits.five_hour.used_percentage // "") | tostring | @sh),
    "G_RATE_7D=" + ((.rate_limits.seven_day.used_percentage // "") | tostring | @sh),
    "G_CWD=" + ((.cwd // "") | @sh),
    "G_PROJECT_DIR=" + ((.workspace.project_dir // "") | @sh),
    "G_SESSION_ID=" + ((.session_id // "") | @sh),
    "G_TRANSCRIPT=" + ((.transcript_path // "") | @sh),
    "G_VERSION=" + ((.version // "") | @sh),
    "G_AGENT=" + ((.agent.name // "") | @sh),
    "G_WORKTREE=" + ((.worktree.name // "") | @sh)
  ' 2>/dev/null)"

  # 프로젝트명 + 브랜치 추출
  if [ -n "$G_PROJECT_DIR" ]; then
    G_PROJECT_NAME=$(basename "$G_PROJECT_DIR")
  else
    G_PROJECT_NAME=$(basename "$G_CWD" 2>/dev/null || echo "?")
  fi

  # Git 브랜치 (가볍게)
  G_BRANCH=""
  if [ -d "${G_PROJECT_DIR:-.}/.git" ]; then
    G_BRANCH=$(git -C "${G_PROJECT_DIR:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null)
  fi

  # 시간당 비용 계산
  G_COST_PER_HOUR="0"
  if [ "$G_DURATION_MS" -gt 0 ] 2>/dev/null; then
    local hours
    hours=$(echo "scale=4; $G_DURATION_MS / 3600000" | bc -l 2>/dev/null)
    if [ -n "$hours" ] && echo "$hours > 0" | bc -l 2>/dev/null | grep -q 1; then
      G_COST_PER_HOUR=$(printf "%.2f" "$(echo "scale=4; $G_COST / $hours" | bc -l 2>/dev/null)" 2>/dev/null || echo "0")
    fi
  fi

  # 컨텍스트 % 정수화
  G_CTX_PCT_INT=$(printf "%.0f" "$G_CTX_PCT" 2>/dev/null || echo "0")
}