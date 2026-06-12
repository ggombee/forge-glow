#!/usr/bin/env bash
# forge-glow — alerts.sh
# 임계값 기반 실시간 경고 생성 + Slack webhook 전파 (opt-in)
# shellcheck disable=SC2034  # G_ALERT_* 변수들은 statusline.sh가 sourcing 후 사용
#
# 입력 (다른 parse-*.sh에서 설정됨):
#   G_CTX_PCT_INT       — L1 컨텍스트 %
#   G_COST_PER_HOUR     — L1 시간당 비용
#   G_RATE_5H, G_RATE_7D — L1 rate limit %
#   G_OTEL_AVAILABLE / G_OTEL_MODEL_COSTS — L5 (있으면 정확값 선호)
#
# 출력:
#   G_ALERT_TEXT — statusLine 3줄째에 얹을 경고 (비어있으면 기존 G_WASTE_WARN 유지)
#
# 환경변수 (opt-in):
#   FORGE_GLOW_SLACK_WEBHOOK — Slack incoming webhook URL
#   FORGE_GLOW_ALERT_COOLDOWN — 같은 알림 재전송 최소 간격(초, 기본 600=10분)

detect_alerts() {
  G_ALERT_TEXT=""

  local alerts=()

  # 컨텍스트 임계 (80% 이상 = 💀)
  if [ -n "${G_CTX_PCT_INT:-}" ] && [ "$G_CTX_PCT_INT" -ge 80 ] 2>/dev/null; then
    alerts+=("ctx:${G_CTX_PCT_INT}% auto-compact 임박 → /handoff")
  fi

  # cost/rate 경고는 제거 (2026-06-12 사용자 결정 — HUD 중복):
  #  - cost: LINE1 비용 아이콘이 $5/h 이상에서 🚨로 자체 에스컬레이션 + ($X/h) 숫자 상시 표시
  #  - rate: LINE3 ⏱ 표시가 60%↑ ⚠️ / 80%↑ 🔴로 자체 에스컬레이션
  #  경고의 LINE3 전체 교체가 ⏱ 5h/7d를 영구히 가리던 부작용도 함께 해소 (statusline.sh 보존 로직 참조).
  #  부수효과: cost/rate는 Slack 전파 대상에서도 빠짐 (ctx 경고만 전파 — opt-in webhook).

  [ "${#alerts[@]}" -eq 0 ] && return

  # 여러 경고는 " | "로 join (bash IFS는 단일 문자만 지원하므로 수동 조립)
  local joined="${alerts[0]}"
  local i
  for ((i=1; i<${#alerts[@]}; i++)); do
    joined="${joined} | ${alerts[$i]}"
  done
  G_ALERT_TEXT="🚨 ${joined}"

  # Slack 전파 (opt-in, 쿨다운 준수)
  push_slack_alert "$G_ALERT_TEXT"
}

push_slack_alert() {
  local msg="$1"
  [ -z "${FORGE_GLOW_SLACK_WEBHOOK:-}" ] && return
  [ -z "$msg" ] && return

  local state="${FORGE_GLOW_STATE_DIR:-$HOME/.forge-glow}"
  local stamp="$state/alert-last-sent"
  local cooldown="${FORGE_GLOW_ALERT_COOLDOWN:-600}"

  mkdir -p "$state" 2>/dev/null
  local now last
  now=$(date +%s)
  last=$(cat "$stamp" 2>/dev/null || echo 0)

  [ $((now - last)) -lt "$cooldown" ] && return

  # 같은 메시지면 스킵
  local last_msg
  last_msg=$(cat "$state/alert-last-msg" 2>/dev/null || echo "")
  [ "$last_msg" = "$msg" ] && return

  # background curl — statusLine 블로킹 금지
  (
    payload=$(printf '{"text":%s}' "$(printf '%s' "$msg" | jq -Rs .)" 2>/dev/null)
    curl -sS -X POST -H 'Content-Type: application/json' \
      --max-time 3 \
      --data "$payload" \
      "$FORGE_GLOW_SLACK_WEBHOOK" >/dev/null 2>&1
  ) &

  echo "$now" > "$stamp"
  echo "$msg" > "$state/alert-last-msg"
}
