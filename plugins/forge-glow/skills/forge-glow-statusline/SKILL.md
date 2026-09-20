---
name: forge-glow-statusline
description: Configure, repair, verify, or explain forge-glow's native Codex CLI status line and its update path. Use when a user installs forge-glow, asks why its HUD is absent or mixed between sessions, wants the recommended `tui.status_line` fields, or wants to refresh the forge-glow Codex plugin.
---

# Forge Glow Statusline

Use Codex's native TUI status line. Never infer a current Codex session by scanning
`~/.codex/sessions` or another tool's transcript.

## Configure

1. Determine whether the user is in terminal Codex CLI or a non-TTY host. Explain that
   the desktop app, IDE integrations, API clients, and embedded hosts do not render the
   CLI footer.
2. In an interactive CLI, prefer `/statusline` and select these fields in order:
   `model-with-reasoning`, `context-remaining`, `five-hour-limit`, `weekly-limit`,
   `current-dir`, `git-branch`, `fast-mode`.
3. If editing the config directly, inspect `${CODEX_HOME:-$HOME/.codex}/config.toml`
   first. Preserve every unrelated key and existing `[tui]` setting. Add or replace only:

   ```toml
   status_line = ["model-with-reasoning", "context-remaining", "five-hour-limit", "weekly-limit", "current-dir", "git-branch", "fast-mode"]
   status_line_use_colors = true
   ```

   Put it inside the existing `[tui]` table, or create that table once if it is absent.
   Obtain approval before writing outside the active workspace when the host requires it.
4. Ask the user to open a new terminal Codex session if the current process does not
   reload an externally edited config.

## Verify

- Compare the footer's model, repository, and context with `/status` in the same CLI.
- Treat the model, directory, branch, and context as session-local.
- Treat five-hour and weekly limits as account-wide. Matching limits across sessions are
  expected and do not indicate context leakage.
- A rate-limit item is omitted when Codex does not receive that limit for the current
  account. Do not diagnose an omitted five-hour item as a status-line ordering failure.
- Codex controls native item labels. `tui.status_line` has no alias or formatter setting,
  so do not claim that the displayed `weekly` label can be renamed to `7d`.
- Do not promise visual parity with the Claude HUD. Codex exposes built-in native fields
  rather than arbitrary multiline shell rendering.

## Update the plugin

Inspect `codex plugin marketplace list --json` before changing anything. For the Git
marketplace named `forge-glow`, run:

```bash
codex plugin marketplace upgrade forge-glow
codex plugin add forge-glow@forge-glow
```

Then tell the user to start a new Codex session. If the marketplace is missing, install
it first with `codex plugin marketplace add ggombee/forge-glow --ref main`. Do not run
networked update commands when the user only asked for an explanation or diagnosis.
