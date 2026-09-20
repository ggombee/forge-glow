#!/usr/bin/env bash
# Verify that every distributable surface describes the same forge-glow release.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  FAILURES=$((FAILURES + 1))
}

command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required" >&2
  exit 1
}

CLAUDE_MANIFEST="$ROOT/.claude-plugin/plugin.json"
CLAUDE_MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
CODEX_MANIFEST="$ROOT/plugins/forge-glow/.codex-plugin/plugin.json"
CODEX_MARKETPLACE="$ROOT/.agents/plugins/marketplace.json"
CODEX_SKILL="$ROOT/plugins/forge-glow/skills/forge-glow-statusline/SKILL.md"

for file in \
  "$CLAUDE_MANIFEST" \
  "$CLAUDE_MARKETPLACE" \
  "$CODEX_MANIFEST" \
  "$CODEX_MARKETPLACE"; do
  if [ ! -f "$file" ]; then
    fail "missing ${file#"$ROOT"/}"
    continue
  fi
  jq empty "$file" >/dev/null 2>&1 || fail "invalid JSON: ${file#"$ROOT"/}"
done

CLAUDE_VERSION=$(jq -r '.version // empty' "$CLAUDE_MANIFEST")
CODEX_VERSION=$(jq -r '.version // empty' "$CODEX_MANIFEST")
STATS_VERSION=$(sed -n 's/^version = "\([^"]*\)"/\1/p' "$ROOT/stats/pyproject.toml" | head -1)
PYTHON_VERSION=$(sed -n 's/^__version__ = "\([^"]*\)"/\1/p' \
  "$ROOT/stats/src/forge_glow_stats/__init__.py" | head -1)

if [ -z "$CLAUDE_VERSION" ]; then
  fail ".claude-plugin/plugin.json has no version"
fi
for pair in \
  "Codex plugin:$CODEX_VERSION" \
  "Python package:$STATS_VERSION" \
  "Python runtime:$PYTHON_VERSION"; do
  label=${pair%%:*}
  value=${pair#*:}
  if [ "$value" != "$CLAUDE_VERSION" ]; then
    fail "$label version '$value' != Claude plugin '$CLAUDE_VERSION'"
  fi
done

grep -Fq "/tags/v${CLAUDE_VERSION}.tar.gz" "$ROOT/Formula/forge-glow.rb" \
  || fail "Homebrew Formula URL does not use v$CLAUDE_VERSION"

jq -e '
  .name == "forge-glow"
  and any(.plugins[]?;
    .name == "forge-glow"
    and .source == "./")
' "$CLAUDE_MARKETPLACE" >/dev/null \
  || fail "Claude marketplace does not point at its repository root"

jq -e '
  .name == "forge-glow"
  and any(.plugins[]?;
    .name == "forge-glow"
    and .source.source == "local"
    and .source.path == "./plugins/forge-glow")
' "$CODEX_MARKETPLACE" >/dev/null \
  || fail "Codex marketplace does not point at ./plugins/forge-glow"

grep -Fq 'status_line = ["model-with-reasoning", "context-remaining", "five-hour-limit", "weekly-limit", "current-dir", "git-branch", "fast-mode"]' \
  "$CODEX_SKILL" \
  || fail "Codex status line must place context and limits immediately after the model"

grep -Fq 'status_line_use_colors = true' "$CODEX_SKILL" \
  || fail "Codex status line must keep native theme colors enabled"

if [ -n "${GITHUB_REF_NAME:-}" ] && [[ "$GITHUB_REF_NAME" == v* ]]; then
  if [ "$GITHUB_REF_NAME" != "v$CLAUDE_VERSION" ]; then
    fail "tag '$GITHUB_REF_NAME' != manifest version 'v$CLAUDE_VERSION'"
  fi
fi

if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi

printf 'RELEASE CHECK GREEN: v%s\n' "$CLAUDE_VERSION"
