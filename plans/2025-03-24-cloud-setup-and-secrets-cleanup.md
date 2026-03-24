# Cloud Setup & Secrets Cleanup Implementation Plan (v2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix cloud setup SSH issues, rename sync-secrets → sync-gist, remove age key from gist sync, and update all references across the codebase.

**Architecture:** Four workstreams: (1) cloud setup fixes (provider detection, SSH keys, interactive age key paste), (2) remove age key from gist sync code and live gist, (3) rename sync-secrets → sync-gist with scheduler migration, (4) update companion scripts and docs. Age key bootstrap moves to interactive paste during cloud setup (stored in Bitwarden). Gist is NOT deleted — just cleaned up with `gh gist edit --remove`.

**Tech Stack:** Bash, GitHub CLI (`gh`), SOPS, age

**Critic feedback incorporated:** Codex + Gemini critiques (v1→v2), plan-critic review (v2→v3). Key changes: no gist deletion (use API PATCH null), `read -rs </dev/tty` for piped execution, scheduler migration inside `setup_gist_sync.sh`, `config.sh` added, companion cloud scripts updated, `BASH_SOURCE` → `$0` for zsh scripts.

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `scripts/cloud/setup.sh` | Modify | Cloud setup (already partially modified in worktree) |
| `scripts/cloud/restart.sh` | Modify | Update to match `USER_HOME` + auto-detect pattern |
| `scripts/cloud/fix_permissions.sh` | Modify | Update to match `USER_HOME` + auto-detect pattern |
| `scripts/cloud/README.md` | Modify | Update variable docs and examples |
| `scripts/shared/helpers.sh` | Modify | Remove age key sync, rename `sync_secrets()` → `sync_gist()` |
| `scripts/sync_secrets.sh` | Rename → `scripts/sync_gist.sh` | Manual sync wrapper |
| `custom_bins/sync-secrets` | Rename → `custom_bins/sync-gist` | Scheduled sync binary |
| `scripts/cleanup/setup_secrets_sync.sh` | Rename → `scripts/cleanup/setup_gist_sync.sh` | Scheduler setup (with old job migration) |
| `config.sh` | Modify | Rename `SECRETS_GIST_ID` → `GIST_SYNC_ID` |
| `config/aliases.sh` | Modify | Rename alias, update `secrets-init` output |
| `deploy.sh` | Modify | Update function calls, section names, log messages |
| `README.md` | Modify | Update all references |
| `CLAUDE.md` | Modify | Update all references |

## Changes Already Applied (in this worktree)

In `scripts/cloud/setup.sh`:
- `HOME_DIR` → `USER_HOME` rename throughout
- Provider auto-detection (RunPod `/workspace` vs standard `/home`)
- `PERSISTENT` variable removed
- SSH keys: GitHub public key fallback when root has no `authorized_keys`
- Home dir `chmod 755` for sshd key auth
- `install.sh` without explicit flags (uses platform defaults)
- `gh auth` moved before `deploy.sh`
- Interactive age key paste prompt added

**Still needs fixing in setup.sh:** `read -r AGE_KEY` must use `</dev/tty` for `curl | bash` compatibility.

---

### Task 1: Fix setup.sh `read` for piped execution

**Files:**
- Modify: `scripts/cloud/setup.sh:112-128`

- [ ] **Step 1: Fix the `read` to use `/dev/tty`**

Replace the age key prompt block (lines 112-128) with:

```bash
# ─── Age key for SOPS secrets (paste from Bitwarden) ─────────────────────────
AGE_KEY_DIR="$USER_HOME/.config/sops/age"
if [ ! -f "$AGE_KEY_DIR/keys.txt" ]; then
    echo ""
    echo "Paste your age private key (from Bitwarden), then press Enter:"
    echo "(starts with AGE-SECRET-KEY-, leave empty to skip)"
    if [[ -e /dev/tty ]]; then
        read -rs AGE_KEY </dev/tty
    else
        echo "Non-interactive — skipping age key prompt. Paste after login with: secrets-init"
        AGE_KEY=""
    fi
    if [[ -n "$AGE_KEY" ]]; then
        sudo -u "$USERNAME" mkdir -p "$AGE_KEY_DIR"
        printf '%s\n' "$AGE_KEY" | sudo -u "$USERNAME" tee "$AGE_KEY_DIR/keys.txt" > /dev/null
        chmod 600 "$AGE_KEY_DIR/keys.txt"
        chown "$USERNAME:$USERNAME" "$AGE_KEY_DIR/keys.txt"
        echo "Age key saved."
    else
        echo "Skipping — run secrets-init after login to set up SOPS"
    fi
fi
```

