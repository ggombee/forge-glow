#!/usr/bin/env bash
# forge-glow adapter — everything-claude-code (ECC)
# https://github.com/everything-claude-code/everything-claude-code
#
# 감지: ~/.claude/ecc/ 디렉터리 또는 ~/.claude/plugins/cache/**/ecc/ 존재
# 출력: ECC 활성 프로필 1줄

ECC_DIR="$HOME/.claude/ecc"
if [ ! -d "$ECC_DIR" ]; then
  # 플러그인 캐시 후보
  FOUND=$(find "$HOME/.claude/plugins/cache" -maxdepth 3 -type d -name "everything-claude-code*" 2>/dev/null | head -1)
  [ -z "$FOUND" ] && exit 0
  ECC_DIR="$FOUND"
fi

VERSION=""
if [ -f "$ECC_DIR/VERSION" ]; then
  VERSION=$(head -1 "$ECC_DIR/VERSION" 2>/dev/null | tr -d ' \n')
elif [ -f "$ECC_DIR/.claude-plugin/plugin.json" ]; then
  VERSION=$(grep -o '"version":[[:space:]]*"[^"]*"' "$ECC_DIR/.claude-plugin/plugin.json" 2>/dev/null \
    | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
fi

PROFILE=""
if [ -f "$ECC_DIR/active-profile" ]; then
  PROFILE=$(head -1 "$ECC_DIR/active-profile" 2>/dev/null | tr -d ' \n')
fi

OUT="🌐 ECC"
[ -n "$VERSION" ] && OUT="${OUT} v${VERSION}"
[ -n "$PROFILE" ] && OUT="${OUT}:${PROFILE}"

echo "$OUT"
