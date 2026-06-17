# Bitwarden Secrets Manager (bws) Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `bws` (Bitwarden Secrets Manager CLI) as the primary secrets backend alongside existing SOPS+age, enabling multi-machine secret access with a single access token per machine.

**Architecture:** `dotfiles-secrets` gains backend dispatch — auto-detects `bws` (if token exists AND `bws` CLI is installed) or falls back to `sops`. If `bws` is selected but fails at runtime, the error is clear (no silent fallback — explicit `DOTFILES_SECRETS_BACKEND` override for intentional switching). `setup-envrc` updated to emit backend-appropriate `watch_file` directives. Token stored at `~/.config/bws/token` (chmod 600), read on demand.

**Tech Stack:** bash, bws CLI (Bitwarden), python3 (JSON parsing), existing SOPS+age (fallback)

---

## File Map

| File | Change | Purpose |
|------|--------|---------|
| `scripts/helpers/dotfiles_secrets.sh` | Modify | Add `dotfiles_secrets_backend()`, `dotfiles_secrets_bws_token_file()`, harden bws token perms |
| `custom_bins/dotfiles-secrets` | Modify | Add bws backend functions, backend dispatch, update `paths` subcommand |
| `custom_bins/setup-envrc` | Modify | Emit backend-appropriate `watch_file` directives in generated `.envrc` |
| `scripts/shared/helpers.sh` | Modify | Add `install_bws()` |
| `install.sh` | Modify | Add `bws` to security tools install block |
| `scripts/cloud/setup.sh` | Modify | Add BWS access token prompt |
| `config/aliases.sh` | Modify | Add `secrets-init-bws` function |
| `CLAUDE.md` | Modify | Update secrets docs + learnings |

---

### Task 1: Add bws helpers to `scripts/helpers/dotfiles_secrets.sh`

**Files:**
- Modify: `scripts/helpers/dotfiles_secrets.sh`

- [ ] **Step 1: Add `dotfiles_secrets_bws_token_file()` and `dotfiles_secrets_backend()`**

After the existing `dotfiles_secrets_age_key()` function (line 19):

```bash
dotfiles_secrets_bws_token_file() {
    printf '%s\n' "${BWS_TOKEN_FILE:-$HOME/.config/bws/token}"
}

dotfiles_secrets_backend() {
    local explicit="${DOTFILES_SECRETS_BACKEND:-}"
    if [[ -n "$explicit" ]]; then
        printf '%s\n' "$explicit"
        return
    fi
    # Auto-detect: prefer bws if BOTH token exists AND bws CLI is installed
    if { [[ -n "${BWS_ACCESS_TOKEN:-}" ]] || [[ -f "$(dotfiles_secrets_bws_token_file)" ]]; } && \
       command -v bws >/dev/null 2>&1; then
        printf 'bws\n'
    elif command -v sops >/dev/null 2>&1 && [[ -f "$(dotfiles_secrets_enc)" ]]; then
        printf 'sops\n'
    else
        # Neither backend is available — return empty so callers can give clear errors
        printf 'none\n'
    fi
}
```

- [ ] **Step 2: Extend `dotfiles_secrets_harden_permissions()` for bws token**

Add after the age_key block (line 33):

```bash
local bws_token
bws_token=$(dotfiles_secrets_bws_token_file)
if [[ -f "$bws_token" ]]; then chmod 600 "$bws_token" 2>/dev/null || true; fi
if [[ -d "$(dirname "$bws_token")" ]]; then chmod 700 "$(dirname "$bws_token")" 2>/dev/null || true; fi
```

- [ ] **Step 3: Verify auto-detect logic**

```bash
source scripts/helpers/dotfiles_secrets.sh

# Test 1: no bws token, no sops → none
(unset BWS_ACCESS_TOKEN DOTFILES_SECRETS_BACKEND
 dotfiles_secrets_backend)  # should print "none" (or "sops" if sops+enc exist)

# Test 2: BWS_ACCESS_TOKEN set + bws installed → bws
(BWS_ACCESS_TOKEN=test dotfiles_secrets_backend)  # should print "bws" (if bws in PATH)

# Test 3: token file exists + bws installed → bws
mkdir -p ~/.config/bws && echo test > ~/.config/bws/token
(unset BWS_ACCESS_TOKEN; dotfiles_secrets_backend)  # should print "bws"

# Test 4: explicit override wins
(DOTFILES_SECRETS_BACKEND=sops BWS_ACCESS_TOKEN=test dotfiles_secrets_backend)  # should print "sops"

# Test 5: token exists but bws NOT installed → falls through to sops
(unset BWS_ACCESS_TOKEN
 PATH=/usr/bin:/bin  # remove bws from PATH
 dotfiles_secrets_backend)  # should print "sops" (not "bws")

# Cleanup
rm -f ~/.config/bws/token
```