Key changes from current:
- `read -rs AGE_KEY </dev/tty` — `-s` hides input (it's a private key), `</dev/tty` works when piped via `curl | bash`
- TTY guard: only checks `/dev/tty` exists (the actual requirement for the redirect)
- `printf '%s\n'` instead of `echo` (safer for special chars)

- [ ] **Step 2: Verify shellcheck passes**

Run: `shellcheck scripts/cloud/setup.sh`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add scripts/cloud/setup.sh
git commit -m "fix: cloud setup — SSH auth, provider detection, safe age key prompt"
```

---

### Task 2: Update companion cloud scripts to match setup.sh

**Files:**
- Modify: `scripts/cloud/restart.sh`
- Modify: `scripts/cloud/fix_permissions.sh`
- Modify: `scripts/cloud/README.md`

- [ ] **Step 1: Update restart.sh**

Replace the config section (lines 15-17) with auto-detection matching setup.sh:

```bash
USERNAME="${1:-${USERNAME:-yulong}}"

# Auto-detect provider (same logic as setup.sh)
if [[ -n "$USER_HOME" ]]; then
    :
elif [[ -d /workspace ]] || [[ -n "$RUNPOD_POD_ID" ]]; then
    USER_HOME="/workspace/$USERNAME"
else
    USER_HOME="/home/$USERNAME"
fi
```

Also replace all `$HOME_DIR` → `$USER_HOME` in the file, and update the SSH key copy to use the GitHub fallback (same pattern as setup.sh):

```bash
# Restore SSH access
GITHUB_USER="${GITHUB_USER:-yulonglin}"
mkdir -p "$USER_HOME/.ssh"
if [ -f /root/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys "$USER_HOME/.ssh/"
else
    curl -fsSL "https://github.com/$GITHUB_USER.keys" > "$USER_HOME/.ssh/authorized_keys"
fi
[ -f /root/.ssh/config ] && cp /root/.ssh/config "$USER_HOME/.ssh/" 2>/dev/null || true
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"
chmod 600 "$USER_HOME/.ssh/authorized_keys"
chmod 755 "$USER_HOME"  # sshd refuses key auth if home is group/world-writable
```

Remove the `PERSISTENT` positional arg (was `$2`). Remove old usage comment referencing it.

- [ ] **Step 2: Update fix_permissions.sh**

Replace config section (lines 7-9) with auto-detection:

```bash
USERNAME="${USERNAME:-yulong}"

if [[ -n "$USER_HOME" ]]; then
    :
elif [[ -d /workspace ]] || [[ -n "$RUNPOD_POD_ID" ]]; then
    USER_HOME="/workspace/$USERNAME"
else
    USER_HOME="/home/$USERNAME"
fi
```

Replace all `$HOME_DIR` → `$USER_HOME`. Remove `PERSISTENT`.

- [ ] **Step 3: Update scripts/cloud/README.md**

Update the configuration table:

```markdown
| Variable | Default | Description |
|----------|---------|-------------|
| `USERNAME` | `yulong` | Non-root username to create |
| `USER_HOME` | auto-detected | User home directory (auto: RunPod → `/workspace/$USERNAME`, else `/home/$USERNAME`) |
| `DOTFILES_REPO` | `https://github.com/yulonglin/dotfiles.git` | Dotfiles repo URL |
| `GITHUB_USER` | `yulonglin` | GitHub username for SSH public key fallback |
```

Update the Hetzner example:
```bash
# Standard VPS (auto-detects /home)
curl -fsSL .../setup.sh | bash
# Override home:
USER_HOME=/data/yulong curl -fsSL .../setup.sh | bash
```

Remove `PERSISTENT` references throughout.

- [ ] **Step 4: Verify shellcheck passes on modified scripts**

Run: `shellcheck scripts/cloud/restart.sh scripts/cloud/fix_permissions.sh`
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add scripts/cloud/restart.sh scripts/cloud/fix_permissions.sh scripts/cloud/README.md
git commit -m "refactor: cloud scripts use auto-detection, drop PERSISTENT/HOME_DIR"
```

---

### Task 3: Remove age key from gist sync code

**Files:**
- Modify: `scripts/shared/helpers.sh` (inside `sync_secrets()` function)

- [ ] **Step 1: Remove the age key sync block from sync_secrets()**

In `scripts/shared/helpers.sh`, find and delete the `# Sync age key (SOPS encryption)` block inside `sync_secrets()`:

```bash
    # Sync age key (SOPS encryption)
    local age_key_path="$HOME/.config/sops/age/keys.txt"
    if [[ -f "$age_key_path" ]] || [[ "$(gist_has_file "age_keys.txt")" == "yes" ]]; then
        log_info "Syncing age key..."
        mkdir -p "$(dirname "$age_key_path")"
        (umask 077 && sync_file "$age_key_path" "age_keys.txt" "$gist_id" "$gist_updated_at") && changes_made=true
        [[ -f "$age_key_path" ]] && chmod 600 "$age_key_path"
    fi
```

- [ ] **Step 2: Commit**

```bash
git add scripts/shared/helpers.sh
git commit -m "security: remove age private key from gist sync"
```

---

### Task 4: Remove age key from live gist

**Files:**
- None (GitHub API operation only)

- [ ] **Step 1: Verify the age key file exists in the gist**

```bash
gh api /gists/3cc239f160a2fe8c9e6a14829d85a371 --jq '.files | keys[]'
```

Expected: List includes `age_keys.txt`

- [ ] **Step 2: Remove age_keys.txt from the gist**

To delete a file from a gist via the API, send `null` for that file:

```bash
gh api -X PATCH /gists/3cc239f160a2fe8c9e6a14829d85a371 \
  --input <(echo '{"files":{"age_keys.txt":null}}')
```

⚠️ Do NOT use `-f 'files[age_keys.txt][content]='` — that sets content to empty string, it does not delete the file.

- [ ] **Step 3: Verify removal**

```bash
gh api /gists/3cc239f160a2fe8c9e6a14829d85a371 --jq '.files | keys[]'
```

Expected: `age_keys.txt` no longer listed. Only: `config`, `authorized_keys`, `user.conf`

⚠️ **Note on gist history:** Secret gist revision history still contains the age key. Gist history cannot be rewritten. This is acceptable because:
- Secret gists are unlisted (URL not publicly discoverable)
- We will rotate the actual API keys (Task 8), making the old age key useless
- The age key itself is not the valuable secret — the API keys it decrypts are

---

### Task 5: Rename sync_secrets → sync_gist with scheduler migration

**Files:**
- Modify: `scripts/shared/helpers.sh` (function name + log messages)
- Modify: `config.sh:68` (env var name)
- Rename: `scripts/sync_secrets.sh` → `scripts/sync_gist.sh`
- Rename: `custom_bins/sync-secrets` → `custom_bins/sync-gist`
- Rename: `scripts/cleanup/setup_secrets_sync.sh` → `scripts/cleanup/setup_gist_sync.sh`
- Modify: `config/aliases.sh`
- Modify: `deploy.sh`

- [ ] **Step 1: Rename function in helpers.sh**

In `scripts/shared/helpers.sh`:
- `sync_secrets()` → `sync_gist()`
- `SECRETS_GIST_ID` → `GIST_SYNC_ID` in the fallback: `local gist_id="${GIST_SYNC_ID:-3cc239f160a2fe8c9e6a14829d85a371}"`
- Log messages: `"Secrets synced with gist"` → `"Gist sync complete"`
- Log messages: `"All secrets already in sync"` → `"Gist already in sync"`

- [ ] **Step 2: Rename env var in config.sh**

In `config.sh:68`:
```bash
# Before:
SECRETS_GIST_ID="${SECRETS_GIST_ID:-3cc239f160a2fe8c9e6a14829d85a371}"  # Public identifier (like repo name), not a secret
# After:
GIST_SYNC_ID="${GIST_SYNC_ID:-3cc239f160a2fe8c9e6a14829d85a371}"  # Gist used for config sync (SSH, git identity)
```

- [ ] **Step 3: Rename script files**

```bash
git mv scripts/sync_secrets.sh scripts/sync_gist.sh
git mv custom_bins/sync-secrets custom_bins/sync-gist
git mv scripts/cleanup/setup_secrets_sync.sh scripts/cleanup/setup_gist_sync.sh
```

- [ ] **Step 4: Update scripts/sync_gist.sh contents**

```bash
#!/usr/bin/env zsh
# Manually trigger gist sync (SSH config, authorized_keys, git identity)
set -uo pipefail

DOT_DIR="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
export DOT_DIR

source "$DOT_DIR/config.sh"
source "$DOT_DIR/scripts/shared/helpers.sh"

sync_gist
```

- [ ] **Step 5: Update custom_bins/sync-gist contents**

```bash
#!/usr/bin/env zsh
# Sync config with GitHub gist (scheduled wrapper)

set -euo pipefail

DOT_DIR="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"

source "$DOT_DIR/config.sh"
source "$DOT_DIR/scripts/shared/helpers.sh"

log_info "Starting scheduled gist sync..."
if sync_gist; then
    log_success "Gist sync completed"
    exit 0
else
    log_error "Gist sync failed"
    exit 1
fi
```

Key changes from current: shebang → `zsh`, `BASH_SOURCE[0]` → `realpath "$0"` (zsh-compatible), added `source config.sh` (was missing — Codex found this bug).

- [ ] **Step 6: Update scripts/cleanup/setup_gist_sync.sh contents**

- `SYNC_BIN` path: `sync-secrets` → `sync-gist`
- `JOB_ID`: `"sync-secrets"` → `"sync-gist"`
- Comment: `# Setup automatic secrets sync` → `# Setup automatic gist sync`
- Log: `"Setting up automated secrets sync..."` → `"Setting up automated gist sync..."`
- Log: `"Secrets sync automation uninstalled."` → `"Gist sync automation uninstalled."`
- Add migration in `install()` BEFORE scheduling new job:
  ```bash
  # Migration: remove old job name if it exists
  unschedule "sync-secrets" 2>/dev/null || true
  ```

- [ ] **Step 7: Update config/aliases.sh**

- Alias: `alias sync-secrets='"$DOT_DIR/scripts/sync_secrets.sh"'` → `alias sync-gist='"$DOT_DIR/scripts/sync_gist.sh"'`
- Add deprecation alias: `alias sync-secrets='echo "Renamed to sync-gist"; sync-gist'`
- In `secrets-init()` output (line 83), remove the `sync-secrets` step:
  ```bash
  # Before:
  echo "  2. sync-secrets          # Sync age key to gist"
  # After: (remove this line entirely — age key comes from Bitwarden, not gist)
  ```
  Renumber remaining steps.

- [ ] **Step 8: Update deploy.sh**

- Section name: `"SYNCING SECRETS"` → `"SYNCING GIST"`
- Function call: `sync_secrets` → `sync_gist`
- Log: `"Secrets sync failed (continuing anyway)"` → `"Gist sync failed (continuing anyway)"`
- Log: `"Setting up automated daily secrets sync..."` → `"Setting up automated daily gist sync..."`
- Script path: `setup_secrets_sync.sh` → `setup_gist_sync.sh`
- Log: `"Failed to setup automated sync"` → `"Failed to setup automated gist sync"`
- Age key warning (line 255): `"run 'secrets-init' or 'sync-secrets'"` → `"run 'secrets-init' (paste age key from Bitwarden)"`

- [ ] **Step 9: Commit**

```bash
git add scripts/shared/helpers.sh config.sh scripts/sync_gist.sh custom_bins/sync-gist scripts/cleanup/setup_gist_sync.sh config/aliases.sh deploy.sh
git commit -m "refactor: rename sync-secrets → sync-gist, fix missing config.sh source"
```

---

### Task 6: Update documentation

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update README.md**

All occurrences:
- `sync-secrets` → `sync-gist`
- `setup_secrets_sync.sh` → `setup_gist_sync.sh`
- "Secrets Sync" headings → "Gist Sync"
- "Secrets sync pattern (bidirectional gist sync)" → "Gist sync (bidirectional SSH config/identity sync)"
- `SECRETS_GIST_ID` → `GIST_SYNC_ID`
- `PERSISTENT` → `USER_HOME` in cloud setup references
- "age private key (synced via gist)" → "age private key (stored in Bitwarden)"
- `secrets-init` description: clarify it generates a NEW keypair, not installs from Bitwarden
- Cloud setup section: update to reflect auto-detection, remove `PERSISTENT=/home` example

- [ ] **Step 2: Update CLAUDE.md**

All occurrences:
- `sync-secrets` → `sync-gist`
- `sync_secrets.sh` → `sync_gist.sh`
- "Secrets Sync" → "Gist Sync" in deploy component list
- "synced via gist" → "stored in Bitwarden, pasted during cloud setup"
- `PERSISTENT` → `USER_HOME` in cloud setup references
- Update `secrets-init` description

- [ ] **Step 3: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: sync-secrets → sync-gist, age key from Bitwarden"
```

---

### Task 7: Verify everything works

⚠️ **Cross-machine migration:** After merging, all other machines need `git pull && deploy.sh` to migrate the scheduler from `sync-secrets` → `sync-gist`. The `setup_gist_sync.sh` script handles this automatically via `unschedule "sync-secrets"` in its `install()` function. Until then, the old cron/launchd job will fail silently (binary renamed).

- [ ] **Step 1: Grep for any remaining old references**

```bash
rg 'sync.secrets|sync_secrets|SECRETS_GIST_ID|HOME_DIR|PERSISTENT' --type sh --type md --glob '!plans/*' --glob '!claude/custom-insights/*'
```

Expected: No matches outside of plans/ and custom-insights/ (historical records).

- [ ] **Step 2: Shellcheck all modified shell scripts**

```bash
shellcheck scripts/cloud/setup.sh scripts/cloud/restart.sh scripts/cloud/fix_permissions.sh
```

Note: `scripts/sync_gist.sh` and `custom_bins/sync-gist` are zsh — shellcheck with `# shellcheck shell=bash` at top (closest approximation).

- [ ] **Step 3: Source-level test of sync-gist**

```bash
source config.sh && source scripts/shared/helpers.sh && type sync_gist
```

Expected: `sync_gist is a function`

- [ ] **Step 4: Verify gist state**

```bash
gh api /gists/3cc239f160a2fe8c9e6a14829d85a371 --jq '.files | keys[]'
```

Expected: `authorized_keys`, `config`, `user.conf` (no `age_keys.txt`)

---

### Task 8: Rotate actual secrets (manual, post-merge)

⚠️ **This task is manual and happens AFTER all code changes are merged and deployed to all machines.**

The old age key was in the gist (even if only in history). While secret gists are unlisted, defense in depth requires rotating the actual API keys the old age key could decrypt.

- [ ] **Step 1: Generate new age keypair**

```bash
age-keygen 2>&1 | tee /dev/stderr | grep 'AGE-SECRET-KEY' > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

Note the new PUBLIC key from the output (starts with `age1...`).

- [ ] **Step 2: Update .sops.yaml with new public key**

Replace the old `age1...` public key with the new one in `.sops.yaml`.

- [ ] **Step 3: Re-encrypt secrets with new key**

```bash
# Must have BOTH old and new keys available during re-encryption
# Temporarily append old key if needed:
sops updatekeys config/secrets.env.enc
```

- [ ] **Step 4: Store new age private key in Bitwarden**

Copy the `AGE-SECRET-KEY-...` value to Bitwarden. Remove/update the old entry.

- [ ] **Step 5: Rotate actual API keys**

For each API key in `secrets.env.enc`:
- Go to the provider dashboard (Anthropic, OpenAI, etc.)
- Revoke the old key
- Generate a new key
- Update via `secrets-edit`

- [ ] **Step 6: Deploy to all machines**

On each machine:
1. `git pull` (gets new `.sops.yaml` and re-encrypted file)
2. Paste new age key from Bitwarden
3. `deploy.sh --secrets-env` to decrypt

- [ ] **Step 7: Commit**

```bash
git add .sops.yaml config/secrets.env.enc
git commit -m "security: rotate age key and re-encrypt secrets"
```
