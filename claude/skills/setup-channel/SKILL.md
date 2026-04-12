---
name: setup-channel
description: Set up project-local messaging channels (Telegram, iMessage, Things Cloud). Platform-aware — Telegram works everywhere, iMessage requires macOS. Extensible dispatch table — adding a new channel means adding one row.
---

# Set up messaging channels

Configure per-project messaging channels so Claude Code can send/receive messages and read tasks from this repo.

---

## Channel Registry

| Channel | Platform | Has dedicated skill? | Config location |
|---------|----------|---------------------|-----------------|
| Telegram | All | Yes: `/telegram:configure`, `/telegram:access` | `.claude/channels/telegram/.env` + `access.json` |
| iMessage | macOS only | Yes: `/imessage:configure`, `/imessage:access` | `.claude/channels/imessage/access.json` |
| Things Cloud | All | No (inline below) | `THINGS_USERNAME`/`THINGS_PASSWORD` via bws or env |

**To add a new channel:** add a row to this table and a corresponding section below. The dispatch logic in Step 3 will handle it.

---

## Instructions

### 1. Detect platform

Run `uname -s` to detect the platform (Linux or Darwin/macOS).

- **Linux**: Only Telegram and Things Cloud are available. iMessage requires macOS — if the user requests it on Linux, refuse with: "iMessage requires macOS — it reads from the local `chat.db` SQLite database which only exists on macOS."
- **macOS**: All channels are available.

### 2. Parse arguments and select channels

- If the user passed an argument (e.g., `/setup-channel telegram` or `/setup-channel things`), use that channel directly.
- If no argument, list available channels based on platform and ask which to configure (can be multiple).

### 3. Dispatch to channel setup

For each requested channel, look it up in the registry above and follow the section below:

---

#### Telegram

Telegram has a dedicated skill. Delegate:

1. Tell the user: "Telegram setup is handled by the `/telegram:configure` skill. Running it now…"
2. Invoke `/telegram:configure` — it handles token collection, directory creation, `.env` writing, and `access.json` scaffolding.
3. After configure completes, tell the user: "To pair your Telegram account, run `/telegram:access`."
4. Note the **gotcha**: The built-in `/telegram:access` skill edits the GLOBAL `~/.claude/channels/telegram/access.json`, not the project-local one. Either pair before `TELEGRAM_STATE_DIR` is set, or edit the project-local `access.json` directly after pairing.
5. Ensure `.claude/channels/` is in `.gitignore` (Step 4).

---

#### iMessage (macOS only)

iMessage has a dedicated skill. Delegate:

1. Tell the user: "iMessage setup is handled by the `/imessage:configure` skill. Running it now…"
2. Invoke `/imessage:configure` — it handles handle collection, directory creation, and `access.json` scaffolding.
3. After configure completes, tell the user: "To manage iMessage access, run `/imessage:access`."
4. Remind the user: Full Disk Access for Terminal/iTerm2 is required in System Settings > Privacy & Security > Full Disk Access (needed to read `chat.db`).
5. Ensure `.claude/channels/` is in `.gitignore` (Step 4).

---

#### Things Cloud

Things Cloud has no dedicated skill — handle inline.

This is used by swordsmith-style bots that read tasks from Things 3 via the `things-mcp` plugin.

1. **Ask how the user wants to store credentials:**
   - **bws (recommended)** — credentials stored in BitWarden Secrets Manager, retrieved at session start. Ask for the secret name (e.g., `THINGS_CLOUD_CREDS`).
   - **env vars (simpler)** — `THINGS_USERNAME` and `THINGS_PASSWORD` set directly in `.envrc`.

2. **For bws flow:**
   - Tell the user to store their Things Cloud email + password as a JSON secret in bws: `{"username": "...", "password": "..."}`.
   - Add to `.envrc` (create or append):
     ```bash
     # Things Cloud credentials (via bws)
     eval "$(bws secret get <SECRET_NAME> | jq -r '"export THINGS_USERNAME=\(.value | fromjson | .username)\nexport THINGS_PASSWORD=\(.value | fromjson | .password)"')"
     ```

3. **For env vars flow:**
   - Ask for `THINGS_USERNAME` (Things Cloud email) and `THINGS_PASSWORD`.
   - Add to `.envrc` (create or append):
     ```bash
     export THINGS_USERNAME="<email>"
     export THINGS_PASSWORD="<password>"
     ```
   - **Warn**: Never commit `.envrc` containing plaintext credentials — ensure it's in `.gitignore`.

4. **Create the things-mcp config directory:**
   ```bash
   mkdir -p .claude/channels/things
   ```

5. **Write `.claude/channels/things/config.json`:**
   ```json
   {
     "source": "cloud",
     "syncOnStart": true
   }
   ```

6. Ensure `.claude/channels/` is in `.gitignore` (Step 4).

7. Tell the user: "Things Cloud credentials will be read from `THINGS_USERNAME`/`THINGS_PASSWORD` env vars. The `things-mcp` plugin will use them to sync tasks at session start."

---

### 4. Add `.claude/channels/` to `.gitignore` (idempotent)

After configuring any channel, check `.gitignore` and add the entry if missing:

```bash
grep -qxF '.claude/channels/' .gitignore 2>/dev/null || echo '.claude/channels/' >> .gitignore
```

This step is idempotent — safe to run for every channel.

---

### 5. Show final status

After all requested channels are configured, show a summary:

```
Channel setup complete for <repo-name>

Configured channels:
  ✓ Telegram: .claude/channels/telegram/ (bot token set, pairing mode)
  ✓ iMessage: .claude/channels/imessage/ (allowlist: user@example.com)
  ✓ Things Cloud: .claude/channels/things/ (credentials via bws/env)

Skipped (already configured):
  — (none)

Next steps:
  - Telegram: DM the bot, then run /telegram:access to pair
  - iMessage: Ensure Full Disk Access is granted in System Settings
  - Things Cloud: Run `direnv allow` if using .envrc credentials
  - Start a session with `claude` from this directory — channels auto-activate
```

Adapt to show only the channels actually configured. If a channel was already configured (files exist), note it as skipped/unchanged.

---

## Important Notes

- **One Telegram bot per project.** Sharing a bot token across projects causes competing pollers — only one session receives each message.
- **Never commit `.claude/channels/`** — it contains bot tokens and credentials. Always gitignore it.
- **The `claude()` wrapper handles activation.** No manual env vars or `--channels` flags needed — the wrapper auto-detects channel directories at launch.
- **Secrets-based Telegram flow**: For storing the token in `dotfiles-secrets` instead of a plain `.env`, run `setup-envrc --telegram-secret <SECRET_NAME>` instead of letting `/telegram:configure` write the `.env`.
- **Adding a new channel type**: Add a row to the Channel Registry table and a new `####` section in Step 3. No other changes needed.