- [ ] **Step 4: Commit**

```bash
git add scripts/helpers/dotfiles_secrets.sh
git commit -m "feat: add bws backend detection to dotfiles_secrets helpers"
```

---

### Task 2: Add bws backend to `custom_bins/dotfiles-secrets`

**Files:**
- Modify: `custom_bins/dotfiles-secrets`

- [ ] **Step 1: Add backend dispatch at top of script**

Replace lines 18-20 (the unconditional SOPS var setup) with:

```bash
BACKEND=$(dotfiles_secrets_backend)
BWS_TOKEN_FILE=$(dotfiles_secrets_bws_token_file)

if [[ "$BACKEND" == "sops" ]]; then
    SECRETS_ENC=$(dotfiles_secrets_enc)
    SOPS_CONFIG=$(dotfiles_secrets_sops_config)
fi
```

- [ ] **Step 2: Add bws backend functions**

After the existing `load_secrets_cache` function (line ~58), add:

```bash
# ─── bws backend ─────────────────────────────────────────────────────────────

require_bws() {
    command -v bws >/dev/null 2>&1 || die "bws not found. Run: install.sh or cargo install bws"
    if [[ -z "${BWS_ACCESS_TOKEN:-}" ]]; then
        [[ -f "$BWS_TOKEN_FILE" ]] || die "No BWS_ACCESS_TOKEN and $BWS_TOKEN_FILE not found. Run: secrets-init-bws"
        BWS_ACCESS_TOKEN=$(cat "$BWS_TOKEN_FILE")
        export BWS_ACCESS_TOKEN
    fi
}

load_secrets_cache_bws() {
    [[ -n "$SECRETS_CACHE" ]] && return 0
    require_bws
    local json bws_stderr
    bws_stderr=$(mktemp)
    json=$(bws secret list 2>"$bws_stderr") || {
        local err
        err=$(cat "$bws_stderr")
        rm -f "$bws_stderr"
        die "bws secret list failed: $err"
    }
    rm -f "$bws_stderr"
    SECRETS_CACHE=$(printf '%s\n' "$json" | python3 -c '
import json, sys
data = json.load(sys.stdin)
if not isinstance(data, list):
    print(f"Unexpected bws output: expected JSON array, got {type(data).__name__}", file=sys.stderr)
    sys.exit(1)
for s in data:
    if "key" not in s or "value" not in s:
        print(f"Unexpected bws secret format: missing key/value in {list(s.keys())}", file=sys.stderr)
        sys.exit(1)
    k, v = s["key"], s["value"]
    if any(c in v for c in (" ", "\n", "\r", "\t", "\"", "'\''", "#", "$", "`", "\\", "=")):
        v = "\"" + v.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t") + "\""
    print(f"{k}={v}")
') || die "Failed to parse bws output (is the bws CLI version compatible?)"
}

# ─── backend dispatch ────────────────────────────────────────────────────────

load_secrets() {
    case "$BACKEND" in
        bws)  load_secrets_cache_bws ;;
        sops) load_secrets_cache ;;
        none) die "No secrets backend available. Run: secrets-init-bws (recommended) or secrets-init (SOPS)" ;;
        *)    die "Unknown backend: $BACKEND. Set DOTFILES_SECRETS_BACKEND to 'bws' or 'sops'" ;;
    esac
}
```

- [ ] **Step 3: Replace all `load_secrets_cache` calls with `load_secrets`**

There are 4 call sites in the existing code:
1. `list_sensitive_keys` function
2. `print_shell_exports` function
3. `write_telegram_env` function
4. The `dotenv)` case in the main switch

Replace each `load_secrets_cache` → `load_secrets`.

- [ ] **Step 4: Update `paths` subcommand**

Replace the existing `paths)` case:

```bash
paths)
    printf 'DOTFILES_SECRETS_BACKEND=%s\n' "$BACKEND"
    printf 'DOTFILES_SECRETS_DIR=%s\n' "$(dotfiles_secrets_dir)"
    if [[ "$BACKEND" == "bws" ]]; then
        printf 'BWS_TOKEN_FILE=%s\n' "$BWS_TOKEN_FILE"
    else
        printf 'SECRETS_ENC=%s\n' "$SECRETS_ENC"
        printf 'SOPS_CONFIG=%s\n' "$SOPS_CONFIG"
        printf 'SOPS_AGE_KEY_FILE=%s\n' "$(dotfiles_secrets_age_key)"
    fi
    ;;
