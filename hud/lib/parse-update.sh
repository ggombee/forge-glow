#!/usr/bin/env bash
# forge-glow — parse-update.sh
# self-update.sh가 남긴 update-available flag 감지 → statusline에 알림 표시
# shellcheck disable=SC2034  # G_UPDATE_* 변수들은 statusline.sh가 sourcing 후 사용

parse_update() {
  G_UPDATE_AVAILABLE=""

  local state="${FORGE_GLOW_STATE_DIR:-$HOME/.forge-glow}"
  local flag="$state/update-available"

  [ ! -f "$flag" ] && return

  local reason
  reason=$(head -1 "$flag" 2>/dev/null | tr -d ' \n')

  case "$reason" in
    dirty)          G_UPDATE_AVAILABLE="⬆︎ update available (dirty tree — commit/stash 후 재시도)" ;;
    local-commits)  G_UPDATE_AVAILABLE="⬆︎ update available (로컬 커밋 있음 — push 또는 rebase 필요)" ;;
    *)              G_UPDATE_AVAILABLE="⬆︎ update available" ;;
  esac
}
