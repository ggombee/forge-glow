#!/usr/bin/env bash
# forge-glow tmux — status-right.sh
# Claude Code + Codex CLI 최근 활성 세션을 tmux 하단바(status-right)에 표시.
# shellcheck disable=SC2034  # G_CODEX_* 변수들은 parse-codex.sh가 설정, 이 파일이 소비
#
# 사용법: ~/.tmux.conf에 아래 추가
#   set -g status-right-length 150
#   set -g status-right "#(/path/to/forge-glow/tmux/status-right.sh)"
#
# 출력: 1줄. 두 도구 중 최근 활성된 걸 우선 (mtime 기준 5분 이내).
# 실패 시 빈 문자열 (tmux가 status-right를 공백으로 표시).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUD_DIR="$SCRIPT_DIR/../hud"

# ── 최근 활성 도구 감지 (mtime 5분 이내) ──────────────────
detect_latest() {
  local claude_dir="$HOME/.claude/projects"
  local codex_dir="${CODEX_HOME:-$HOME/.codex}/sessions"

  local claude_mtime=0 codex_mtime=0

  if [ -d "$claude_dir" ]; then
    claude_mtime=$(find "$claude_dir" -name "*.jsonl" -mmin -5 -type f -print0 2>/dev/null \
      | xargs -0 stat -f "%m" 2>/dev/null | sort -rn | head -1)
    claude_mtime="${claude_mtime:-0}"
  fi

  if [ -d "$codex_dir" ]; then
    codex_mtime=$(find "$codex_dir" -name "*.jsonl" -mmin -5 -type f -print0 2>/dev/null \
      | xargs -0 stat -f "%m" 2>/dev/null | sort -rn | head -1)
    codex_mtime="${codex_mtime:-0}"
  fi

  if [ "$claude_mtime" -gt "$codex_mtime" ]; then
    echo "claude"
  elif [ "$codex_mtime" -gt 0 ]; then
    echo "codex"
  else
    echo ""
  fi
}

# ── Codex 정보만 출력 (Claude Code는 statusLine API 사용 권장) ──
render_codex() {
  # parse-codex.sh 직접 로드해서 값만 뽑기
  # shellcheck disable=SC1091
  source "$HUD_DIR/lib/parse-codex.sh"
  parse_codex

  [ "$G_CODEX_AVAILABLE" != "true" ] && return

  local out="🤖 codex"
  [ -n "$G_CODEX_MODEL" ] && out="${out}:${G_CODEX_MODEL}"
  [ -n "$G_CODEX_COST" ] && out="${out} \$${G_CODEX_COST}"
  [ -n "$G_CODEX_CTX_PCT" ] && out="${out} ctx:${G_CODEX_CTX_PCT}%"
  [ "${G_CODEX_TURNS:-0}" -gt 0 ] && out="${out} turns:${G_CODEX_TURNS}"

  echo "$out"
}

# ── 메인 ──────────────────────────────────────────────────
LATEST=$(detect_latest)

case "$LATEST" in
  codex)
    render_codex
    ;;
  claude)
    # Claude Code는 자체 statusLine을 쓰므로 tmux엔 간단 표시만
    echo "🧠 claude (statusLine 참조)"
    ;;
  *)
    # 최근 활동 없음
    echo ""
    ;;
esac