```

- [ ] **Step 5: Update usage text**

Add to the heredoc at the bottom:

```
  Backend: $DOTFILES_SECRETS_BACKEND (auto: bws if token exists, else sops)
```

- [ ] **Step 6: Test bws backend end-to-end**

Requires a real BWS token. Run each:

```bash
dotfiles-secrets paths                    # should show BWS_TOKEN_FILE
dotfiles-secrets keys                     # should list keys matching KEY_PATTERN
dotfiles-secrets dotenv                   # should output KEY=value lines
dotfiles-secrets shell ANTHROPIC_API_KEY  # should output export line
dotfiles-secrets shell --all              # should export all sensitive keys
```

- [ ] **Step 7: Test sops backend regression**

```bash
DOTFILES_SECRETS_BACKEND=sops dotfiles-secrets keys
DOTFILES_SECRETS_BACKEND=sops dotfiles-secrets dotenv
DOTFILES_SECRETS_BACKEND=sops dotfiles-secrets shell ANTHROPIC_API_KEY
```

- [ ] **Step 8: Commit**

```bash
git add custom_bins/dotfiles-secrets
git commit -m "feat: add bws backend to dotfiles-secrets"
```

---

### Task 3: Update `setup-envrc` watch_file directives

**Files:**
- Modify: `custom_bins/setup-envrc`

Currently `write_envrc()` hardcodes SOPS-specific watch paths (lines 321-323):
```bash
printf 'watch_file %q\n' "$helper_bin"
printf 'watch_file %q\n' "$secrets_enc"
printf 'watch_file %q\n' "$sops_config"
```

When the bws backend is active, these files don't exist — direnv watches nothing useful, so it won't re-eval when the bws token changes or the backend switches.

- [ ] **Step 1: Make `write_envrc()` emit backend-appropriate watch directives**

Replace the hardcoded `watch_file` lines in `write_envrc()` with:

```bash
printf 'watch_file %q\n' "$helper_bin"
# Watch backend-specific files so direnv re-evals on token/config changes
local _backend
_backend=$("$helper_bin" paths 2>/dev/null | sed -n 's/^DOTFILES_SECRETS_BACKEND=//p')
case "$_backend" in
    bws)
        local _bws_token
        _bws_token=$("$helper_bin" paths 2>/dev/null | sed -n 's/^BWS_TOKEN_FILE=//p')
        [[ -n "$_bws_token" ]] && printf 'watch_file %q\n' "$_bws_token"
        ;;
    sops|*)
        printf 'watch_file %q\n' "$secrets_enc"
        printf 'watch_file %q\n' "$sops_config"
        ;;
