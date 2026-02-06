# Plan: Scheduled AI CLI Tools Auto-Update + Bun Installation

## Goal
Two related changes:
1. **Add bun** to `install.sh` as the preferred package manager (Linux; macOS keeps brew)
2. **Add a daily scheduled job** (6 AM) that updates Claude Code, Codex CLI, and Gemini CLI

## Codex Critique Fixes Applied
- Use `claude update` universally (not `brew upgrade --cask claude-code`) — works regardless of install method
- Detect per-tool installation method (brew vs bun vs npm) rather than assuming platform = method
- Make `ai-update` alias call `update-ai-tools` script (single source of truth)
- Set `HOMEBREW_NO_AUTO_UPDATE=1` + `NONINTERACTIVE=1` in launchd context
- Add `--dry-run` flag to update script
- Scope bun install to Linux (macOS already has brew for everything)
- Add `$HOME/.bun/bin` and `$HOME/.npm-global/bin` to PATH in update script
- Log PATH at start of each run for debugging

---

## Part A: Bun Installation (Linux-focused)

### A1. `install.sh` — Add bun install (~line 232, before Gemini/Codex)

```bash
# Install bun (preferred package manager for global CLI tools on Linux)
if is_linux && ! cmd_exists bun; then
    log_info "Installing bun..."
    curl -fsSL https://bun.sh/install | bash
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
fi
```
On macOS, brew handles everything — no need for bun. Respect `FORCE_REINSTALL` flag.

### A2. `install.sh` — Use bun for global CLI installs on Linux

Replace `npm install -g` with `bun add -g`, npm as fallback:
```bash
# Gemini CLI (Linux)
elif cmd_exists bun; then
    bun add -g @google/gemini-cli || log_warning "Gemini CLI failed"
elif cmd_exists npm; then
    npm install -g @google/gemini-cli || log_warning "Gemini CLI failed"
```
Same pattern for Codex CLI. macOS continues using `brew_install`.

### A3. `config/zshrc.sh` — Add bun PATH

```bash
[[ -d "$HOME/.bun/bin" ]] && export PATH="$HOME/.bun/bin:$PATH"
```

### A4. `scripts/cloud/setup.sh` — Add bun install (~line 37)

After Node 20 install:
```bash
if ! command -v bun &>/dev/null; then
    curl -fsSL https://bun.sh/install | sudo -u "$USERNAME" bash
fi
```

---

## Part B: Scheduled Auto-Update

### B1. `custom_bins/update-ai-tools` — The update script (NEW)

**TODO(human) opportunity**: core update logic — per-tool installation detection and error handling strategy.

Key design:

**PATH setup** (critical for launchd/cron which have minimal PATH):
```bash
# macOS: source brew
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
# Both: add common paths
export PATH="$HOME/.bun/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"
```

**Per-tool update with method detection** (Codex critique fix):
```bash
update_claude() {
    command -v claude &>/dev/null || return 0  # skip if not installed
    claude update 2>&1  # works for both curl and brew installs
}

update_tool() {
    local tool_name="$1" brew_name="$2" npm_name="$3"
    command -v "$tool_name" &>/dev/null || return 0  # skip if not installed
    if is_macos && brew list "$brew_name" &>/dev/null 2>&1; then
        NONINTERACTIVE=1 HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade "$brew_name" 2>&1
    elif command -v bun &>/dev/null && bun pm ls -g 2>/dev/null | grep -q "$npm_name"; then
        bun add -g "${npm_name}@latest" 2>&1
    elif command -v npm &>/dev/null; then
        npm update -g "$npm_name" 2>&1
    fi
}

update_tool "gemini" "gemini-cli" "@google/gemini-cli"
update_tool "codex"  "codex"      "@openai/codex"
```

