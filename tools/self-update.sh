#!/usr/bin/env bash
# forge-glow — self-update.sh
# 안전한 자동 업데이트 (Codex+Claude 합의 설계, 2026-04)
#
# 3중 안전 가드:
#   1. clean tree — `git diff` 비어있을 때만
#   2. upstream tracking — @{u} 설정된 브랜치만
#   3. fast-forward only — 로컬에 커밋 있으면 스킵
#
# 트리거: launchd(macOS) / cron(Linux). statusLine 렌더 경로에는 들어가지 않음.
#
# 환경변수:
#   FORGE_GLOW_DIR            - 레포 경로 (기본: $HOME/Desktop/workspace/forge-glow)
#   FORGE_GLOW_STATE_DIR      - 상태 파일 경로 (기본: $HOME/.forge-glow)
#   FORGE_GLOW_UPDATE_INTERVAL - 최소 재시도 간격, 초 단위 (기본: 3600)

set -euo pipefail

ROOT="${FORGE_GLOW_DIR:-$HOME/Desktop/workspace/forge-glow}"
STATE="${FORGE_GLOW_STATE_DIR:-$HOME/.forge-glow}"
LOCK="$STATE/update.lock"
STAMP="$STATE/last-attempt"
INTERVAL="${FORGE_GLOW_UPDATE_INTERVAL:-3600}"

mkdir -p "$STATE"

# ── 1. 동시 실행 잠금 (mkdir은 atomic) ────────────────────
if ! mkdir "$LOCK" 2>/dev/null; then
  exit 0   # 다른 인스턴스가 작업 중
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

# ── 2. Throttle ───────────────────────────────────────────
now=$(date +%s)
last=$(cat "$STAMP" 2>/dev/null || echo 0)
if [ $((now - last)) -lt "$INTERVAL" ]; then
  exit 0
fi
echo "$now" > "$STAMP"

# ── 3. 레포 유효성 ────────────────────────────────────────
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# dirty/로컬커밋 때문에 스킵하는 경우엔 flag 남겨서 statusLine이 알림 표시
AVAIL_FLAG="$STATE/update-available"
clear_flag() { rm -f "$AVAIL_FLAG" 2>/dev/null || true; }
set_flag()   { echo "$1" > "$AVAIL_FLAG"; }

DIRTY=false
git -C "$ROOT" diff --quiet || DIRTY=true
git -C "$ROOT" diff --cached --quiet || DIRTY=true

# ── 5. upstream 추적 확인 ─────────────────────────────────
upstream=$(git -C "$ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
if [ -z "$upstream" ]; then
  clear_flag
  exit 0
fi
remote="${upstream%%/*}"

# ── 6. fetch (네트워크 실패 조용히 스킵) ─────────────────
GIT_TERMINAL_PROMPT=0 git -C "$ROOT" fetch --quiet "$remote" 2>/dev/null || exit 0

head=$(git -C "$ROOT" rev-parse HEAD)
tip=$(git -C "$ROOT" rev-parse "$upstream" 2>/dev/null || echo "$head")

# 이미 최신이면 flag 제거
if [ "$head" = "$tip" ]; then
  clear_flag
  exit 0
fi

# ── 7. dirty 또는 로컬커밋이면 머지 스킵 + flag 설정 ───────
base=$(git -C "$ROOT" merge-base HEAD "$upstream" 2>/dev/null || echo "$head")
if [ "$DIRTY" = true ]; then
  set_flag "dirty"      # 사용자 작업 중 — 덮어쓰기 금지
  exit 0
fi
if [ "$head" != "$base" ]; then
  set_flag "local-commits"  # 로컬에 앞선 커밋 있음 — ff 불가
  exit 0
fi

# ── 8. ff-only 머지 ──────────────────────────────────────
if GIT_TERMINAL_PROMPT=0 git -C "$ROOT" merge --ff-only --quiet "$upstream" 2>/dev/null; then
  clear_flag
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") updated $head -> $tip" >> "$STATE/update.log"
fi
