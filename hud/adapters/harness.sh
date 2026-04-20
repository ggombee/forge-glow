#!/usr/bin/env bash
# forge-glow adapter — claude-code-harness
# https://github.com/anthropic-labs/claude-code-harness
#
# 감지: $CLAUDE_HARNESS_HOME 또는 ~/.claude-harness/ 디렉터리
# 출력: Harness 세션 수 + 활성 브랜치

HARNESS_DIR="${CLAUDE_HARNESS_HOME:-$HOME/.claude-harness}"
[ ! -d "$HARNESS_DIR" ] && exit 0

VERSION=""
if [ -f "$HARNESS_DIR/VERSION" ]; then
  VERSION=$(head -1 "$HARNESS_DIR/VERSION" 2>/dev/null | tr -d ' \n')
fi

# 활성 세션 수 (sessions/ 하위 jsonl 중 5분 이내 수정)
SESSIONS=0
if [ -d "$HARNESS_DIR/sessions" ]; then
  SESSIONS=$(find "$HARNESS_DIR/sessions" -name "*.jsonl" -mmin -5 -type f 2>/dev/null | wc -l | tr -d ' ')
fi

OUT="⚙️  harness"
[ -n "$VERSION" ] && OUT="${OUT} v${VERSION}"
[ "$SESSIONS" -gt 0 ] 2>/dev/null && OUT="${OUT} ${SESSIONS}세션"

echo "$OUT"
