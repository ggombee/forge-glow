#!/usr/bin/env bash
# forge-glow — render.sh
# 프로그레스바, 색상, 이모지 렌더링 유틸리티
# shellcheck disable=SC2034  # 색상 상수 일부는 예약(추후 사용)

# ANSI 색상
C_RESET=$'\033[0m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_ORANGE=$'\033[38;5;208m'
C_RED=$'\033[31m'
C_GRAY=$'\033[90m'
C_CYAN=$'\033[36m'
C_WHITE=$'\033[37m'

# 컨텍스트 % → 이모지 + 색상
context_indicator() {
  local pct=$1
  if [ "$pct" -ge 84 ]; then
    echo "♻️"
  elif [ "$pct" -ge 80 ]; then
    echo "💀"
  elif [ "$pct" -ge 70 ]; then
    echo "🔥"
  elif [ "$pct" -ge 50 ]; then
    echo "⚠️"
  else
    echo "🧊"
  fi
}

context_color() {
  local pct=$1
  if [ "$pct" -ge 80 ]; then
    echo "$C_RED"
  elif [ "$pct" -ge 70 ]; then
    echo "$C_ORANGE"
  elif [ "$pct" -ge 50 ]; then
    echo "$C_YELLOW"
  else
    echo "$C_GREEN"
  fi
}

# 프로그레스바 렌더링 (20칸)
progress_bar() {
  local pct=$1
  local width=20
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local color
  color=$(context_color "$pct")

  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done

  echo "${color}${bar}${C_RESET}"
}

# 비용 이모지
cost_indicator() {
  local cost_per_hour=$1
  # bc로 부동소수 비교
  if echo "$cost_per_hour >= 5.0" | bc -l 2>/dev/null | grep -q 1; then
    echo "🚨"
  elif echo "$cost_per_hour >= 2.0" | bc -l 2>/dev/null | grep -q 1; then
    echo "💸"
  else
    echo "💰"
  fi
}

# rate limit 표시
rate_limit_display() {
  local pct=$1
  local label=$2
  if [ -z "$pct" ] || [ "$pct" = "null" ]; then
    return
  fi
  local icon=""
  local rounded
  rounded=$(printf "%.0f" "$pct" 2>/dev/null || echo "$pct")
  if [ "$rounded" -ge 80 ] 2>/dev/null; then
    icon="🔴"
  elif [ "$rounded" -ge 60 ] 2>/dev/null; then
    icon="⚠️"
  fi
  echo "${label}:${icon}${rounded}%"
}

# 캐시 히트율 표시
cache_display() {
  local pct=$1
  if [ -z "$pct" ] || [ "$pct" = "0" ]; then
    return
  fi
  local color="$C_GREEN"
  if [ "$pct" -lt 40 ] 2>/dev/null; then
    color="$C_RED"
  elif [ "$pct" -lt 70 ] 2>/dev/null; then
    color="$C_YELLOW"
  fi
  echo "📊 ${color}cache:${pct}%${C_RESET}"
}