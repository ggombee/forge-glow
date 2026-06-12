#!/usr/bin/env bash
# forge-glow parity harness (Option C Phase 0 deliverable)
#
# Proves the Claude spine — LINE1/LINE2/LINE3 — renders BYTE-IDENTICAL across every
# Option-C change, with all FORGE_* flags at defaults and NO active Codex session.
# This is the merge gate that must be green before any edit to a live spine file.
#
# Isolation for determinism:
#   - CODEX_HOME → empty temp dir  → Codex panel off (so parse-codex.sh internals can't
#     affect the spine; the codex segment is gated on G_CODEX_AVAILABLE && G_CODEX_TURNS>0)
#   - CLAUDE_CODE_ENABLE_TELEMETRY=0 → L5 OTel off
#   - fixtures point cwd at a fixed non-git temp dir → no git-branch noise
#
# Usage:
#   run.sh           # check against golden/ (exit 1 on any mismatch)
#   run.sh update    # regenerate golden/ from current HUD output
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUD="$DIR/../../hud/statusline.sh"
FIX="$DIR/fixtures"
GOLD="$DIR/golden"
MODE="${1:-check}"

TMP_CODEX="$(mktemp -d)"
mkdir -p "$TMP_CODEX/sessions"
mkdir -p /tmp/forge-parity
# transcript 픽스처(.jsonl)는 stdin 픽스처가 /tmp/forge-parity 절대경로로 참조 — 고정 위치로 스테이징
cp "$FIX"/*.jsonl /tmp/forge-parity/ 2>/dev/null || true
trap 'rm -rf "$TMP_CODEX"' EXIT

mkdir -p "$GOLD"
fail=0

for f in "$FIX"/*.json; do
  [ -f "$f" ] || continue
  name="$(basename "$f" .json)"
  # CODE_FORGE_BIN=/usr/bin/true → 실행 가능하지만 status --json 출력이 비어 forge 패널 결정적 off
  #   (캐시의 실제 bin/forge가 살아있는 프로젝트의 route.json을 읽어오는 누수 차단 — 2026-06-12 발견)
  # FORGE_GLOW_GATE_LAST=0 → Claude 세션 settings.json env(=1)가 셸에 주입돼도 flags-off 보장
  out="$(CODEX_HOME="$TMP_CODEX" CLAUDE_CODE_ENABLE_TELEMETRY=0 CODE_FORGE_BIN=/usr/bin/true FORGE_GLOW_GATE_LAST=0 bash "$HUD" < "$f" 2>/dev/null)"
  if [ "$MODE" = "update" ]; then
    printf '%s\n' "$out" > "$GOLD/$name.txt"
    echo "updated golden: $name"
  else
    if diff -q <(printf '%s\n' "$out") "$GOLD/$name.txt" >/dev/null 2>&1; then
      echo "✓ parity: $name"
    else
      echo "✗ PARITY FAIL: $name"
      diff <(printf '%s\n' "$out") "$GOLD/$name.txt" || true
      fail=1
    fi
  fi
done

[ "$MODE" = "update" ] && { echo "golden regenerated."; exit 0; }
[ "$fail" -eq 0 ] && echo "ALL PARITY GREEN" || echo "PARITY BROKEN — spine output changed"
exit "$fail"
