#!/usr/bin/env bash
# forge-glow HUD/parsers regression harness
#
# Claude spine(LINE1/LINE2/LINE3), transcript 스키마, 세션 격리를 회귀 검증한다.
#
# Isolation for determinism:
#   - CODEX_HOME → isolated temp dir → the host's Codex sessions cannot leak into tests
#   - OTel/state 경로 → isolated temp dir → 호스트 설정 영향 차단
#   - fixtures point cwd at a fixed non-git temp dir → no git-branch noise
#
# Usage:
#   run.sh           # check against golden/ (exit 1 on any mismatch)
#   run.sh update    # regenerate golden/ from current HUD output
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUD="$DIR/../../hud/statusline.sh"
TMUX_STATUS="$DIR/../../tmux/status-right.sh"
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
  # codex-* 픽스처는 CODEX_HOME=빈 디렉토리인 이 루프에서 제외 (아래 별도 블록에서 Codex 활성 스테이징)
  case "$name" in codex-*) continue ;; esac
  hud_columns=160
  [ "$name" = "claude-narrow" ] && hud_columns=80
  out="$(COLUMNS="$hud_columns" CODEX_HOME="$TMP_CODEX" \
    FORGE_GLOW_OTEL_LOG="$TMP_CODEX/no-otel.jsonl" \
    FORGE_GLOW_STATE_DIR="$TMP_CODEX/state" FORGE_GLOW_SLACK_WEBHOOK= \
    FORGE_GLOW_COST=1 bash "$HUD" < "$f" 2>/dev/null)"
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

# 가격표 회귀: Sonnet 5 표준가와 구형 Opus/Haiku를 서로 다른 단가로 계산한다.
pricing_out="$(bash -c '
  G_COLUMNS=160
  source "$1"
  parse_transcript "$2"
  printf "%s\n" "$G_MODEL_COSTS"
' _ "$DIR/../../hud/lib/parse-transcript.sh" "$FIX/pricing-transcript.jsonl" 2>/dev/null)"
if [ "$pricing_out" = "opus-4.1:\$90.00 sonnet-5:\$12.00 haiku-3.5:\$4.80 " ]; then
  echo "✓ parser: model pricing families"
else
  echo "✗ PRICING FAIL: got $pricing_out"
  fail=1
fi

# ── 세션 격리 parity ──
# 활성 Codex 로그가 있어도 Claude HUD는 Claude stdin 세션만 렌더해야 한다.
# 전역 "최근 Codex 세션"을 Claude 컨텍스트로 오인하는 회귀를 막는다.
CODEX_FIX="$FIX/codex-session.jsonl"
CODEX_STDIN="$FIX/codex-active.json"
if [ -f "$CODEX_FIX" ] && [ -f "$CODEX_STDIN" ]; then
  cp "$CODEX_FIX" "$TMP_CODEX/sessions/rollout-codex.jsonl"
  touch "$TMP_CODEX/sessions/rollout-codex.jsonl"
  out="$(COLUMNS=160 CODEX_HOME="$TMP_CODEX" \
    FORGE_GLOW_OTEL_LOG="$TMP_CODEX/no-otel.jsonl" \
    FORGE_GLOW_STATE_DIR="$TMP_CODEX/state" FORGE_GLOW_SLACK_WEBHOOK= \
    FORGE_GLOW_COST=1 bash "$HUD" < "$CODEX_STDIN" 2>/dev/null)"
  if [ "$MODE" = "update" ]; then
    printf '%s\n' "$out" > "$GOLD/codex-active.txt"
    echo "updated golden: codex-active"
  else
    if diff -q <(printf '%s\n' "$out") "$GOLD/codex-active.txt" >/dev/null 2>&1; then
      echo "✓ parity: session-isolation"
    else
      echo "✗ PARITY FAIL: session-isolation"
      diff <(printf '%s\n' "$out") "$GOLD/codex-active.txt" || true
      fail=1
    fi
  fi

  if printf '%s\n' "$out" | grep -q '🤖 codex'; then
    echo "✗ ISOLATION FAIL: Claude HUD leaked a Codex session"
    fail=1
  fi

fi

# tmux는 두 도구의 전역 활동 여부를 동시에 보이되 세션 값은 노출하지 않는다.
TMP_TMUX_HOME="$TMP_CODEX/tmux-home"
mkdir -p "$TMP_TMUX_HOME/.claude/projects"
cp "$FIX/fable-transcript.jsonl" "$TMP_TMUX_HOME/.claude/projects/claude.jsonl"
tmux_out="$(HOME="$TMP_TMUX_HOME" CODEX_HOME="$TMP_CODEX" bash "$TMUX_STATUS")"
expected_tmux='🌐 codex active (native status line 참조)  🧠 claude active (statusLine 참조)'
if [ "$tmux_out" = "$expected_tmux" ] && \
   ! printf '%s\n' "$tmux_out" | grep -Eq 'ctx:|\$[0-9]|turn'; then
  echo "✓ tmux: activity-only isolation"
else
  echo "✗ TMUX FAIL: $tmux_out"
  fail=1
fi

# launcher가 넘긴 pane 계정은 로그 추측 없이 foreground Codex에만 표시한다.
tmux_account_out="$(HOME="$TMP_TMUX_HOME" CODEX_HOME="$TMP_CODEX" \
  FORGE_GLOW_CODEX_ACCOUNT=personal FORGE_GLOW_PANE_COMMAND=codex \
  bash "$TMUX_STATUS")"