**Other requirements:**
- `--dry-run` flag (preview what would be updated, don't execute)
- Log PATH and timestamps at start of each run
- `set +e` during update section (continue on individual tool failure)
- Lock file with PID check at `~/.update-ai-tools.lock` (prevent concurrent runs, handle stale locks)

### B2. `scripts/cleanup/setup_ai_update.sh` — Scheduler setup (NEW)

Exact pattern of `scripts/cleanup/setup_claude_cleanup.sh`:
```bash
source "$DOT_DIR/scripts/scheduler/scheduler.sh"
JOB_ID="update-ai-tools"
schedule_daily "$JOB_ID" "$UPDATE_BIN" 6 0  # 6:00 AM
```
Supports `--uninstall`. Idempotent.

### B3. `config.sh` — Add deploy flag (after line 46)

```bash
DEPLOY_AI_UPDATE=true           # AI tools auto-update (daily, both platforms)
```
Add `DEPLOY_AI_UPDATE=false` to both `server` profile (~line 144) and `minimal` profile (~line 168).

### B4. `deploy.sh` — Integration

- Add `--ai-update` to `show_help()` (after `--claude-cleanup`, ~line 53)
- Add deployment section before "Done" (~line 593):
  ```bash
  # ─── AI Tools Auto-Update (both platforms) ──────────────────────────────────
  if [[ "$DEPLOY_AI_UPDATE" == "true" ]]; then
      log_section "INSTALLING AI TOOLS AUTO-UPDATE"
      if [[ -f "$DOT_DIR/scripts/cleanup/setup_ai_update.sh" ]]; then
          "$DOT_DIR/scripts/cleanup/setup_ai_update.sh" || log_warning "AI update setup failed"
      fi
  fi
  ```

### B5. `config/aliases.sh` — Simplify alias (~line 396)

Replace the 3-branch alias with a single call to the script (single source of truth):
```bash
alias ai-update='update-ai-tools'
```

### B6. Documentation updates

- `CLAUDE.md` — Add to deployment components list and deploy.sh defaults
- `scripts/cleanup/README.md` — Document new scheduled job

---

## Key Patterns to Reuse

| Pattern | Location | Purpose |
|---------|----------|---------|
| `schedule_daily()` | `scripts/scheduler/scheduler.sh` | Cross-platform scheduling |
| Setup script template | `scripts/cleanup/setup_claude_cleanup.sh` | Exact template for B2 |
| `brew_install()`, `cmd_exists()` | `scripts/shared/helpers.sh` | Helpers |
| Cloud Node setup | `scripts/cloud/setup.sh:32-37` | Linux Node/npm pattern |

## Implementation Strategy: Parallel Agents

| Agent | Task | Files |
|-------|------|-------|
| **Codex 1** | Part A: bun in install.sh + cloud setup + zshrc | `install.sh`, `scripts/cloud/setup.sh`, `config/zshrc.sh` |
| **Codex 2** | Part B: update script + scheduler + alias | `custom_bins/update-ai-tools`, `scripts/cleanup/setup_ai_update.sh`, `config/aliases.sh` |
| **Codex 3** | Part B: deploy integration + config + docs | `config.sh`, `deploy.sh`, `CLAUDE.md`, `scripts/cleanup/README.md` |

After implementation: **code-review agent** to validate.

## Verification

1. `command -v bun` after `install.sh --ai-tools` on Linux — bun installed
2. `bun add -g @openai/codex@latest` — bun global installs work
3. `update-ai-tools --dry-run` — previews updates without executing
4. `update-ai-tools` — runs successfully, logs per tool
5. `scripts/cleanup/setup_ai_update.sh` — job created
6. macOS: `launchctl list | grep update-ai-tools`
7. Linux: `crontab -l | grep update-ai-tools`
8. Logs: macOS `~/Library/Logs/com.user.update-ai-tools.log`, Linux `~/.update-ai-tools.log`
9. `./deploy.sh --minimal --ai-update` — end-to-end deploy
10. `ai-update` alias calls `update-ai-tools` correctly
11. `scripts/cleanup/setup_ai_update.sh --uninstall` — clean removal
