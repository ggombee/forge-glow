#!/usr/bin/env bash
# forge-glow — metrics-report.sh
# 주간 사용 메트릭 리포트 — bellows usage.jsonl + self-update.log + quality.jsonl 분석.
# 실제 사용 데이터가 축적된 후 `/usage 관측` 용도.
#
# 환경변수:
#   FORGE_GLOW_STATE_DIR  - 기본: ~/.forge-glow
#   BELLOWS_LOG           - 기본: ~/.code-forge/usage.jsonl
#   REPORT_DAYS           - 기본: 7

set -uo pipefail

STATE="${FORGE_GLOW_STATE_DIR:-$HOME/.forge-glow}"
BELLOWS="${BELLOWS_LOG:-$HOME/.code-forge/usage.jsonl}"
DAYS="${REPORT_DAYS:-7}"

CUTOFF=$(date -u -v-"${DAYS}"d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
       || date -u -d "${DAYS} days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
       || echo "")

printf '═══════════════════════════════════════════════════════════════\n'
printf '  forge-glow weekly metrics report — last %s days\n' "$DAYS"
printf '  generated: %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
printf '═══════════════════════════════════════════════════════════════\n'

# BSD awk는 match 3-arg 미지원이라 python3로 cutoff 필터.
filter_by_cutoff() {
  local file="$1"
  local cutoff="$2"
  if [ -z "$cutoff" ] || ! command -v python3 >/dev/null 2>&1; then
    cat "$file"
    return
  fi
  python3 - "$cutoff" "$file" <<'PY'
import re, sys
cutoff, path = sys.argv[1], sys.argv[2]
with open(path, encoding='utf-8', errors='ignore') as f:
    for line in f:
        m = re.search(r'"ts":"([^"]+)"', line)
        if m and m.group(1) >= cutoff:
            sys.stdout.write(line)
PY
}

# ── 1. bellows usage.jsonl ──────────────────────────────
if [ -f "$BELLOWS" ] && command -v jq >/dev/null 2>&1; then
  printf '\n[1] code-forge bellows (last %s days)\n' "$DAYS"
  printf -- '-----\n'

  FILTERED=$(filter_by_cutoff "$BELLOWS" "$CUTOFF")
  TOTAL=$(printf '%s\n' "$FILTERED" | grep -c . || echo 0)
  printf 'total events: %s\n' "$TOTAL"

  if [ "$TOTAL" -gt 0 ]; then
    printf '\ntop agents:\n'
    echo "$FILTERED" | jq -r 'select(.type=="agent") | .name' 2>/dev/null \
      | sort | uniq -c | sort -rn | head -5 \
      | awk '{printf "  %-30s %s\n", $2, $1}'

    printf '\ntop skills:\n'
    echo "$FILTERED" | jq -r 'select(.type=="skill") | .name' 2>/dev/null \
      | sort | uniq -c | sort -rn | head -5 \
      | awk '{printf "  %-30s %s\n", $2, $1}'

    # agent_end duration 평균 (bellows v2.5)
    printf '\nagent_end duration (평균):\n'
    echo "$FILTERED" | jq -r 'select(.type=="agent_end") | "\(.name) \(.duration_ms)"' 2>/dev/null \
      | awk '{sum[$1]+=$2; cnt[$1]++} END{for (k in sum) printf "  %-30s avg=%dms count=%d\n", k, sum[k]/cnt[k], cnt[k]}' \
      | sort -k2 -rn | head -5
  fi
else
  printf '\n[1] code-forge bellows: 로그 없음 (%s)\n' "$BELLOWS"
fi

# ── 2. self-update 이력 ─────────────────────────────────
UPDATE_LOG="$STATE/update.log"
if [ -f "$UPDATE_LOG" ]; then
  printf '\n[2] forge-glow self-update (last %s days)\n' "$DAYS"
  printf -- '-----\n'
  CUT_CNT=0
  if [ -n "$CUTOFF" ]; then
    CUT_CNT=$(awk -v c="$CUTOFF" '$1 >= c' "$UPDATE_LOG" | wc -l | tr -d ' ')
  else
    CUT_CNT=$(wc -l < "$UPDATE_LOG" | tr -d ' ')
  fi
  printf 'updates in period: %s\n' "$CUT_CNT"
  printf 'last 5 updates:\n'
  tail -5 "$UPDATE_LOG" 2>/dev/null | awk '{printf "  %s\n", $0}'
else
  printf '\n[2] self-update: 이력 없음 (dirty/로컬커밋으로 자동 pull 되지 않음?)\n'
fi

# ── 3. alert 이력 ───────────────────────────────────────
ALERT_LAST_MSG="$STATE/alert-last-msg"
if [ -f "$ALERT_LAST_MSG" ]; then
  printf '\n[3] last alert:\n'
  printf -- '-----\n'
  printf '  %s\n' "$(cat "$ALERT_LAST_MSG" 2>/dev/null)"
fi

# ── 4. code-forge quality.jsonl (있으면) ────────────────
QUALITY=""
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
if [ -f "$GIT_ROOT/.claude/state/quality.jsonl" ] && command -v jq >/dev/null 2>&1; then
  QUALITY="$GIT_ROOT/.claude/state/quality.jsonl"
  printf '\n[4] code-forge quality-gate (현재 프로젝트, last %s days)\n' "$DAYS"
  printf -- '-----\n'
  FILTERED_Q=$(filter_by_cutoff "$QUALITY" "$CUTOFF")
  PASS=$(echo "$FILTERED_Q" | grep -c '"status":"pass"')
  WARN=$(echo "$FILTERED_Q" | grep -c '"status":"warn"')
  FAIL=$(echo "$FILTERED_Q" | grep -c '"status":"fail"')
  printf 'pass: %s / warn: %s / fail: %s\n' "$PASS" "$WARN" "$FAIL"
fi

printf '\n═══════════════════════════════════════════════════════════════\n'
printf '  end of report\n'
printf '═══════════════════════════════════════════════════════════════\n'