esac
```

This queries `dotfiles-secrets paths` (which already knows the active backend) instead of hardcoding paths.

- [ ] **Step 2: Test generated `.envrc` with bws backend**

```bash
# With bws active:
cd /tmp/test-repo && git init && setup-envrc ANTHROPIC_API_KEY
grep watch_file .envrc  # should show ~/.config/bws/token, NOT secrets.enc
```

- [ ] **Step 3: Test generated `.envrc` with sops backend**

```bash
DOTFILES_SECRETS_BACKEND=sops setup-envrc ANTHROPIC_API_KEY
grep watch_file .envrc  # should show secrets.enc and .sops.yaml
```

- [ ] **Step 4: Commit**

```bash
git add custom_bins/setup-envrc
git commit -m "fix: emit backend-appropriate watch_file directives in setup-envrc"
```

---

### Task 4: Add `install_bws()` to `scripts/shared/helpers.sh`

**Files:**
- Modify: `scripts/shared/helpers.sh`

- [ ] **Step 1: Add `install_bws()` function**

Insert after `install_direnv()` (line ~367):

```bash
install_bws() {
    if is_installed bws; then return 0; fi
    log_info "Installing bws (Bitwarden Secrets Manager CLI)..."
    curl -fsSL "https://bitwarden.com/secrets/install" | sh 2>/dev/null || {
        log_warning "bws install script failed, trying GitHub release..."
        local bws_arch tmpd
        case "$(uname -m)" in
            x86_64)  bws_arch="x86_64" ;;
            aarch64) bws_arch="aarch64" ;;
            arm64)   bws_arch="aarch64" ;;  # macOS
            *)       log_warning "Unsupported architecture for bws"; return 1 ;;
        esac
        tmpd=$(mktemp -d)
        mkdir -p "$HOME/.local/bin"
        local os_suffix
        if is_macos; then
            os_suffix="apple-darwin"
        else
            os_suffix="unknown-linux-gnu"
        fi
        curl -fsSL "https://github.com/bitwarden/sdk-internal/releases/latest/download/bws-${bws_arch}-${os_suffix}.zip" \
            -o "$tmpd/bws.zip" && \
            unzip -o "$tmpd/bws.zip" -d "$HOME/.local/bin/" && \
            chmod +x "$HOME/.local/bin/bws" && \
            log_success "bws installed" || { log_warning "bws installation failed"; rm -rf "$tmpd"; return 1; }
        rm -rf "$tmpd"
    }
}
```

- [ ] **Step 2: Verify**

```bash
source ./config.sh && source scripts/shared/helpers.sh
install_bws
bws --version
```

- [ ] **Step 3: Commit**

```bash
git add scripts/shared/helpers.sh
git commit -m "feat: add install_bws() for Bitwarden Secrets Manager CLI"
```

---

### Task 5: Add bws to `install.sh`

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add `bws` to security tools install block**

In the Linux parallel block (~line 139):

```bash
run_parallel "Installing security tools" \
    "gitleaks|install_gitleaks" \
    "sops|install_sops" \
    "age|install_age" \
    "direnv|install_direnv" \
    "bws|install_bws"
```

In the macOS sequential block (~line 146):

```bash
install_gitleaks
install_sops
install_age
install_direnv
install_bws
```

- [ ] **Step 2: Commit**

```bash
git add install.sh
git commit -m "feat: install bws alongside sops/age/direnv"
```

---

### Task 6: Add `secrets-init-bws` to `config/aliases.sh`

**Files:**
- Modify: `config/aliases.sh`

- [ ] **Step 1: Add `secrets-init-bws()` function**

After the existing `secrets-init` function:

```bash
secrets-init-bws() {
    local token_file token_dir
    token_file=$(dotfiles_secrets_bws_token_file)
    token_dir=$(dirname "$token_file")

    echo "BWS token file: $token_file"

    if [[ -f "$token_file" ]]; then
        echo "BWS token already exists."
        echo -n "Overwrite? [y/N] "
        read -r answer
        [[ "$answer" =~ ^[Yy]$ ]] || return 0
    fi

    echo ""
    echo "Paste your BWS access token (from Bitwarden Secrets Manager):"
    echo "(machine account token, starts with 0., leave empty to skip)"
    read -rs bws_token
    echo ""

    if [[ -z "$bws_token" ]]; then
        echo "Skipped"
        return 0
    fi

    mkdir -p "$token_dir"
    chmod 700 "$token_dir"
    printf '%s\n' "$bws_token" > "$token_file"
    chmod 600 "$token_file"
    echo "Token saved to $token_file"

    echo "Testing bws connectivity..."
    if BWS_ACCESS_TOKEN="$bws_token" bws secret list &>/dev/null; then
        local count
        count=$(BWS_ACCESS_TOKEN="$bws_token" bws secret list 2>/dev/null | \
            python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo "?")
        echo "Success — $count secret(s) accessible"
    else
        echo "Warning: bws secret list failed — check your token" >&2
    fi

    dotfiles_secrets_harden_permissions

    echo ""
    echo "Backend: $(dotfiles_secrets_backend)"
    echo "Next: dotfiles-secrets keys / setup-envrc"
}
```

- [ ] **Step 2: Commit**

```bash
git add config/aliases.sh
git commit -m "feat: add secrets-init-bws command for machine token setup"
```

---

### Task 7: Update `scripts/cloud/setup.sh`

**Files:**
- Modify: `scripts/cloud/setup.sh`

- [ ] **Step 1: Add BWS token prompt after SOPS age key section**

Insert after line 302 (end of age key section), before the deploy.sh section:

```bash
# ─── BWS access token ──────────────────────────────────────────────────────
step "BWS access token (Bitwarden Secrets Manager)"
BWS_TOKEN_DIR="$USER_HOME/.config/bws"
BWS_TOKEN_FILE="$BWS_TOKEN_DIR/token"
if [ ! -f "$BWS_TOKEN_FILE" ]; then
    echo "Paste your BWS access token (from Bitwarden Secrets Manager), leave empty to skip:"
    if [[ -e /dev/tty ]]; then
        read -rs BWS_TOKEN </dev/tty
    else
        warn "Non-interactive — skipping BWS token. Run: secrets-init-bws"
        BWS_TOKEN=""
    fi
    if [[ -n "$BWS_TOKEN" ]]; then
        run_as "mkdir -p $BWS_TOKEN_DIR && chmod 700 $BWS_TOKEN_DIR"
        printf '%s\n' "$BWS_TOKEN" | run_as "tee $BWS_TOKEN_FILE > /dev/null"
        run_as "chmod 600 $BWS_TOKEN_FILE"
        ok "BWS token saved"
    else
        log "Skipping — run secrets-init-bws after login"
    fi
