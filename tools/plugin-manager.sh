#!/usr/bin/env bash
# Install, update, or inspect forge-glow through the native Claude/Codex plugin managers.

set -euo pipefail

ACTION="${1:-}"
TARGET="${2:-all}"
REPO_SLUG="${FORGE_GLOW_REPO:-ggombee/forge-glow}"
REF="${FORGE_GLOW_REF:-main}"
MARKETPLACE="forge-glow"
PLUGIN_ID="forge-glow@forge-glow"
DRY_RUN="${FORGE_GLOW_DRY_RUN:-0}"

usage() {
  cat <<'EOF'
Usage: bash tools/plugin-manager.sh <install|update|check> [claude|codex|all]

Environment:
  FORGE_GLOW_REPO       GitHub owner/repo (default: ggombee/forge-glow)
  FORGE_GLOW_REF        Git ref for marketplace snapshots (default: main)
  FORGE_GLOW_DRY_RUN=1  Print mutating commands without running them
  FORGE_GLOW_CLAUDE_SETTINGS  Override Claude settings.json path
EOF
}

case "$ACTION" in
  install|update|check) ;;
  *) usage; exit 2 ;;
esac

case "$TARGET" in
  claude|codex|all) ;;
  *) usage; exit 2 ;;
esac

log() { printf '%s\n' "$*"; }

run() {
  printf '  +'
  printf ' %q' "$@"
  printf '\n'
  if [ "$DRY_RUN" != "1" ]; then
    "$@"
  fi
}

need() {
  if [ "$DRY_RUN" != "1" ] && ! command -v "$1" >/dev/null 2>&1; then
    log "ERROR: '$1' command is required for target '$2'."
    exit 1
  fi
}

claude_marketplace_exists() {
  claude plugin marketplace list --json 2>/dev/null \
    | jq -e --arg name "$MARKETPLACE" 'any(.[]?; .name == $name)' >/dev/null
}

claude_plugin_exists() {
  claude plugin list --json 2>/dev/null \
    | jq -e --arg id "$PLUGIN_ID" 'any(.[]?; .id == $id)' >/dev/null
}

enable_claude_autoupdate() {
  local settings config_dir tmp
  config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  settings="${FORGE_GLOW_CLAUDE_SETTINGS:-$config_dir/settings.json}"

  if [ "$DRY_RUN" = "1" ]; then
    log "  + enable autoUpdate for '$MARKETPLACE' in $settings"
    return
  fi

  mkdir -p "$(dirname "$settings")"
  if [ ! -f "$settings" ]; then
    printf '{}\n' > "$settings"
  fi
  jq empty "$settings" >/dev/null
  tmp="${settings}.forge-glow.$$"
  jq --arg name "$MARKETPLACE" --arg repo "$REPO_SLUG" --arg ref "$REF" '
    .extraKnownMarketplaces = (.extraKnownMarketplaces // {})
    | (.extraKnownMarketplaces[$name] // {}) as $entry
    | .extraKnownMarketplaces[$name] = ($entry + {
        source: ($entry.source // {
          source: "github",
          repo: $repo,
          ref: $ref
        }),
        autoUpdate: true
      })
  ' "$settings" > "$tmp"
  mv "$tmp" "$settings"
  log "  ✓ Claude marketplace autoUpdate enabled: $settings"
}

install_claude() {
  need claude claude
  need jq claude
  log "Claude Code plugin install"
  if [ "$DRY_RUN" = "1" ]; then
    run claude plugin marketplace add "${REPO_SLUG}@${REF}"
    enable_claude_autoupdate
    run claude plugin install "$PLUGIN_ID"
    return
  fi

  if claude_marketplace_exists; then
    run claude plugin marketplace update "$MARKETPLACE"
  else
    run claude plugin marketplace add "${REPO_SLUG}@${REF}"
  fi
  enable_claude_autoupdate
  if claude_plugin_exists; then
    run claude plugin update "$PLUGIN_ID"
  else
    run claude plugin install "$PLUGIN_ID"
  fi
  log "  → Run /reload-plugins or start a new Claude Code session."
}

update_claude() {
  need claude claude
  need jq claude
  log "Claude Code plugin update"
  if [ "$DRY_RUN" = "1" ]; then
    run claude plugin marketplace update "$MARKETPLACE"
    run claude plugin update "$PLUGIN_ID"
    return
  fi

  if ! claude_marketplace_exists; then
    install_claude
    return
  fi
  enable_claude_autoupdate
  run claude plugin marketplace update "$MARKETPLACE"
  if claude_plugin_exists; then
    run claude plugin update "$PLUGIN_ID"
  else
    run claude plugin install "$PLUGIN_ID"
  fi
  log "  → Run /reload-plugins or start a new Claude Code session."
}

check_claude() {
  need claude claude
  need jq claude
  log "Claude Code plugin state"
  claude plugin marketplace list --json \
    | jq --arg name "$MARKETPLACE" '[.[]? | select(.name == $name)]'
  claude plugin list --json \
    | jq --arg id "$PLUGIN_ID" '[.[]? | select(.id == $id)]'
}

codex_marketplace_exists() {
  codex plugin marketplace list --json 2>/dev/null \
    | jq -e --arg name "$MARKETPLACE" \
      'any(.marketplaces[]?; .name == $name)' >/dev/null
}

install_codex() {
  need codex codex
  need jq codex
  log "Codex plugin install"
  if [ "$DRY_RUN" = "1" ]; then
    run codex plugin marketplace add "$REPO_SLUG" --ref "$REF"
    run codex plugin add "$PLUGIN_ID"
    return
  fi

  if codex_marketplace_exists; then
    run codex plugin marketplace upgrade "$MARKETPLACE"
  else
    run codex plugin marketplace add "$REPO_SLUG" --ref "$REF"
  fi
  run codex plugin add "$PLUGIN_ID"
  log "  → Start a new Codex session, then invoke \$forge-glow-statusline."
}

update_codex() {
  need codex codex
  need jq codex
  log "Codex plugin update"
  if [ "$DRY_RUN" = "1" ]; then
    run codex plugin marketplace upgrade "$MARKETPLACE"
    run codex plugin add "$PLUGIN_ID"
    return
  fi

  if ! codex_marketplace_exists; then
    install_codex
    return
  fi
  run codex plugin marketplace upgrade "$MARKETPLACE"
  run codex plugin add "$PLUGIN_ID"
  log "  → Start a new Codex session to load the refreshed plugin."
}

check_codex() {
  need codex codex
  need jq codex
  log "Codex plugin state"
  codex plugin marketplace list --json \
    | jq --arg name "$MARKETPLACE" \
      '{marketplaces: [.marketplaces[]? | select(.name == $name)]}'
  codex plugin list --available --json \
    | jq --arg name "$MARKETPLACE" '
        {
          installed: [.installed[]? | select(.marketplaceName == $name or .pluginId == "forge-glow@forge-glow")],
          available: [.available[]? | select(.marketplaceName == $name or .pluginId == "forge-glow@forge-glow")]
        }
      '
}

if [ "$TARGET" = "claude" ] || [ "$TARGET" = "all" ]; then
  "${ACTION}_claude"
fi

if [ "$TARGET" = "codex" ] || [ "$TARGET" = "all" ]; then
  "${ACTION}_codex"
fi