expected_tmux_account='👤 codex:개인  🧠 claude active (statusLine 참조)'
if [ "$tmux_account_out" = "$expected_tmux_account" ]; then
  echo "✓ tmux: pane-scoped Codex account badge"
else
  echo "✗ TMUX ACCOUNT FAIL: $tmux_account_out"
  fail=1
fi

# ── Claude OTel 세션 격리 ──
# OTel 추정값도 전역 로그를 합산하지 않고 현재 session.id만 소비해야 한다.
for OTEL_FIX in "$FIX/otel-mixed.jsonl" "$FIX/otel-otlp-mixed.jsonl"; do
  [ -f "$OTEL_FIX" ] || continue
  otel_out="$(FORGE_GLOW_OTEL_LOG="$OTEL_FIX" bash -c '
    source "$1"
    parse_otel "parity-test-session"
    printf "%s|%s\n" "$G_OTEL_MODEL_COSTS" "$G_OTEL_CACHE_HIT_PCT"
  ' _ "$DIR/../../hud/lib/parse-otel.sh" 2>/dev/null)"
  if [ "$otel_out" = "opus:\$1.25 |9" ]; then
    echo "✓ parser: Claude OTel session isolation ($(basename "$OTEL_FIX"))"
  else
    echo "✗ OTEL ISOLATION FAIL: expected opus:\$1.25 |9, got $otel_out"
    fail=1
  fi
done

# 깨진 stdin도 기본 HUD로 내려가야 하며 set -u로 중단되면 안 된다.
fallback_out="$(printf '{broken' | COLUMNS=80 \
  FORGE_GLOW_OTEL_LOG="$TMP_CODEX/no-otel.jsonl" \
  FORGE_GLOW_STATE_DIR="$TMP_CODEX/state" FORGE_GLOW_SLACK_WEBHOOK= \
  bash "$HUD" 2>/dev/null)"
if printf '%s\n' "$fallback_out" | grep -q '^🧠 ?  📁 ?  💰 ~\$0.00$'; then
  echo "✓ fallback: malformed stdin"
else
  echo "✗ FALLBACK FAIL: malformed stdin aborted or rendered unexpectedly"
  fail=1
fi

# ── Python 집계 파서 스키마 ──
# 대시보드도 nested tool_use와 message.id 중복 제거, OTLP envelope를 동일하게 읽어야 한다.
if command -v python3 >/dev/null 2>&1; then
  TMP_PROJECTS="$TMP_CODEX/claude-projects"
  mkdir -p "$TMP_PROJECTS"
  cp "$FIX/fable-transcript.jsonl" "$TMP_PROJECTS/session.jsonl"
  python_out="$(PYTHONPATH="$DIR/../../stats/src" CLAUDE_PROJECTS_DIR="$TMP_PROJECTS" \
    FORGE_GLOW_OTEL_LOG="$TMP_CODEX/no-otel.jsonl" python3 -c '
from forge_glow_stats.parsers import build_snapshot
s = build_snapshot()
f = s.models.get("fable")
print("{}|{:.2f}|{}|{}".format(
    f.request_count if f else 0,
    f.estimate_cost() if f else 0,
    s.tools_used.get("Bash", 0),
    s.tools_used.get("Read", 0),
))
  ' 2>/dev/null)"
  if [ "$python_out" = "2|23.25|1|1" ]; then
    echo "✓ parser: Python transcript dedup + nested tools"
  else
    echo "✗ PYTHON PARSER FAIL: expected 2|23.25|1|1, got $python_out"
    fail=1
  fi

  python_otel="$(PYTHONPATH="$DIR/../../stats/src" python3 -c '
import sys
from pathlib import Path
from forge_glow_stats.parsers import parse_otel
models, available = parse_otel(Path(sys.argv[1]))
print("{}|{}|{}|{}".format(
    str(available).lower(), models["opus"].request_count,
    models["opus"].cache_write, models["sonnet-5"].request_count
))
  ' "$FIX/otel-otlp-mixed.jsonl" 2>/dev/null)"
  if [ "$python_otel" = "true|1|100|1" ]; then
    echo "✓ parser: Python OTLP envelope"
  else
    echo "✗ PYTHON OTLP FAIL: expected true|1|100|1, got $python_otel"
    fail=1
  fi

  python_pricing="$(PYTHONPATH="$DIR/../../stats/src" python3 -c '
from forge_glow_stats.parsers import ModelUsage, short_model
models = [
    "claude-opus-4-1-20250805",
    "claude-sonnet-5",
    "claude-haiku-3-5-20241022",
]
print("|".join("{}:{:.2f}".format(
    short_model(model),
    ModelUsage(model=short_model(model), input_tokens=1_000_000,
               output_tokens=1_000_000).estimate_cost(),
) for model in models))
  ' 2>/dev/null)"
  if [ "$python_pricing" = "opus-4.1:90.00|sonnet-5:12.00|haiku-3.5:4.80" ]; then
    echo "✓ parser: Python model pricing families"
  else
    echo "✗ PYTHON PRICING FAIL: got $python_pricing"
    fail=1
  fi
fi

[ "$MODE" = "update" ] && { echo "golden regenerated."; exit 0; }
[ "$fail" -eq 0 ] && echo "ALL PARITY GREEN" || echo "PARITY BROKEN — spine output changed"
exit "$fail"
