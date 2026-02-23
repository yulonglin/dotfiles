# Plan: Add Official Marketplace to Plugin Reset

## Context

`claude-plugin-reset` currently only handles the custom `ai-safety-plugins` marketplace. The official Anthropic marketplace (`anthropics/claude-plugins-official`) has 27 plugins already referenced in `settings.json` and `profiles.yaml`, but they're assumed to be "built-in" and never explicitly installed. This means:

- On a fresh machine, `installed_plugins.json` won't have official plugin entries
- `claude-context` may warn about unresolved plugins
- No way to update/reinstall official plugins via the reset script

**Goal:** Make `claude-plugin-reset` (and `deploy.sh`) register the official marketplace and install all 27 official plugins.

## Changes

### 1. `config.sh` — Add `OFFICIAL_PLUGINS` array

**File:** `/home/yulong/code/dotfiles/config.sh` (lines 72-77)

- Update comment on line 74 to note plugins still need explicit installation
- Add `OFFICIAL_PLUGINS` array after `PLUGIN_MARKETPLACES` with all 27 `@claude-plugins-official` plugins
- Add `"claude-plugins-official:anthropics/claude-plugins-official"` to `PLUGIN_MARKETPLACES`

```bash
PLUGIN_MARKETPLACES=(
    "claude-plugins-official:anthropics/claude-plugins-official"
    "ai-safety-plugins:yulonglin/ai-safety-plugins"
)

# Official plugins to auto-install from claude-plugins-official marketplace.
# Matches everything referenced in settings.json enabledPlugins.
OFFICIAL_PLUGINS=(
    # Base profile (always-on)
    "superpowers" "hookify" "plugin-dev" "commit-commands"
    "claude-md-management" "context7"
    # Development
    "code-simplifier" "code-review" "security-guidance" "feature-dev"
    "pr-review-toolkit" "playground" "ralph-loop" "claude-code-setup"
    # Integrations
    "Notion" "linear" "figma" "vercel" "supabase" "stripe" "playwright"
    # Language servers
    "pyright-lsp" "typescript-lsp"
    # Specialized
    "frontend-design" "huggingface-skills" "coderabbit" "serena"
)
```

### 2. `custom_bins/claude-plugin-reset` — Add official plugin install step

**File:** `/home/yulong/code/dotfiles/custom_bins/claude-plugin-reset`

Insert new **Step 2** between current Step 1 (marketplace update) and Step 2 (cache clean). Shifts existing steps 2→3, 3→4, 4→5.

New step logic:
```bash
# --- Step 2: Install official marketplace plugins ---
run_step "Installing official marketplace plugins..."

if ! command -v claude &>/dev/null; then
  echo -e "  ${RED}claude CLI not found — skipping${NC}"
else
  installed=0 skipped=0 failed=0
  for plugin in "${OFFICIAL_PLUGINS[@]}"; do
    qualified="${plugin}@claude-plugins-official"
    if $DRY_RUN; then
      echo -e "  ${YELLOW}Would ensure: $qualified${NC}"
      continue
    fi
    # Skip if already installed
    if claude plugin list 2>/dev/null | grep -q "$qualified"; then
      skipped=$((skipped + 1))
      continue
    fi
    if claude plugin install "$qualified" --scope user 2>&1; then
      installed=$((installed + 1))
    else
      echo -e "  ${YELLOW}Failed: $qualified${NC}"
      failed=$((failed + 1))
    fi
  done
  if ! $DRY_RUN; then
    echo -e "  ${GREEN}Installed: $installed${NC}, Skipped: $skipped, Failed: $failed"
  fi
fi
```

### 3. `deploy.sh` — Install official plugins during Claude deployment

**File:** `/home/yulong/code/dotfiles/deploy.sh` (after ai-safety-plugins registration, ~line 466)

Add equivalent official plugin install block using same pattern. Uses `log_info`/`log_success`/`log_warning` helpers already in deploy.sh.

### 4. No doc changes needed

`config.sh` comments are self-documenting. The `OFFICIAL_PLUGINS` array is the single source of truth.

## Verification

1. **Dry run:** `claude-plugin-reset --dry-run` — should list all 27 official plugins as "Would ensure"
2. **Idempotent:** Run `claude-plugin-reset` twice — second run should skip all 27
3. **Context check:** `claude-context --list` — no warnings about uninstalled plugins
4. **CLI syntax:** `claude plugin install superpowers@claude-plugins-official --scope user` — verify it works non-interactively before batch install
