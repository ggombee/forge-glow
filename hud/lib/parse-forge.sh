#!/usr/bin/env bash
# forge-glow — parse-forge.sh
# L3: code-forge usage.jsonl 파싱 (code-forge 설치 시에만 동작)

parse_forge() {
  local session_id="$1"

  G_FORGE_AGENTS=""
  G_FORGE_SKILLS=""
  G_FORGE_GATE=""
  G_FORGE_AVAILABLE=false

  local forge_log="$HOME/.code-forge/usage.jsonl"
  [ ! -f "$forge_log" ] && return

  G_FORGE_AVAILABLE=true

  # 현재 세션 에이전트/스킬 집계 (bellows-log v2: "sid" 필드)
  if [ -n "$session_id" ]; then
    G_FORGE_AGENTS=$(grep "\"sid\":\"$session_id\"" "$forge_log" 2>/dev/null \
      | jq -r 'select(.type=="agent") | .name' 2>/dev/null \
      | sort | uniq -c | sort -rn | head -4 \
      | awk '{printf "%s×%s ", $2, $1}' || true)

    G_FORGE_SKILLS=$(grep "\"sid\":\"$session_id\"" "$forge_log" 2>/dev/null \
      | jq -r 'select(.type=="skill") | .name' 2>/dev/null \
      | sort | uniq -c | sort -rn | head -3 \
      | awk '{printf "/%s×%s ", $2, $1}' || true)
  fi

  # 품질게이트 통과율 (state-schema v1 계약: .claude/state/quality.jsonl)
  # CWD 기준 프로젝트 로컬 파일 사용
  local project_root
  project_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  local quality_log="$project_root/.claude/state/quality.jsonl"

  if [ -f "$quality_log" ]; then
    local pass_count total_count
    pass_count=$(grep -c '"status":"pass"' "$quality_log" 2>/dev/null || echo "0")
    total_count=$(wc -l < "$quality_log" 2>/dev/null | tr -d ' ')
    if [ "$total_count" -gt 0 ] 2>/dev/null; then
      G_FORGE_GATE="gate:${pass_count}/${total_count}"
    fi
  fi
}