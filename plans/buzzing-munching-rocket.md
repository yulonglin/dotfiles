# Supply Chain Defense System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automated multi-layer defense against npm/PyPI supply chain attacks across all repos, addressing the axios (2026), litellm (2026), and shai-hulud (2025) attack patterns.

**Architecture:** 9 defense layers — min-release-age quarantine (7-day delay across all package managers), credential isolation (stop global API key export), postinstall lockdown (`.npmrc`), Socket CLI wrapper, hash-pinned Python deps (Claude rule), periodic audit (cron/launchd), Claude Code PreToolUse hook, git pre-commit lockfile check, and Claude behavioral rule. All deployed via existing dotfiles infrastructure (deploy.sh/install.sh), working across all repos in `~/code`, `~/scratch`, `~/writing`.

**Resolved questions:**
- **Hooks for package versions?** — No. min-release-age handles the "too new" case. Version pinning is already enforced by lockfiles. A hook checking specific versions would be brittle and redundant with the weekly audit's known-bad IOC list.
- **Hash verification for non-Python deps?** — Not needed. npm/bun/pnpm lockfiles already include integrity hashes (SHA-512) by default. `npm audit signatures` can verify registry signatures. Python is the outlier that needs explicit `--generate-hashes`.

**Bugs fixed during review:**
- **`mapfile` (bash 4+)** → replaced with `while IFS= read -r` loops in env-context (macOS ships bash 3.2)
- **`grep -oP`** → replaced with `sed -n 's/.../\1/p'` in env-context (macOS grep lacks `-P`)
- **`echo | xargs` trimming** → replaced with parameter expansion `${var##pattern}` in zshrc.sh replacement and env-context (avoids fork-per-line)
- **Semver range parsing** → `tr '-' ' '` corrupted ranges like `10.1.1-10.1.3`. Changed to comma-separated versions in IOC list, split on commas only
- **`deploy.sh --only`** → doesn't exist. Changed verification to `--minimal --pkg-configs`
- **`.envrc` in gitignore** → added as action item in Task 2 (currently missing from `config/ignore_global`)
- **pnpm global rc format** → global rc uses kebab-case INI (`minimum-release-age=10080`), not camelCase YAML. pnpm docs only document `pnpm-workspace.yaml` form, but global rc at `~/Library/Preferences/pnpm/rc` (macOS) works
- **`grep -oP` in envrc-init** → replaced with `sed -n 's/.../\1/p'` (macOS grep lacks `-P`)
- **`while IFS='=' read` value parsing** → replaced with two-phase `source` + selective `export` in zshrc.sh (handles shell quoting/expansion correctly)

**Tech Stack:** Shell (bash/zsh), Socket CLI, direnv, SOPS+age, launchd/cron, Claude Code hooks

