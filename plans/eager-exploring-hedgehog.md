# Fix: claude-plugin-reset + deploy.sh flag parsing

## Context

Two bugs triggered by `claude-plugin-reset` and `./deploy.sh --minimal --claude`:
1. `claude-plugin-reset` fails because the ai-safety-plugins marketplace was never registered
2. `--minimal` flag doesn't work in deploy.sh — all defaults still run
3. Component flags (e.g. `--claude`) set `INSTALL_*` instead of `DEPLOY_*` due to `typeset -g` always succeeding

## Fix 1: Centralize marketplace config in `config.sh`

Add marketplace array following existing `MCP_SERVERS_LOCAL` pattern:

```bash
# ─── Claude Code Plugin Marketplaces ─────────────────────────────────────────
# Format: "name:source" (source = GitHub user/repo)
# Official plugins (claude-plugins-official) are built-in — no registration needed
PLUGIN_MARKETPLACES=(
    "ai-safety-plugins:yulonglin/ai-safety-plugins"
)
```

**File:** `config.sh` (after `MCP_SERVERS_LOCAL` block, ~line 70)

## Fix 2: Update `claude-plugin-reset` to use centralized config

Source `config.sh` and loop over `PLUGIN_MARKETPLACES` instead of hardcoding:

```bash
source "$DOT_DIR/config.sh"

# --- Step 1: Update plugin marketplaces ---
run_step "Updating plugin marketplaces..."

if ! command -v claude &>/dev/null; then
  echo -e "  ${RED}claude CLI not found — skipping marketplace update${NC}"
else
  for entry in "${PLUGIN_MARKETPLACES[@]}"; do
    local name="${entry%%:*}"
    local src="${entry#*:}"

    if $DRY_RUN; then
      echo -e "  ${YELLOW}Would ensure marketplace: $name ($src)${NC}"
      continue
    fi

    # Register if not already added
    if ! claude plugin marketplace list 2>/dev/null | grep -q "$name"; then
      echo -e "  ${CYAN}Adding marketplace: $name from $src...${NC}"
      if ! claude plugin marketplace add "$src" 2>&1; then
        echo -e "  ${RED}Failed to add $name — skipping${NC}"
        continue
      fi
    fi

    # Update
    claude plugin marketplace update "$name" 2>&1 || \
      echo -e "  ${YELLOW}$name update had warnings (may be OK)${NC}"
  done
fi
```

**File:** `custom_bins/claude-plugin-reset` (replace lines 52-62)

## Fix 3: Fix `parse_args()` in `scripts/shared/helpers.sh`

**Problem A:** `--minimal` matches generic `--*`, sets meaningless `INSTALL_MINIMAL=true`.
**Problem B:** `typeset -g "INSTALL_${component}=true"` always succeeds in zsh, so `DEPLOY_*` is never set.

Add profile shortcuts before the generic `--*` case, and set both `INSTALL_*` and `DEPLOY_*`:

```bash
--minimal)
    apply_profile "minimal"
    ;;
--server)
    apply_profile "server"
    ;;
--personal)
    apply_profile "personal"
    ;;
--no-*)
    local component="${1#--no-}"
    component="${(U)component}"
    component="${component//-/_}"
    typeset -g "INSTALL_${component}=false"
    typeset -g "DEPLOY_${component}=false"
    ;;
--*)
    local component="${1#--}"
    component="${(U)component}"
    component="${component//-/_}"
    typeset -g "INSTALL_${component}=true"
    typeset -g "DEPLOY_${component}=true"
    ;;
```

**File:** `scripts/shared/helpers.sh` (lines 857-874 in `parse_args()`)

## Files to modify

1. `config.sh` — Add `PLUGIN_MARKETPLACES` array (~line 70)
2. `custom_bins/claude-plugin-reset` — Source config.sh, loop over marketplaces (lines 52-62)
3. `scripts/shared/helpers.sh` — Fix `parse_args()` (lines 857-874)

## Note: `date`/`mv` not found

Cannot reproduce. Once `--minimal` works correctly, htop deployment will be skipped and this error won't occur. If it recurs in other contexts, investigate PATH in that terminal session.

## Implementation order

0. Pull dotfiles: `git stash && git pull --rebase && git stash pop`
1. Clone/pull ai-safety-plugins at `~/code/ai-safety-plugins` (currently missing on this machine)
2. Fix symlink: `claude/ai-safety-plugins` → `~/code/ai-safety-plugins` (currently points to macOS `/Users/yulong/...`)
3. `config.sh` — add `PLUGIN_MARKETPLACES`
4. `scripts/shared/helpers.sh` — fix `parse_args()`
5. `custom_bins/claude-plugin-reset` — use centralized config

## Verification

1. `./deploy.sh --minimal --claude` — deploys base (tmux, shell) + claude only
2. `./deploy.sh --minimal --claude --ghostty` — deploys base + claude + ghostty
3. `./deploy.sh --no-editor` — deploys everything except editor
4. `claude-plugin-reset --dry-run` — shows marketplace registration + update for each entry
5. `claude-plugin-reset` (outside CC) — registers and updates ai-safety-plugins marketplace
