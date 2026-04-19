#!/usr/bin/env bash
# forge-glow — parse-forge.sh
# L3: code-forge 상태 파싱
# shellcheck disable=SC2034  # G_FORGE_* 변수들은 statusline.sh가 sourcing 후 사용
#
# 계약: code-forge의 bin/forge status --json surface를 통해서만 접근.
# .claude/state/ 파일 직독 금지 (code-forge CLAUDE.md + state-schema.md v1).

parse_forge() {
  local session_id="$1"

  G_FORGE_AGENTS=""
  G_FORGE_SKILLS=""
  G_FORGE_GATE=""
  G_FORGE_AVAILABLE=false

  # ── 1. bin/forge 탐색 ──────────────────────────────────────
  # code-forge 설치된 플러그인 캐시에서 bin/forge를 찾는다.
  # 우선순위: $CODE_FORGE_BIN > 플러그인 캐시 > dev 레포 (로컬 개발)
  local forge_bin=""
  if [ -n "${CODE_FORGE_BIN:-}" ] && [ -x "$CODE_FORGE_BIN" ]; then
    forge_bin="$CODE_FORGE_BIN"
  else
    # 마켓플레이스 캐시에서 최신 버전 탐색 (가장 높은 semver 디렉터리)
    local cache_root="$HOME/.claude/plugins/cache/forge-market/code-forge"
    if [ -d "$cache_root" ]; then
      local latest
      latest=$(ls "$cache_root" 2>/dev/null | sort -V | tail -1)
      [ -n "$latest" ] && [ -x "$cache_root/$latest/bin/forge" ] && forge_bin="$cache_root/$latest/bin/forge"
    fi
  fi

  # bin/forge를 못 찾으면 code-forge 비사용자 → 조용히 종료
  [ -z "$forge_bin" ] && return

  G_FORGE_AVAILABLE=true

  # ── 2. surface 호출 (계약 v1) ──────────────────────────────
  local status_json
  status_json=$("$forge_bin" status --json 2>/dev/null)
  [ -z "$status_json" ] && return

  # quality 집계 — 모든 세션 누적. 현재 세션만 필터는 bin/forge가 아직 미지원.
  local pass fail total
  pass=$(echo "$status_json" | jq -r '.state.quality_pass // 0' 2>/dev/null)
  fail=$(echo "$status_json" | jq -r '.state.quality_fail // 0' 2>/dev/null)
  total=$(echo "$status_json" | jq -r '.state.quality_events // 0' 2>/dev/null)

  if [ "${total:-0}" -gt 0 ] 2>/dev/null; then
    if [ "${fail:-0}" -gt 0 ] 2>/dev/null; then
      G_FORGE_GATE="gate:${pass}/${total}(fail:${fail})"
    else
      G_FORGE_GATE="gate:${pass}/${total}"
    fi
  fi

  # REFLECT flag 활성이면 경고
  local reflect_active
  reflect_active=$(echo "$status_json" | jq -r '.state.reflect_active // false' 2>/dev/null)
  if [ "$reflect_active" = "true" ]; then
    G_FORGE_GATE="${G_FORGE_GATE:+$G_FORGE_GATE }⚠️REFLECT"
  fi

  # ── 3. bellows usage.jsonl — 현재 세션 에이전트/스킬 집계 ────
  # bin/forge status는 session-level 필터를 아직 제공하지 않으므로
  # usage.jsonl은 계속 직접 파싱 (bellows v2.5 sid 필드 사용).
  local forge_log="$HOME/.code-forge/usage.jsonl"
  if [ -f "$forge_log" ] && [ -n "$session_id" ]; then
    G_FORGE_AGENTS=$(grep "\"sid\":\"$session_id\"" "$forge_log" 2>/dev/null \
      | jq -r 'select(.type=="agent") | .name' 2>/dev/null \
      | sort | uniq -c | sort -rn | head -4 \
      | awk '{printf "%s×%s ", $2, $1}' || true)

    G_FORGE_SKILLS=$(grep "\"sid\":\"$session_id\"" "$forge_log" 2>/dev/null \
      | jq -r 'select(.type=="skill") | .name' 2>/dev/null \
      | sort | uniq -c | sort -rn | head -3 \
      | awk '{printf "/%s×%s ", $2, $1}' || true)
  fi
}