**Key research findings:**
- [Axios compromise details](https://socket.dev/blog/axios-npm-package-compromised) — postinstall RAT, C2 at `sfrclak[.]com:8000`
- [Shai-Hulud advisory](https://www.csa.gov.sg/alerts-and-advisories/alerts/al-2025-093/) — self-propagating npm worm via TruffleHog credential scanning
- [npm ignore-scripts best practices](https://www.nodejs-security.com/blog/npm-ignore-scripts-best-practices-as-security-mitigation-for-malicious-packages) — only ~2% of npm registry uses postinstall
- [Socket CLI wrapper](https://docs.socket.dev/docs/socket-npm-socket-npx) — transparent npm/npx wrapping
- [Bun lifecycle docs](https://bun.sh/docs/pm/lifecycle) — bun ignores lifecycle scripts by default (only runs for `trustedDependencies`)
- [Python supply chain defense](https://bernat.tech/posts/securing-python-supply-chain/) — hash verification catches tampered packages
- [Phylum pre-commit hook](https://docs.phylum.io/phylum-ci/git_precommit) — lockfile analysis on commit
- **min-release-age** — 7-day quarantine would have blocked ALL three incidents (axios compromised versions published and caught within days). npm/bun/pnpm/uv all support this now.

**Current vulnerability:** `config/zshrc.sh:62` exports ALL API keys (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.) to every child process — any `npm postinstall` script can read them.

**Security model for credential isolation:** `.envrc` (via direnv) is the most secure entrypoint — no library auto-reads it unlike `.env` (which dotenv libraries may auto-load). Secrets are still exported as env vars when inside the project directory, but they're scoped: project A's secrets aren't visible in project B. This is a significant improvement over global export.

**Resolved: dotenv vs direnv** — dotenv reads `.env` files; direnv reads `.envrc`. They're different systems. With credential isolation, direnv exports secrets as env vars when you `cd` into a project — any code reading `os.environ` / `process.env` sees them. No dotenv needed. Projects currently using dotenv's `.env` can either (a) switch to direnv `.envrc`, or (b) have their `.env` generated from `.envrc` via `dotenv -e .envrc` or a simple `cp`.

---

## Implementation Order (low-risk first)

### Task 1: Package Manager Quarantine Configs (Layer 1 + 2)

**Highest leverage, zero risk.** min-release-age (7-day quarantine) would have blocked ALL three incidents. Combined with ignore-scripts, this covers both attack vectors: malicious new releases AND postinstall scripts.

**Files:**
- Create: `config/npmrc` (npm: ignore-scripts + min-release-age)
- Create: `config/bunfig.toml` (bun: min-release-age — already ignores scripts by default)
- Create: `config/uv.toml` (uv/pip: exclude-newer)
- Create: `config/pnpmrc` (pnpm: min-release-age in global rc, INI format, kebab-case)
- Modify: `deploy.sh` (add `deploy_pkg_configs()`)
- Modify: `config.sh` (add `DEPLOY_PKG_CONFIGS` flag)

**Notes:** Configs flat in `config/` (matches existing convention). Rust/Go/Zig lack min-release-age equivalents — add later if needed. pnpm global rc uses kebab-case INI at `~/Library/Preferences/pnpm/rc` (macOS) or `~/.config/pnpm/rc` (Linux).

- [ ] **Step 1: Create config files**

`config/npmrc`:
```ini
# Global npmrc — deployed by dotfiles (deploy.sh --pkg-configs)
# Supply chain defense: blocks postinstall scripts + quarantines new releases
# Override per-install: npm install --ignore-scripts=false
ignore-scripts=true
min-release-age=7
```

`config/bunfig.toml`:
```toml
# Global bunfig — deployed by dotfiles (deploy.sh --pkg-configs)
# bun already ignores lifecycle scripts by default (trustedDependencies)
# 7-day quarantine on new releases (604800 seconds)
[install]
minimumReleaseAge = 604800
```

`config/pnpmrc`:
```ini
# Global pnpm config — deployed by dotfiles (deploy.sh --pkg-configs)
# pnpm ignores lifecycle scripts by default in global installs
# 7-day quarantine on new releases (10080 minutes)
# Note: global rc uses kebab-case (INI); per-project pnpm-workspace.yaml uses camelCase (YAML)
minimum-release-age=10080
```

`config/uv.toml`:
```toml
# Global uv config — deployed by dotfiles (deploy.sh --pkg-configs)
# 7-day quarantine: won't install packages published in the last 7 days
exclude-newer = "7 days"
```

- [ ] **Step 2: Add deploy flag to `config.sh`**

Add `DEPLOY_PKG_CONFIGS=true` to the deploy components defaults section (near the other `DEPLOY_*` variables).

- [ ] **Step 3: Add `deploy_pkg_configs()` to `deploy.sh`**

Uses `safe_symlink()` (helpers.sh:208) — handles backup, parent dirs, error logging:

```bash
deploy_pkg_configs() {
    log_info "Deploying package manager security configs..."

    safe_symlink "$DOT_DIR/config/npmrc" "$HOME/.npmrc"
    safe_symlink "$DOT_DIR/config/bunfig.toml" "$HOME/.bunfig.toml"

    # pnpm global rc path is platform-specific
    local pnpm_config_dir
    if is_macos; then
        pnpm_config_dir="$HOME/Library/Preferences/pnpm"
    else
        pnpm_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/pnpm"
    fi
    mkdir -p "$pnpm_config_dir"
    safe_symlink "$DOT_DIR/config/pnpmrc" "$pnpm_config_dir/rc"

    local uv_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/uv"
    mkdir -p "$uv_config_dir"
    safe_symlink "$DOT_DIR/config/uv.toml" "$uv_config_dir/uv.toml"

    log_success "Package manager configs deployed — 7-day quarantine active"
}
```

Add flag parsing (`--pkg-configs`/`--no-pkg-configs`) and call in the deployment section.

- [ ] **Step 4: Verify**

```bash
./deploy.sh --minimal --pkg-configs
npm config get ignore-scripts        # → true
npm config get min-release-age       # → 7
# Verify symlinks exist
ls -la ~/.npmrc ~/.bunfig.toml
```

- [ ] **Step 5: Commit**

```bash
git add config/npmrc config/bunfig.toml config/pnpmrc config/uv.toml deploy.sh config.sh
git commit -m "feat: deploy package manager quarantine configs (7-day min-release-age + ignore-scripts)"
```

---

### Task 2: Claude Code Supply Chain Rule (Layer 4 + 8)

Zero-risk, behavioral guidance for Claude across all repos.

**Files:**
- Create: `claude/rules/supply-chain-security.md`

Rule auto-loads every session (passive). Hook (Task 3) is active enforcement.

- [ ] **Step 1: Create the rule file**

```markdown
# Supply Chain Security

## When Adding Dependencies

Before installing ANY new package (npm, pip, bun, uv), state:
1. Package name and exact version
2. Weekly downloads (check npm/PyPI)
3. Package age and maintainer count
4. Whether it has postinstall/lifecycle scripts

Flag packages with <1,000 weekly downloads or <6 months old as potential risks.

## min-release-age Quarantine (IMPORTANT)

All package managers are configured with a **7-day quarantine** (`min-release-age`). Packages published less than 7 days ago will fail to install. This is intentional — it blocks supply chain attacks that are typically caught within days.

**When install fails due to min-release-age:**
1. This is NOT a bug — it's working as intended
2. Tell the user: "Package X@Y was published less than 7 days ago. The 7-day quarantine is blocking it."
3. Suggest alternatives:
   - Wait for the quarantine to expire (safest)
   - Use a known-good older version: `npm install package@<previous-version>`
   - Override for this install only (user must confirm): `npm install --min-release-age=0 package`
4. **Never** silently bypass the quarantine or suggest disabling it globally

**Per-manager override syntax:**
- npm: `npm install --min-release-age=0 <pkg>`
- bun: `bun add --minimumReleaseAge=0 <pkg>` (or remove from bunfig.toml temporarily)
- pnpm: `pnpm add --minimum-release-age=0 <pkg>` (or set to 0 in global rc temporarily)
- uv: `uv pip install --exclude-newer '' <pkg>`

## Python Dependencies

- Use `uv pip compile --generate-hashes` to produce hash-pinned requirements
- Use `uv pip install --require-hashes -r requirements.txt` when installing
- For `uv add`: verify package on PyPI before adding

## JavaScript/TypeScript Dependencies

- Global `~/.npmrc` has `ignore-scripts=true` — do not override without user approval
- bun ignores lifecycle scripts by default (trustedDependencies allowlist)
- After adding dependencies: run `socket report` if socket CLI is available
- If lockfile changes, note added/removed/updated packages in commit message

## Never Do

- Install packages from arbitrary URLs or git repos without user approval
- Run `npm install --ignore-scripts=false` without explicit user confirmation
- Add packages to bun's `trustedDependencies` without stating why
- Skip hash verification for production Python dependencies
- Bypass min-release-age quarantine without explicit user approval

## Secrets Awareness

- API keys are scoped per-project via direnv `.envrc`, NOT globally exported
- If a project needs an API key, use `env-context` (fzf picker) or `envrc-init` to set up
- Never hardcode secrets; verify `.envrc` is in `.gitignore`
```

**Action required:** Add `.envrc` to `config/ignore_global` (currently only `.env` is listed at line 101). This prevents accidentally committing project-scoped secrets.

- [ ] **Step 2: Verify rule is auto-loaded**

Start a new Claude Code session — the rule should appear in the loaded rules list.

- [ ] **Step 3: Commit**

```bash
git add claude/rules/supply-chain-security.md
git commit -m "feat: add supply chain security rule for Claude Code"
```

---

### Task 3: Claude Code PreToolUse Hook (Layer 6)

Low-risk. Warns Claude when it runs package install commands.

**Files:**
- Create: `claude/hooks/warn_dep_install.sh`
- Modify: `claude/settings.json` (add hook to PreToolUse:Bash)

- [ ] **Step 1: Create the hook script**

`claude/hooks/warn_dep_install.sh`:

```bash
#!/bin/bash
# PreToolUse:Bash hook — supply chain warning on package install commands
set -euo pipefail

command=$(jq -r '.tool_input.command // ""')
[[ -z "$command" ]] && exit 0

# Detect package install commands (exit early if no match)
case "$command" in
    npm\ install*|npm\ i\ *|pnpm\ install*|pnpm\ add*|bun\ add*|bun\ install*) ;;
    pip\ install*|pip3\ install*|uv\ pip\ install*|uv\ add*|python*\ -m\ pip\ install*) ;;
    *) exit 0 ;;
esac

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    message: "[Supply Chain] Check package age, downloads, and maintainer count before installing. See rules/supply-chain-security.md for quarantine override syntax."
  }
}'
```

- [ ] **Step 2: Make executable**

```bash
chmod +x claude/hooks/warn_dep_install.sh
```

- [ ] **Step 3: Register in settings.json**

Add to the existing `PreToolUse` → `matcher: "Bash"` hooks array (after `nudge_modern_tools.sh` at line ~278):

```json
{
  "type": "command",
  "command": "$HOME/.claude/hooks/warn_dep_install.sh",
  "timeout": 3
}
```

- [ ] **Step 4: Verify**

In a Claude Code session, ask Claude to run `npm install lodash` — should see the supply chain warning in the hook output.

- [ ] **Step 5: Commit**

```bash
git add claude/hooks/warn_dep_install.sh claude/settings.json
git commit -m "feat: PreToolUse hook warns on package install commands"
```

---

### Task 4: Git Pre-Commit Lockfile Check (Layer 7)

Low-risk. Extends the existing global pre-commit hook.

**Sequencing note:** Task 4 is safe to deploy before Task 5 (socket/pip-audit installation). All tool invocations are guarded by `command -v` checks — the lockfile detection runs but audit commands are skipped if tools aren't installed. Installing Task 5 later automatically activates the scanning.

**Note:** Global hook at `config/git-hooks/pre-commit` via `core.hooksPath`. min-release-age only applies to resolution, not already-pinned lockfile versions — this hook and the weekly audit (Task 6) catch those.

**Files:**
- Modify: `config/git-hooks/pre-commit` (add lockfile detection section)

- [ ] **Step 1: Add lockfile audit section**

Insert between the GLOBAL CHECKS section (line 44) and the REPO-SPECIFIC HOOKS section (line 46):

```bash
# === LOCKFILE CHANGE DETECTION (Supply Chain Defense) ===
# When lockfiles change, run available audit tools

STAGED_FILES=$(git diff --cached --name-only 2>/dev/null || true)
LOCKFILE_CHANGED=""

for pattern in package-lock.json bun.lockb pnpm-lock.yaml yarn.lock uv.lock poetry.lock Pipfile.lock; do
    if echo "$STAGED_FILES" | grep -q "$pattern"; then
        LOCKFILE_CHANGED="$pattern"
        break
    fi
done

if [ -n "$LOCKFILE_CHANGED" ]; then
    echo "Pre-commit: Lockfile changed ($LOCKFILE_CHANGED) — checking for supply chain issues..."

    # Socket CLI (preferred — covers npm ecosystem)
    if command -v socket &>/dev/null && [[ "$LOCKFILE_CHANGED" =~ ^(package-lock|bun\.lockb|pnpm-lock|yarn\.lock) ]]; then
        if ! socket report --json 2>/dev/null | jq -e '.issues | length == 0' >/dev/null 2>&1; then
            echo "Pre-commit: socket found potential issues in $LOCKFILE_CHANGED. Review with: socket report"
            echo "  To bypass: git commit --no-verify"
            # Warning only — don't block (socket may flag non-critical issues)
        fi
    fi

    # pip-audit (Python lockfiles)
    if command -v pip-audit &>/dev/null && [[ "$LOCKFILE_CHANGED" =~ ^(uv\.lock|poetry\.lock|Pipfile\.lock) ]]; then
        if ! pip-audit 2>/dev/null; then
            echo "Pre-commit: pip-audit found vulnerabilities. Review above."
            echo "  To bypass: git commit --no-verify"
            exit 1
        fi
    fi
fi
```

- [ ] **Step 2: Verify**

In a JS project, modify package-lock.json, `git add` it, run `git commit` — should see the lockfile warning.

- [ ] **Step 3: Commit**

```bash
git add config/git-hooks/pre-commit
git commit -m "feat: pre-commit hook checks lockfile changes for supply chain issues"
```

---

### Task 5: Socket CLI + pip-audit Installation (Layer 3)

Medium risk — adds new global tools.

**Files:**
- Modify: `install.sh` (add socket CLI and pip-audit)
- Modify: `config/aliases.sh` (add socket wrapper aliases)

- [ ] **Step 1: Add to install.sh**

Socket CLI wraps npm/npx only; pip-audit covers Python. Add near other security/dev tools:

```bash
# Supply chain defense tools
if [[ "$INSTALL_AI_TOOLS" == "true" ]] || [[ "$INSTALL_EXTRAS" == "true" ]]; then
    # Socket CLI — wraps npm/npx with supply chain scanning
    if ! command -v socket &>/dev/null; then
        log_info "Installing Socket CLI..."
        npm install -g @socketsecurity/cli 2>/dev/null || log_warning "Socket CLI install failed (npm required)"
    fi

    # pip-audit — vulnerability scanner for Python dependencies
    if ! command -v pip-audit &>/dev/null; then
        log_info "Installing pip-audit..."
        uv tool install pip-audit 2>/dev/null || log_warning "pip-audit install failed"
    fi
fi
```

- [ ] **Step 2: Add socket wrapper aliases to `config/aliases.sh`**

```bash
# Supply chain defense: socket wraps npm/npx with security scanning
if command -v socket &>/dev/null; then
    alias npm="socket npm"
    alias npx="socket npx"
fi
```

- [ ] **Step 3: Verify**

```bash
socket --version
pip-audit --version
which npm  # Should show alias to socket npm
npm install express --dry-run  # Should show socket scanning
```

- [ ] **Step 4: Commit**

```bash
git add install.sh config/aliases.sh
git commit -m "feat: install socket CLI + pip-audit, alias npm to socket wrapper"
```

---

### Task 6: Periodic Dependency Audit (Layer 5)

Medium effort. Weekly scan across all repos.

Uses scheduler abstraction (`scripts/scheduler/scheduler.sh`), same pattern as `setup_brew_update.sh`.

**Files:**
- Create: `scripts/security/audit_dependencies.sh`
- Create: `scripts/security/known_bad_packages.txt`
- Create: `scripts/security/setup_dep_audit.sh`
- Modify: `deploy.sh` (add scheduled task registration)
- Modify: `config.sh` (add `DEPLOY_DEP_AUDIT` flag)

- [ ] **Step 1: Create `scripts/security/known_bad_packages.txt`**

IOC registry — compromised package names and versions:

```
# Known compromised packages (ecosystem:name:bad_versions:description)
# Lines starting with # are comments. Fields separated by colons.
npm:event-stream:3.3.6:cryptominer via flatmap-stream (2018)
npm:ua-parser-js:0.7.29:cryptominer (2021)
npm:coa:2.0.3:malware (2021)
npm:rc:1.2.9:malware (2021)
npm:colors:1.4.1:protestware infinite loop (2022)
npm:node-ipc:10.1.1,10.1.2,10.1.3:protestware peacenotwar (2022)
npm:axios:1.14.1:RAT via plain-crypto-js (2026-03)
npm:axios:0.30.4:RAT via plain-crypto-js (2026-03)
npm:plain-crypto-js:4.2.1:RAT payload for axios attack (2026-03)
pypi:litellm:1.82.8:credential exfil + K8s backdoor (2026-03)
# Filesystem IOC artifacts (type:path:description)
ioc:/Library/Caches/com.apple.act.mond:axios RAT macOS binary
ioc:/tmp/ld.py:axios RAT Linux payload
```

- [ ] **Step 2: Create `scripts/security/audit_dependencies.sh`**

```bash
#!/bin/bash
# Weekly dependency audit — scans repos for known-bad packages and filesystem IOCs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOWN_BAD="$SCRIPT_DIR/known_bad_packages.txt"
REPORT_DIR="$HOME/.local/share/dep-audit"
REPORT_FILE="$REPORT_DIR/report-$(date +%Y%m%d).txt"
SCAN_DIRS=("${CODE_DIR:-$HOME/code}" "${SCRATCH_DIR:-$HOME/scratch}" "${WRITING_DIR:-$HOME/writing}")

mkdir -p "$REPORT_DIR"
issues_found=0

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$REPORT_FILE"; }
log "=== Dependency Audit $(date) ==="

# --- Build grep patterns from KNOWN_BAD once ---
npm_patterns=()   # "name@version" pairs for grep
pypi_names=()     # package names for grep -i
while IFS=: read -r ecosystem name versions desc; do
    [[ "$ecosystem" =~ ^#.*$ || -z "$name" ]] && continue
    if [[ "$ecosystem" == "npm" ]]; then
        IFS=',' read -ra ver_list <<< "$versions"
        for ver in "${ver_list[@]}"; do
            ver="${ver## }"; ver="${ver%% }"
            npm_patterns+=("${name}@${ver}|\"$name\".*\"$ver\"")
        done
    elif [[ "$ecosystem" == "pypi" ]]; then
        pypi_names+=("$name")
    elif [[ "$ecosystem" == "ioc" && -e "$name" ]]; then
        log "CRITICAL: IOC artifact found: $name ($versions)"
        issues_found=$((issues_found + 1))
    fi
done < "$KNOWN_BAD"

# --- Scan lockfiles ---
for dir in "${SCAN_DIRS[@]}"; do
    [[ ! -d "$dir" ]] && continue
    log "Scanning $dir..."

    # JS lockfiles — grep with combined pattern
    if [[ ${#npm_patterns[@]} -gt 0 ]]; then
        npm_regex=$(IFS='|'; echo "${npm_patterns[*]}")
        while IFS= read -r lockfile; do
            matches=$(grep -cE "$npm_regex" "$lockfile" 2>/dev/null || true)
            if [[ "$matches" -gt 0 ]]; then
                log "CRITICAL: $lockfile has $matches known-bad package match(es)"
                issues_found=$((issues_found + matches))
            fi
        done < <(find "$dir" -maxdepth 4 \( -name "package-lock.json" -o -name "yarn.lock" -o -name "pnpm-lock.yaml" \) -not -path "*/node_modules/*" 2>/dev/null)
    fi

    # Python lockfiles
    if [[ ${#pypi_names[@]} -gt 0 ]]; then
        pypi_regex=$(IFS='|'; echo "${pypi_names[*]}")
        while IFS= read -r lockfile; do
            if grep -qiE "$pypi_regex" "$lockfile" 2>/dev/null; then
                log "WARNING: $lockfile references a known-bad Python package (verify version)"
                issues_found=$((issues_found + 1))
            fi
        done < <(find "$dir" -maxdepth 4 \( -name "uv.lock" -o -name "poetry.lock" -o -name "Pipfile.lock" \) -not -path "*/.venv/*" 2>/dev/null)
    fi
done

# --- Summary ---
log "=== Audit complete: $issues_found issue(s) found ==="
if [[ $issues_found -gt 0 ]]; then
    log "Review: $REPORT_FILE"
    if [[ "$(uname -s)" == "Darwin" ]]; then
        osascript -e "display notification \"$issues_found supply chain issue(s) found\" with title \"Dependency Audit\"" 2>/dev/null || true
    elif command -v notify-send &>/dev/null; then
        notify-send "Dependency Audit" "$issues_found issue(s) found" 2>/dev/null || true
    fi
    exit 1
fi

# Clean old reports (keep last 30)
ls -t "$REPORT_DIR"/report-*.txt 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null || true
```

- [ ] **Step 3: Create `scripts/security/setup_dep_audit.sh`**

Following the `setup_brew_update.sh` pattern exactly:

```bash
#!/bin/bash
# Setup weekly dependency audit (supply chain defense)
# Scans all repos for known-bad packages and IOC artifacts
# Runs every Sunday at 10:00 AM
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUDIT_BIN="$DOT_DIR/scripts/security/audit_dependencies.sh"

source "$DOT_DIR/scripts/scheduler/scheduler.sh"

JOB_ID="dep-audit"

uninstall() {
    unschedule "$JOB_ID" 2>/dev/null || true
}

install() {
    echo -e "${BLUE}==>${NC} Setting up weekly dependency audit..."

    if [[ ! -f "$AUDIT_BIN" ]]; then
        _sched_log_warn "Audit script not found at $AUDIT_BIN. Skipping."
        return 1
    fi

    chmod +x "$AUDIT_BIN"
    # Sunday at 10:00 AM
    schedule_weekly "$JOB_ID" "$AUDIT_BIN" 0 10 0
}

uninstall >/dev/null 2>&1 || true

if [[ "${1:-}" == "--uninstall" ]]; then
    _sched_log_info "Dependency audit uninstalled."
    exit 0
fi

install
```

- [ ] **Step 4: Add `dep-audit` alias**

In `config/aliases.sh`:

```bash
alias dep-audit='"$DOT_DIR/scripts/security/audit_dependencies.sh"'
```

- [ ] **Step 5: Register in deploy.sh**

Add to the scheduled tasks section following existing pattern. Add `DEPLOY_DEP_AUDIT=true` to `config.sh`.

- [ ] **Step 6: Verify**

```bash
chmod +x scripts/security/audit_dependencies.sh
./scripts/security/audit_dependencies.sh  # Manual run
# Should output "0 issue(s) found" for clean system
```

- [ ] **Step 7: Commit**

```bash
git add scripts/security/ config/aliases.sh deploy.sh config.sh
git commit -m "feat: weekly dependency audit with known-bad package IOC registry"
```

---

### Task 7: Credential Isolation (Layer 1)

**Highest impact, highest migration risk.** Currently `config/zshrc.sh:62` exports ALL secrets globally.

**Security model:** `.envrc` (via direnv) is the most secure entrypoint — no library auto-reads it (unlike `.env` which dotenv libraries may auto-load). When inside a project directory, direnv exports the secrets as env vars, which ARE visible to child processes. But secrets are **scoped**: project A's secrets aren't visible when you're in project B. This is a major improvement over the current global export.

**Files:**
- Modify: `config/zshrc.sh` (line 62 — stop exporting API keys globally)
- Create: `custom_bins/envrc-init` (CLI helper to bootstrap per-project `.envrc`)
- Create: `custom_bins/env-context` (fzf-based toggleable secret picker, like `claude-tools context`)

- [ ] **Step 1: Modify `config/zshrc.sh` line 62**

Replace the current global export with a two-phase approach: `source` (handles all shell syntax correctly) + selective export:

```bash
# Secrets: sensitive keys (API_KEY, TOKEN, SECRET) are NOT exported globally.
# Per-project via direnv .envrc — run 'env-context' or 'envrc-init' to set up.
if [ -f "$DOT_DIR/.secrets" ]; then
    # Phase 1: Source all vars as shell-local (NOT exported)
    source "$DOT_DIR/.secrets"

    # Phase 2: Export only non-sensitive vars (key names parsed via sed, not values)
    for key in $(sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' "$DOT_DIR/.secrets"); do
        case "$key" in
            *API_KEY*|*TOKEN*|*SECRET*|*PASSWORD*|*CREDENTIAL*) ;;
            *) export "$key" ;;
        esac
    done
fi
```

- [ ] **Step 2: Create `custom_bins/env-context`**

fzf-based secret picker, modeled after `claude-tools context` UX:

```bash
#!/bin/bash
# Per-project secret picker (fzf multi-select or CLI args)
# Usage: env-context              # fzf picker
#        env-context --list       # Show current .envrc keys
#        env-context --clean      # Remove .envrc
#        env-context KEY1 KEY2    # Non-interactive
set -euo pipefail

DOT_DIR="${DOT_DIR:-$HOME/code/dotfiles}"
SECRETS_FILE="$DOT_DIR/.secrets"
ENVRC=".envrc"

[[ ! -f "$SECRETS_FILE" ]] && { echo "Error: $SECRETS_FILE not found" >&2; exit 1; }

# Extract sensitive key names from secrets file
get_sensitive_keys() {
    sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' "$SECRETS_FILE" \
        | grep -E 'API_KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL'
}

case "${1:-}" in
    --list)
        [[ ! -f "$ENVRC" ]] && { echo "No .envrc in current directory"; exit 0; }
        echo "Current .envrc keys:"
        sed -n 's/^export \([A-Za-z_][A-Za-z0-9_]*\)=.*/  \1/p' "$ENVRC"
        exit 0
        ;;
    --clean)
        [[ -f "$ENVRC" ]] && { trash "$ENVRC" 2>/dev/null || rm "$ENVRC"; echo "Removed .envrc"; } || echo "No .envrc to remove"
        exit 0
        ;;
esac

if [[ $# -gt 0 ]]; then
    selected_keys=("$@")
else
    command -v fzf &>/dev/null || { echo "Error: fzf required. Use: env-context KEY1 KEY2" >&2; exit 1; }

    # Build --select args from existing .envrc keys
    select_args=()
    if [[ -f "$ENVRC" ]]; then
        while IFS= read -r k; do
            [[ -n "$k" ]] && select_args+=(--select "$k")
        done < <(sed -n 's/^export \([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' "$ENVRC")
    fi

    selected=$(get_sensitive_keys | fzf --multi \
        --prompt="Select secrets for $(basename "$PWD")> " \
        --header="TAB to toggle, ENTER to confirm" \
        "${select_args[@]}" 2>/dev/null) || exit 0

    selected_keys=()
    while IFS= read -r k; do
        [[ -n "$k" ]] && selected_keys+=("$k")
    done <<< "$selected"
fi

# Write .envrc
{
    echo "# Auto-generated by env-context — re-run to modify, --clean to remove"
    for key in "${selected_keys[@]}"; do
        value=$(grep "^${key}=" "$SECRETS_FILE" | head -1 | cut -d= -f2-)
        [[ -n "$value" ]] && echo "export ${key}=${value}" || echo "# WARNING: $key not found"
    done
} > "$ENVRC"

# Ensure .envrc is gitignored
if [[ -f .gitignore ]] && ! grep -q '^\.envrc$' .gitignore; then
    echo ".envrc" >> .gitignore
    echo "Added .envrc to .gitignore"
fi

direnv allow .
echo "${#selected_keys[@]} key(s) scoped to $(basename "$PWD"). Auto-loads on cd."
```

- [ ] **Step 3: Create `custom_bins/envrc-init`**

Simpler non-interactive helper (for scripting and Claude agents):

```bash
#!/bin/bash
# Bootstrap a .envrc for the current project (non-interactive)
# Usage: envrc-init ANTHROPIC_API_KEY OPENAI_API_KEY OPENROUTER_API_KEY  # Specific keys
#        envrc-init --all                              # All keys (NOT recommended)
#        envrc-init --sops                             # SOPS-based decryption template
# For interactive picker, use: env-context
set -euo pipefail

DOT_DIR="${DOT_DIR:-$HOME/code/dotfiles}"
SECRETS_FILE="$DOT_DIR/.secrets"

case "${1:-}" in
    --sops)
        cp "$DOT_DIR/config/envrc_sops_template" .envrc
        echo "Created .envrc with SOPS decryption template"
        direnv allow .
        exit 0
        ;;
    --all)
        exec env-context $(sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' "$SECRETS_FILE" | grep -E 'API_KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL')
        ;;
    "")
        echo "Usage: envrc-init KEY1 [KEY2 ...]" >&2
        echo "  For interactive picker: env-context" >&2
        exit 1
        ;;
    *)
        exec env-context "$@"
        ;;
esac
```

- [ ] **Step 4: Make executable**

```bash
chmod +x custom_bins/env-context custom_bins/envrc-init
```

- [ ] **Step 5: Test the migration**

1. Open a new shell
2. Run `env | grep API_KEY` — should show nothing
3. `cd ~/code/some-project && env-context` — fzf picker, select ANTHROPIC_API_KEY
4. Run `env | grep ANTHROPIC_API_KEY` — should show the key
5. `cd ~ && env | grep ANTHROPIC_API_KEY` — should show nothing again
6. `env-context --list` in project — shows selected keys
7. `env-context --clean` — removes .envrc

- [ ] **Step 6: Bootstrap .envrc in active projects**

Run `env-context` in each project that needs API keys. Most projects only need 1-2 keys:
- AI safety research repos: `ANTHROPIC_API_KEY` (and maybe `OPENAI_API_KEY`, `OPENROUTER_API_KEY`)
- HuggingFace repos: `HF_TOKEN`
- Modal repos: `MODAL_TOKEN_ID MODAL_TOKEN_SECRET`

- [ ] **Step 7: Commit**

```bash
git add config/zshrc.sh custom_bins/env-context custom_bins/envrc-init
git commit -m "feat: credential isolation — API keys scoped per-project via direnv + fzf picker"
```

---

### Task 8: Documentation Update

**Files:**
- Modify: `CLAUDE.md` (update secrets section, add supply chain defense docs)
- Modify: `README.md` (add supply chain section)

- [ ] **Step 1: Update CLAUDE.md**

In the "Deployment Components" section, add:
- Package manager configs — Global npmrc, bunfig.toml, pnpm rc, uv.toml with 7-day min-release-age + ignore-scripts (symlinked)
- Dependency audit — Weekly scan for known-bad packages (launchd/cron)

In the "Encrypted Secrets" section, update:
- Note that API keys are NO LONGER globally exported
- Document `env-context` (fzf picker) and `envrc-init` workflow
- Document `dep-audit` alias

In the "Important Gotchas" section, add:
- **Secrets are per-project**: API keys require `env-context` or `envrc-init` in each project. Running `npm postinstall` or `pip install` in a project without `.envrc` cannot access secrets (this is intentional — supply chain defense)
- **min-release-age quarantine**: All package managers have a 7-day delay on new releases. Packages published <7 days ago will fail to install. This is intentional. See `claude/rules/supply-chain-security.md` for override syntax
- **min-release-age agent confusion**: Claude Code agents may encounter install failures due to quarantine and think it's a bug. The supply chain rule (`rules/supply-chain-security.md`) instructs agents to recognize this and suggest alternatives rather than bypassing

- [ ] **Step 2: Update README.md**

Add a "Supply Chain Security" section covering all 8 layers.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: document supply chain defense layers"
```

---

## Verification Checklist

After all tasks are complete:

- [ ] `npm config get ignore-scripts` → `true`
- [ ] `npm config get min-release-age` → `7`
- [ ] `env | grep API_KEY` in new shell → nothing
- [ ] `cd` into project with `.envrc` → keys appear
- [ ] `cd` out → keys disappear
- [ ] `env-context --list` in project → shows selected keys
- [ ] `env-context --clean` → removes .envrc
- [ ] Claude Code session shows supply chain rule loaded
- [ ] Ask Claude to `npm install lodash` → PreToolUse warning appears
- [ ] Modify a lockfile + `git commit` → pre-commit lockfile check runs
- [ ] `dep-audit` (alias) runs clean on current system
- [ ] `launchctl list | grep dep-audit` (macOS) shows scheduled job
- [ ] Try installing a package published <7 days ago → blocked by quarantine
