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

  # 현재 세션 에이전트 사용 집계
  if [ -n "$session_id" ]; then
    G_FORGE_AGENTS=$(grep "\"session_id\":\"$session_id\"" "$forge_log" 2>/dev/null \
      | jq -r 'select(.type=="agent") | .name' 2>/dev/null \
      | sort | uniq -c | sort -rn | head -4 \
      | awk '{printf "%s×%s ", $2, $1}' || true)

    G_FORGE_SKILLS=$(grep "\"session_id\":\"$session_id\"" "$forge_log" 2>/dev/null \
      | jq -r 'select(.type=="skill") | .name' 2>/dev/null \
      | sort | uniq -c | sort -rn | head -3 \
      | awk '{printf "/%s×%s ", $2, $1}' || true)
  fi

  # 품질게이트 통과율
  local quality_log="$HOME/.code-forge/quality.jsonl"
  if [ -f "$quality_log" ]; then
    local pass total
    pass=$(grep -c '"pass":true' "$quality_log" 2>/dev/null || echo "0")
    total=$(wc -l < "$quality_log" 2>/dev/null | tr -d ' ')
    [ "$total" -gt 0 ] 2>/dev/null && G_FORGE_GATE="gate:${pass}/${total}"
  fi
}