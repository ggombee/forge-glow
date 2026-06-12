#!/usr/bin/env bash
# forge-glow — parse-routing.sh
# L3.5: bin/forge status --json의 route 키(.claude/state/route.json 실시간 스냅샷) 파싱.
# parse-forge.sh가 공유해둔 G_FORGE_STATUS_JSON을 재사용 — forge를 두 번 호출하지 않는다.
# 모든 G_ROUTE_* 는 선제 빈값 초기화 (set -u 방어, 부재 시 렌더 가드가 무표시 처리).
# shellcheck disable=SC2034

parse_routing() {
  G_ROUTE_MODEL=""
  G_ROUTE_VERSION=""
  G_ROUTE_EFFORT=""
  G_ROUTE_ROLE=""
  G_ROUTE_COMPLEXITY=""
  G_ROUTE_GATE_STATUS=""
  G_ROUTE_GATE_BLOCKS=""

  [ -z "${G_FORGE_STATUS_JSON:-}" ] && return
  command -v jq >/dev/null 2>&1 || return

  local route
  route=$(echo "$G_FORGE_STATUS_JSON" | jq -c '.route // empty' 2>/dev/null)
  if [ -z "$route" ] || [ "$route" = "null" ]; then
    return
  fi

  G_ROUTE_MODEL=$(echo "$route" | jq -r '.model // empty' 2>/dev/null)
  G_ROUTE_VERSION=$(echo "$route" | jq -r '.model_version // empty' 2>/dev/null)
  G_ROUTE_EFFORT=$(echo "$route" | jq -r '.effort_level // empty' 2>/dev/null)
  G_ROUTE_ROLE=$(echo "$route" | jq -r '.role // empty' 2>/dev/null)
  G_ROUTE_COMPLEXITY=$(echo "$route" | jq -r '.complexity // empty' 2>/dev/null)
  G_ROUTE_GATE_STATUS=$(echo "$route" | jq -r '.last_gate.status // empty' 2>/dev/null)
  G_ROUTE_GATE_BLOCKS=$(echo "$route" | jq -r '.last_gate.blocks // empty' 2>/dev/null)
}
