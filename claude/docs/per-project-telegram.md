# Per-Project Telegram Bots in Claude Code

How to run separate Telegram bots per repository, so each project has its own bot identity.

## How It Works

Two things are needed:

1. **`TELEGRAM_STATE_DIR`** — env var that tells the plugin's MCP server where to read `.env` (token) and `access.json` (allowlist). Defaults to `~/.claude/channels/telegram/`.
2. **`--channels plugin:telegram@claude-plugins-official`** — launch flag that enables inbound message routing. Without this, the bot sends but can't receive.

## Setup Per Project

### 1. Create bot via @BotFather

Each project gets its own bot (e.g., `ambassador_bot`, `nudge_bot`).

### 2. Store the canonical token in `dotfiles-secrets`

```bash
secrets-edit
# Add a namespaced key such as:
#   AMBASSADOR_TELEGRAM_BOT_TOKEN=123456789:AAH...
```

Then bind the repo to that secret:

```bash
setup-envrc --telegram-secret AMBASSADOR_TELEGRAM_BOT_TOKEN
```

This records the secret name in `.envrc` and exports:

- `TELEGRAM_STATE_DIR=<repo>/.claude/channels/telegram`
- `DOTFILES_TELEGRAM_BOT_SECRET=AMBASSADOR_TELEGRAM_BOT_TOKEN`

The `claude()` shell wrapper then generates `.claude/channels/telegram/.env` just before launch. Treat that file as a runtime artifact, not the source of truth.

### 3. Gitignore the runtime state

```gitignore
.claude/channels/
```

### 4. Set up access control

Create `.claude/channels/telegram/access.json`:
```json
{
  "dmPolicy": "pairing",
  "allowFrom": [],
  "groups": {},
  "pending": {}
}
```

Then DM the bot, get a pairing code, and approve with `/telegram:access pair <code>`.
After pairing, lock down: set `"dmPolicy": "allowlist"`.

**Gotcha**: The `/telegram:access` skill edits the GLOBAL `~/.claude/channels/telegram/access.json`, not the project-local one. Edit the project-local file directly or pair before setting `TELEGRAM_STATE_DIR`.

### 5. Automate in shell wrapper

The `claude()` function in `config/aliases.sh` auto-detects and configures:

```bash
# Per-project channels: auto-detect and enable
local channels=()
if [[ -n "${DOTFILES_TELEGRAM_BOT_SECRET:-}" ]]; then
    export TELEGRAM_STATE_DIR="${TELEGRAM_STATE_DIR:-$PWD/.claude/channels/telegram}"
    "$DOT_DIR/custom_bins/dotfiles-secrets" write-telegram-env \
        "$DOTFILES_TELEGRAM_BOT_SECRET" "$TELEGRAM_STATE_DIR" >/dev/null
    channels+=(plugin:telegram@claude-plugins-official)
elif [[ -f ".claude/channels/telegram/.env" ]]; then
    export TELEGRAM_STATE_DIR="${TELEGRAM_STATE_DIR:-$PWD/.claude/channels/telegram}"
    channels+=(plugin:telegram@claude-plugins-official)
fi
if [[ ${#channels[@]} -gt 0 ]]; then
    args+=(--channels "${channels[@]}")
fi
```

No manual env vars or flags needed — just `claude` from the project directory.

## Known Gotchas

### 1. Skills hardcode global path

`/telegram:configure` and `/telegram:access` always read/write `~/.claude/channels/telegram/`. They don't respect `TELEGRAM_STATE_DIR`. Edit the project-local files directly when needed. ([anthropics/claude-code#42641](https://github.com/anthropics/claude-code/issues/42641), [claude-plugins-official#851](https://github.com/anthropics/claude-plugins-official/issues/851))

### 2. Competing pollers steal messages

Every Claude Code session with the telegram plugin enabled spawns the MCP server and polls `getUpdates`. Telegram delivers each update to **one** consumer only. Other sessions steal messages from the `--channels` instance. Use separate bot tokens per project to avoid this. ([anthropics/claude-code#41835](https://github.com/anthropics/claude-code/issues/41835))

### 3. `--channels` is mandatory for receiving

Without `--channels`, the MCP server runs (sending works, bot shows "typing"), but `notifications/claude/channel` never reaches the conversation. This is the most common setup failure — not documented anywhere obvious.

### 4. No official multi-bot support yet

`TELEGRAM_STATE_DIR` is supported in the server code but not officially documented. Feature request: [anthropics/claude-code#37173](https://github.com/anthropics/claude-code/issues/37173). No maintainer response yet.

### 5. Local-scope plugin install writes to global path

Choosing "install for this repo only" still writes config to `~/.claude/channels/telegram/`, not the project directory. ([claude-plugins-official#933](https://github.com/anthropics/claude-plugins-official/issues/933))

## Quick Reference

| What | Where |
|------|-------|
| Canonical project token | `dotfiles-secrets/secrets.env.enc` |
| Runtime plugin token file | `.claude/channels/telegram/.env` |
| Project access | `.claude/channels/telegram/access.json` |
| Global token (fallback) | `~/.claude/channels/telegram/.env` |
| Shell wrapper | `dotfiles/config/aliases.sh` → `claude()` |
| Launch flag | `--channels plugin:telegram@claude-plugins-official` |
| Env var | `TELEGRAM_STATE_DIR=$PWD/.claude/channels/telegram` |
