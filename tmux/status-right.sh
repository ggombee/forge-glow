#!/usr/bin/env bash
# forge-glow tmux — status-right.sh
# 현재 pane의 Codex 계정 표식과 Claude/Codex의 전역 최근 활동 여부를 표시한다.
# 계정 표식은 launcher가 pane option으로 넘긴 값만 사용한다. 세션 로그를 추측하지 않는다.

set -uo pipefail

PANE_ID="${1:-}"
PANE_COMMAND="${2:-${FORGE_GLOW_PANE_COMMAND:-}}"
CODEX_ACCOUNT="${FORGE_GLOW_CODEX_ACCOUNT:-}"

has_recent_jsonl() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  [ -n "$(find "$dir" -type f -name '*.jsonl' -mmin -5 -print -quit 2>/dev/null)" ]
}

CLAUDE_DIR="$HOME/.claude/projects"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}/sessions"
OUTPUT=""

if [ -z "$CODEX_ACCOUNT" ] && [ -n "$PANE_ID" ] && command -v tmux >/dev/null 2>&1; then
  CODEX_ACCOUNT="$(tmux show-options -p -v -t "$PANE_ID" \
    @forge_glow_codex_account 2>/dev/null || true)"
fi

CODEX_ACCOUNT_LABEL=""
case "$CODEX_ACCOUNT" in
  personal) CODEX_ACCOUNT_LABEL="개인" ;;
  company) CODEX_ACCOUNT_LABEL="회사" ;;
esac

case "$PANE_COMMAND" in
  codex*)
    if [ -n "$CODEX_ACCOUNT_LABEL" ]; then
      OUTPUT="👤 codex:${CODEX_ACCOUNT_LABEL}"
    fi
    ;;
esac

if [ -z "$OUTPUT" ] && has_recent_jsonl "$CODEX_DIR"; then
  OUTPUT="🌐 codex active (native status line 참조)"
fi
if has_recent_jsonl "$CLAUDE_DIR"; then
  [ -n "$OUTPUT" ] && OUTPUT+="  "
  OUTPUT+="🧠 claude active (statusLine 참조)"
fi

printf '%s\n' "$OUTPUT"

exit 0
