# Plan: SOPS + age Encrypted Secrets + README & Config Centralization

## Context

Three related problems:

1. **Secrets management**: API keys (~5-10: Anthropic, OpenAI, HF, GitHub) scattered across per-project `.env` files. Cloud machines get secrets via manual copy-paste. No central management.

2. **README gaps**: No mention of Claude Code plugin marketplaces, no guidance for adopters on extracting useful parts, no clarity about what's personal vs. generalizable.

3. **Hardcoded values**: User-specific values (gist ID `3cc239f160a2fe8c9e6a14829d85a371`, username `yulong`, website alias) scattered across scripts.

**Prerequisite bug**: `config.sh` was deleted in `e265053` ("unused config file") but `deploy.sh:28`, `install.sh:22`, and `scripts/sync_secrets.sh:8` still `source` it. Scripts are broken. Must restore before any other work. Content available from `git show ae28a65:config.sh`.

## What is SOPS + age?

**SOPS** (Secrets OPerationS) is a Mozilla-created CLI that encrypts file values while keeping structure visible:
```
# Encrypted (safe to commit):
ANTHROPIC_API_KEY=ENC[AES256_GCM,data:abc123...,tag:xyz...]

# After `sops -d` → plaintext:
ANTHROPIC_API_KEY=sk-ant-api03-real-key-here
```

**age** is a modern, simple encryption tool (replaces GPG). You get a keypair: public key (in `.sops.yaml`, committed) and private key (`~/.config/sops/age/keys.txt`, synced via gist).

**Why this over alternatives**: Works offline (no Bitwarden network dependency), git-versioned, cross-platform, no service dependency, no session management friction.

## Architecture

```
# Encrypted (committed to git):
config/secrets.env.enc         # SOPS-encrypted API keys
.sops.yaml                     # SOPS config (age public key only)

# Decrypted (gitignored, never committed):
$DOT_DIR/.secrets              # deploy.sh decrypts here, zshrc sources it

# Age key (synced via existing gist mechanism):
~/.config/sops/age/keys.txt    # age private key (chmod 600)

# Per-project (any repo):
secrets.env.enc                # project-specific encrypted secrets
.envrc                         # direnv auto-decrypts on cd
```

## Implementation Steps

### 1. Restore `config.sh` + centralize user values (prerequisite)

Restore from `git show ae28a65:config.sh`. Add a "User Configuration" section at the top:

```bash
# ─── User Configuration ──────────────────────────────────────────────────────
# Edit these values for your setup. Everything else should work out of the box.
DOTFILES_USERNAME="${DOTFILES_USERNAME:-yulong}"
SECRETS_GIST_ID="${SECRETS_GIST_ID:-3cc239f160a2fe8c9e6a14829d85a371}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/yulonglin/dotfiles.git}"
```

Add `DEPLOY_SECRETS_ENV=true` to deploy components. Add `secrets_env` to `_known_components` in `helpers.sh:965`.

Update hardcoded references:
- `helpers.sh:314` — use `$DOTFILES_USERNAME` (currently hardcoded `yulong`)
- `scripts/cloud/setup.sh:16` — use `${DOTFILES_USERNAME:-yulong}`
- `scripts/cloud/restart.sh:15` — use `${DOTFILES_USERNAME:-yulong}`
- `config/aliases.sh:526` — `website` alias: make conditional or use `$DOTFILES_USERNAME`

### 2. Install sops + age + direnv (`install.sh`)

Follow existing patterns (`is_installed`, `brew_install`, Linux binary download):
- **macOS**: `brew install sops age direnv`
- **Linux**: Binary downloads from GitHub releases for sops + age, `curl -sfL https://direnv.net/install.sh | bash` for direnv

### 3. Add `.sops.yaml` to repo root (new file)

```yaml
creation_rules:
  - path_regex: \.enc$
    age: "age1..."  # placeholder, replaced by secrets-init
```

Committed to git — contains only the public key (not secret).

### 4. Add encrypted secrets decrypt to `deploy.sh`

Insert after existing "Secrets Sync" block (~line 238):

```bash
# ─── Encrypted Secrets (SOPS + age) ──────────────────────────────────────────
if [[ "${DEPLOY_SECRETS_ENV:-false}" == "true" ]]; then
    log_section "DECRYPTING SECRETS"
    local enc="$DOT_DIR/config/secrets.env.enc"
    local out="$DOT_DIR/.secrets"
    local age_key="$HOME/.config/sops/age/keys.txt"

    if [[ ! -f "$enc" ]]; then
        log_warning "No encrypted secrets — run 'secrets-init'"
    elif ! cmd_exists sops; then
        log_warning "sops not installed — run install.sh"
    elif [[ ! -f "$age_key" ]]; then
        log_warning "Age key not found — run 'secrets-init' or 'sync-secrets'"
    else
        sops -d "$enc" > "$out" && chmod 600 "$out" \
            && log_success "Decrypted secrets to $out" \
            || log_warning "Failed to decrypt secrets"
    fi
fi
```

### 5. Add age key to gist sync (`helpers.sh:sync_secrets()`)

After existing `sync_file` calls (~line 523):

```bash
# Sync age key (SOPS encryption)
local age_key_path="$HOME/.config/sops/age/keys.txt"
if [[ -f "$age_key_path" ]] || [[ "$(gist_has_file "age_keys.txt")" == "yes" ]]; then
    log_info "Syncing age key..."
    mkdir -p "$(dirname "$age_key_path")"
    sync_file "$age_key_path" "age_keys.txt" "$gist_id" "$gist_updated_at" && changes_made=true
    [[ -f "$age_key_path" ]] && chmod 600 "$age_key_path"
fi
```

