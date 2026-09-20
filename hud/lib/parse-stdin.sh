#!/usr/bin/env bash
# forge-glow — parse-stdin.sh
# 현재 Claude statusLine stdin JSON 파싱
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
  G_MODEL="?"
  G_COST="0"; G_COST_PER_HOUR="0"; G_DURATION_MS="0"
  G_LINES_ADD="0"; G_LINES_DEL="0"
  G_CTX_PCT="0"
  G_RATE_5H=""; G_RATE_7D=""
  G_CWD=""; G_PROJECT_DIR=""; G_SESSION_ID=""
  G_TRANSCRIPT=""; G_AGENT=""
  # Claude Code v2.1.153+는 status line 프로세스에 실제 터미널 폭을 환경변수로 준다.
  G_COLUMNS="${COLUMNS:-0}"

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
      ((.cost.total_cost_usd // 0) | tostring),
      ((.cost.total_duration_ms // 0) | tostring),
      ((.cost.total_lines_added // 0) | tostring),
      ((.cost.total_lines_removed // 0) | tostring),
      ((.context_window.used_percentage // 0) | tostring),
      ((.rate_limits.five_hour.used_percentage // "") | tostring),
      ((.rate_limits.seven_day.used_percentage // "") | tostring),
      (.workspace.current_dir // .cwd // ""),
      (.workspace.project_dir // ""),
      (.session_id // ""),
      (.transcript_path // ""),
      (.agent.name // "")
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
  G_COST="${V[1]:-0}"
  G_DURATION_MS="${V[2]:-0}"
  G_LINES_ADD="${V[3]:-0}"
  G_LINES_DEL="${V[4]:-0}"
  G_CTX_PCT="${V[5]:-0}"
  G_RATE_5H="${V[6]:-}"
  G_RATE_7D="${V[7]:-}"
  G_CWD="${V[8]:-}"
  G_PROJECT_DIR="${V[9]:-}"
  G_SESSION_ID="${V[10]:-}"
  G_TRANSCRIPT="${V[11]:-}"
  G_AGENT="${V[12]:-}"

  _extract_project_and_branch
  _calc_cost_per_hour
  G_CTX_PCT_INT=$(printf "%.0f" "$G_CTX_PCT" 2>/dev/null || echo "0")
}

# 프로젝트명 + git 브랜치 추출 (jq 의존 없음)
#
# 우선순위:
#   1. CWD(현재 작업 turn의 디렉터리)에서 git toplevel 탐지 → 그 레포가 진짜 작업 대상
#   2. 실패 시 PROJECT_DIR(claude 시작 디렉터리)에서 git toplevel 탐지
#   3. 둘 다 git 레포 아니면 디렉터리명만 표시 (브랜치 없음)
#
# 효과:
#   ~/work에서 claude 켜고 cd ~/work/repo-a 후 작업 → repo-a 정확 인식
#   ~/work에서 claude 켜고 cd ~/work/repo-b 후 작업 → repo-b 정확 인식
#   서브 디렉터리(~/work/repo-a/src/...)에서도 toplevel 자동 탐지
_extract_project_and_branch() {
  local repo_root=""

  # 1순위: 현재 cwd에서 git toplevel
  if [ -n "$G_CWD" ] && [ -d "$G_CWD" ]; then
    repo_root=$(git -C "$G_CWD" rev-parse --show-toplevel 2>/dev/null)
  fi

  # 2순위: project_dir에서 git toplevel
  if [ -z "$repo_root" ] && [ -n "$G_PROJECT_DIR" ] && [ -d "$G_PROJECT_DIR" ]; then
    repo_root=$(git -C "$G_PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)
  fi

  if [ -n "$repo_root" ]; then
    G_PROJECT_NAME=$(basename "$repo_root")
    G_BRANCH=$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null)
  else
    # git 레포 아님 — 디렉터리명만 (cwd 우선, 없으면 project_dir, 그것도 없으면 ?)
    if [ -n "$G_CWD" ]; then
      G_PROJECT_NAME=$(basename "$G_CWD" 2>/dev/null || echo "?")
    elif [ -n "$G_PROJECT_DIR" ]; then
      G_PROJECT_NAME=$(basename "$G_PROJECT_DIR" 2>/dev/null || echo "?")
    else
      G_PROJECT_NAME="?"
    fi
    G_BRANCH=""
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
