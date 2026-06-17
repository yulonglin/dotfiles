# Plan: Declarative Plugin Marketplace Sync

## Context

On a fresh machine, `deploy.sh --claude` only registers the `ai-safety-plugins` marketplace (hardcoded bash). The other two marketplaces (`claude-plugins-official`, `ui-ux-pro-max-skill`) and their ~20 plugins must be manually registered and installed. We need a declarative, single-source-of-truth manifest for all marketplaces with automated registration + installation.

## Approach: Extend `profiles.yaml` + `claude-context`

Add a `marketplaces:` section to `profiles.yaml` (keeps all plugin config in one file), and add `claude-context --sync` to register + update all marketplaces. Replace hardcoded deploy.sh logic with delegation.

## Changes

### 1. `claude/templates/contexts/profiles.yaml` — add `marketplaces:` section

Insert before `base:`:

```yaml
marketplaces:
  claude-plugins-official:
    github: anthropics/claude-plugins-official

  ai-safety-plugins:
    local: ${CODE_DIR}/ai-safety-plugins   # prefer local dev clone
    github: yulonglin/ai-safety-plugins    # fallback for other machines

  ui-ux-pro-max-skill:
    github: nextlevelbuilder/ui-ux-pro-max-skill
```

- `local:` is optional — when present AND directory has `.claude-plugin`, use it (live dev). Otherwise fall back to `github:`.
- `${CODE_DIR}` expanded at runtime (default `~/code`).

### 2. `custom_bins/claude-context` — add sync functionality (~60 lines)

**New function `load_marketplaces()`**: Reads `marketplaces:` from profiles.yaml. Returns dict. Independent of `load_profiles()` (no existing callers touched).

**New function `resolve_marketplace_source(name, config)`**: Returns local path (if exists + has `.claude-plugin`) or GitHub repo string. Expands `${CODE_DIR}` env var.

**New function `sync_marketplaces(verbose=False)`**:
1. Check `claude` CLI exists (graceful skip if not)
2. `claude plugin marketplace list` → get currently registered
3. For each marketplace in manifest:
   - Resolve source (local or GitHub)
   - Register if not already registered (`claude plugin marketplace add`)
   - Update (`claude plugin marketplace update`) — installs all plugins from marketplace
4. Print summary: `X/Y marketplaces synced`

**CLI wiring**: Add `--sync-marketplaces` / `--sync` flag + `-v` verbose flag to argparse.

### 3. `deploy.sh` — replace hardcoded logic (lines 447-469)

Replace 22 lines of hardcoded ai-safety-plugins bash with:

```bash
# Sync plugin marketplaces (declarative, from profiles.yaml)
if command -v claude-context &>/dev/null; then
    log_info "Syncing plugin marketplaces..."
    claude-context --sync-marketplaces -v || \
        log_warning "Marketplace sync had issues — run manually: claude-context --sync"
else
    log_warning "claude-context not found — skipping marketplace sync"
fi
```

### 4. `CLAUDE.md` — update docs

Update "Plugin Organization & Context Profiles" section:
- Mention `marketplaces:` in profiles.yaml
- Add `claude-context --sync` to the CLI examples
- Update "Adding a new plugin" to include adding marketplace entry

## Files Modified

| File | Change |
|------|--------|
| `claude/templates/contexts/profiles.yaml` | Add `marketplaces:` section (~10 lines) |
| `custom_bins/claude-context` | Add 3 functions + CLI wiring (~60 lines) |
| `deploy.sh` | Replace lines 447-469 with 5-line delegation |
| `CLAUDE.md` | Update plugin docs |

## Error Handling

- **Claude CLI missing**: Skip gracefully, print install instructions
- **Local path missing**: Fall back to GitHub (expected on non-dev machines)
- **Registration fails**: Warn + continue to next marketplace
- **Network failure**: Individual failures don't block others
- **Already registered**: Skip (idempotent)
- **Timeouts**: 30s list, 60s add, 120s update

## Verification

1. `claude-context --sync -v` — should register all 3 marketplaces and update
2. `claude plugin marketplace list` — should show all 3
3. Fresh machine simulation: remove `known_marketplaces.json`, run `deploy.sh --claude`, verify all plugins installed
4. Local dev test: with `~/code/ai-safety-plugins` present, verify it uses local path
5. GitHub fallback test: rename local dir, verify it falls back to GitHub URL