else
    ok "BWS token already exists"
fi
```

- [ ] **Step 2: Commit**

```bash
git add scripts/cloud/setup.sh
git commit -m "feat: add BWS token prompt to cloud setup"
```

Note: NOT adding auto `setup-envrc --all` — that would export every managed key into the dotfiles repo, violating the per-project least-privilege model. Users run `setup-envrc` manually per-repo after first login.

---

### Task 8: Update documentation

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md**

In the "Encrypted Secrets" deployment component description, update to mention dual backend:
- "Encrypted secrets (SOPS+age / BWS) — ..."
- Add `secrets-init-bws` to the commands list
- Add `DOTFILES_SECRETS_BACKEND` to env var mentions

Add learnings entry:
```
- Secrets backend: added bws (Bitwarden Secrets Manager) as primary backend alongside SOPS+age fallback. Token at ~/.config/bws/token. Auto-detect: bws if token exists, else sops. Override with DOTFILES_SECRETS_BACKEND env var. Free tier: 1 org, 3 machine accounts, unlimited secrets. bws has no offline cache — direnv caches in shell session (YYYY-MM-DD)
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add bws backend to secrets documentation"
```

---

## Verification Checklist

After all tasks:

1. **Fresh shell, bws token present:**
   - `dotfiles-secrets paths` → shows `DOTFILES_SECRETS_BACKEND=bws` and `BWS_TOKEN_FILE=...`
   - `dotfiles-secrets keys` → lists secret names
   - `dotfiles-secrets shell ANTHROPIC_API_KEY` → prints export line
   - `setup-envrc ANTHROPIC_API_KEY` in a test repo → generates `.envrc`
   - `grep watch_file .envrc` → shows `~/.config/bws/token` (not sops files)
   - `cd` into that repo → direnv loads the key

2. **Explicit sops fallback:**
   - `DOTFILES_SECRETS_BACKEND=sops dotfiles-secrets keys` → works via SOPS
   - `DOTFILES_SECRETS_BACKEND=sops dotfiles-secrets dotenv` → same output as before
   - `DOTFILES_SECRETS_BACKEND=sops setup-envrc ANTHROPIC_API_KEY` → `.envrc` watches sops files

3. **Neither backend available (no bws token, no sops files):**
   - Remove/rename `~/.config/bws/token` and unset `BWS_ACCESS_TOKEN`
   - `dotfiles-secrets keys` → error: "No secrets backend available. Run: secrets-init-bws (recommended) or secrets-init (SOPS)"

4. **bws token exists but `bws` CLI not installed:**
   - `dotfiles-secrets paths` → should show `sops` (auto-detect falls through to sops)
   - NOT a bws error — graceful degradation

5. **install.sh:**
   - `./install.sh` → installs bws alongside other security tools
   - `bws --version` → succeeds

6. **secrets-init-bws:**
   - Run interactively → prompts for token, saves file, tests connectivity
   - File permissions: `stat ~/.config/bws/token` → mode `600`, dir `700`

## Parallelism Guide

```
Task 1 (helpers) ──┐
                    ├─→ Task 2 (dotfiles-secrets core)
                    ├─→ Task 3 (setup-envrc watch_file)
Task 4 (install)  ─┤
                    ├─→ Task 5 (install.sh)
                    ├─→ Task 6 (aliases.sh)
                    └─→ Task 7 (cloud/setup.sh)
                         └─→ Task 8 (docs) — last
```

Tasks 1+4 are independent and can run in parallel. Tasks 2+3 depend on Task 1. Tasks 5/6/7 depend on Task 4 (for install) and Task 1 (for helpers). Task 8 is last.