### 6. Source `.secrets` in zshrc (`config/zshrc.sh`)

After line 48 (`[ -f $CONFIG_DIR/secrets.sh ] && source $CONFIG_DIR/secrets.sh`):
```bash
[ -f "$DOT_DIR/.secrets" ] && source "$DOT_DIR/.secrets"
```

Add direnv hook near bottom (after other tool integrations):
```bash
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"
```

### 7. Add helper commands (`config/aliases.sh`)

After existing `sync-secrets` alias (line 15):

- **`secrets-edit`** — `sops "$DOT_DIR/config/secrets.env.enc"` (edit encrypted in-place)
- **`secrets-decrypt`** — decrypt to `$DOT_DIR/.secrets` (same as deploy)
- **`secrets-init`** — first-time setup: generate age key, write `.sops.yaml` with public key, create initial `config/secrets.env.enc` with template, print next steps
- **`secrets-init-project`** — per-project setup: create `secrets.env.enc`, `.sops.yaml`, `.envrc` in current directory using same age key

### 8. Create envrc template (`config/envrc_sops_template`, new file)

```bash
# Auto-decrypt SOPS secrets on cd
if command -v sops &>/dev/null && [ -f secrets.env.enc ]; then
    eval "$(sops -d --output-type dotenv secrets.env.enc 2>/dev/null | sed 's/^/export /')"
fi
```

### 9. Update `.gitignore`

Add `.secrets` pattern (`.env` already gitignored at line 117).

### 10. Update README.md

**A. "Adopting These Dotfiles" section** (after "Getting to know these dotfiles"):

Content: Explain that this repo is highly personal and the best way to use it is to have a coding agent extract the parts you find useful. Include a table of generalizable vs. personal components. Note that all personal values are centralized in `config.sh`.

**B. "Claude Code Plugin Marketplaces" subsection**:

List the marketplaces worth exploring independently:
- **superpowers** (official) — TDD, brainstorming, code review, agent teams, worktree workflows
- **ui-ux-pro-max** — 50 design styles, 21 palettes, production-grade frontend
- **ai-safety-plugins** — Research experiments, paper writing, literature review
- **productivity-tools** — Hookify, plugin dev tools

Note that profiles are managed via `claude-context` CLI.

**C. "Encrypted Secrets (SOPS + age)" section** (after "Secrets Sync Automation"):

Document the new system alongside existing gist sync docs.

### 11. Update CLAUDE.md

Add to Deployment Components, Configuration Structure, and Important Behaviors sections.

## Files Changed

| File | Change |
|------|--------|
| `config.sh` | **Restore** + user config section + `DEPLOY_SECRETS_ENV=true` |
| `install.sh` | Add sops + age + direnv installation |
| `.sops.yaml` | **New**: SOPS config with age public key |
| `deploy.sh` | Add encrypted secrets decrypt section |
| `scripts/shared/helpers.sh` | Age key gist sync, `secrets_env` to `_known_components`, `$DOTFILES_USERNAME` |
| `config/zshrc.sh` | Source `.secrets`, direnv hook |
| `config/aliases.sh` | Secrets commands, update `website` alias |
| `config/envrc_sops_template` | **New**: template .envrc for per-project secrets |
| `.gitignore` | Add `.secrets` |
| `README.md` | Adoption guide, marketplace mentions, secrets docs |
| `CLAUDE.md` | Update documentation |

## Implementation Order

1. Restore `config.sh` + centralize hardcoded values (step 1)
2. Install sops + age + direnv (step 2)
3. `.sops.yaml` (step 3)
4. Age key gist sync (step 5)
5. Deploy decrypt section (step 4)
6. Shell integration (step 6)
7. Helper commands (step 7)
8. Envrc template (step 8)
9. `.gitignore` (step 9)
10. README.md (step 10)
11. CLAUDE.md (step 11)
12. Test end-to-end

## Verification

1. **Scripts work**: `./deploy.sh --help` and `./install.sh --help` don't crash (config.sh restored)
2. **Install**: `./install.sh` — verify `which sops age direnv`
3. **Init**: `secrets-init` — age key at `~/.config/sops/age/keys.txt`, `.sops.yaml` updated, `config/secrets.env.enc` created
4. **Edit**: `secrets-edit` — SOPS opens editor, saves encrypted
5. **Deploy**: `./deploy.sh --secrets-env` — `$DOT_DIR/.secrets` created (chmod 600)
6. **Shell**: New terminal — `echo $ANTHROPIC_API_KEY` outputs value
7. **Gist sync**: `sync-secrets` — age key in gist
8. **Per-project**: `secrets-init-project` → `sops secrets.env.enc` → `direnv allow` → key in env
9. **Graceful degradation**: Remove sops from PATH, new terminal — no errors, secrets just not loaded
10. **Config centralization**: `grep -r 'yulong' *.sh` shows only `${DOTFILES_USERNAME:-yulong}` patterns

## Sources

- [SOPS GitHub](https://github.com/getsops/sops)
- [age encryption](https://github.com/FiloSottile/age)
- [direnv](https://direnv.net/)
- [Bitwarden Secrets Manager CLI](https://bitwarden.com/help/secrets-manager-cli/) (considered, not chosen)
- [HN: What tools for env file secrets?](https://news.ycombinator.com/item?id=41629168)
