# Parallel Installs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Speed up install.sh, deploy.sh, and setup.sh by running independent network-bound operations in parallel with grouped log replay and failure summary.

**Architecture:** Add a `run_parallel` helper to `helpers.sh` that backgrounds jobs, captures output per-job, waits, then replays logs grouped by job with a pass/fail summary. Refactor inline install blocks into named functions. Apply `run_parallel` to 3 groups in install.sh, 1 group in deploy.sh, 1 group in setup.sh. ~30-40% faster on fresh installs.

**Tech Stack:** ZSH, background subshells, `mktemp`, `wait`, trap-based exit code capture.

**Key design decisions (from Codex review):**
- No spinner — simple "running..." line, full log replay at end
- `set +e` inside subshells + trap to always write exit code
- Pre-set PATH in parent before parallel groups (subshells can't propagate env)
- mise stays sequential (concurrent `mise use -g` corrupts config)
- Always return 0 (continue-on-failure), print failures clearly in summary

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `scripts/shared/helpers.sh` | Modify | Add `run_parallel` helper + 6 new install functions |
| `install.sh` | Modify | Replace inline blocks with function calls + `run_parallel` groups |
| `deploy.sh` | Modify | Wrap cleanup setup scripts in `run_parallel` |
| `scripts/cloud/setup.sh` | Modify | Parallel bun + uv installs |

---

### Task 1: Add `run_parallel` helper to helpers.sh

**Files:**
- Modify: `scripts/shared/helpers.sh` (append after line ~318, before ZSH Setup section)

- [ ] **Step 1: Add `run_parallel` function**

Append to `scripts/shared/helpers.sh` before the `# ─── ZSH Setup` line (currently line 320):

```zsh
# ─── Parallel Execution ──────────────────────────────────────────────────────

# Run multiple commands in parallel with grouped log replay.
# Usage: run_parallel "group label" "job_name|command_or_function" ...
# - Each job runs in a subshell with set +e, stdout+stderr captured to a temp log
# - Exit code captured via trap (always written, even on early exit)
# - After all jobs finish: replay each job's log grouped under its name
# - Print summary with pass/fail counts and list of failures
# - Sets PARALLEL_FAILURES array in caller's scope
# - Always returns 0 (continue-on-failure)
run_parallel() {
    local group_label="$1"
    shift

    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/parallel_run.XXXXXX")

    typeset -A pids
    local job_names=()

    log_info "$group_label..."

    for entry in "$@"; do
        local name="${entry%%|*}"
        local cmd="${entry#*|}"
        job_names+=("$name")

        (
            set +e
            local rc=0
            trap 'echo $rc > "'"$tmpdir/$name"'.exitcode"' EXIT
            eval "$cmd"
            rc=$?
        ) &>"$tmpdir/$name.log" &
        pids[$name]=$!
    done

    # Wait for all jobs
    for name in "${job_names[@]}"; do
        wait ${pids[$name]} 2>/dev/null || true
    done

    # Replay logs and collect results
    local passed=0 failed=0
    PARALLEL_FAILURES=()

    for name in "${job_names[@]}"; do
        local rc=0
        [[ -f "$tmpdir/$name.exitcode" ]] && rc=$(<"$tmpdir/$name.exitcode")

        if [[ "$rc" -eq 0 ]]; then
            echo "  ── $name ──"
            ((passed++))
        else
            echo "  ── $name (FAILED) ──"
            PARALLEL_FAILURES+=("$name")
            ((failed++))
        fi
        cat "$tmpdir/$name.log" 2>/dev/null
    done

    # Summary
    if [[ $failed -gt 0 ]]; then
        log_warning "$group_label: $passed passed, $failed failed: ${PARALLEL_FAILURES[*]}"
    else
        log_success "$group_label: $passed/$passed completed"
    fi

    # Cleanup
    rm -rf "$tmpdir"
    return 0
}
```

- [ ] **Step 2: Verify helpers.sh still sources cleanly**

Run: `zsh -c 'source /Users/yulong/code/dotfiles/config.sh && source /Users/yulong/code/dotfiles/scripts/shared/helpers.sh && echo OK'`
Expected: `OK` with no errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/shared/helpers.sh
git commit -m "feat: add run_parallel helper for parallel job execution with grouped log replay"
```

---

### Task 2: Extract install functions for Linux binary downloads

**Files:**
- Modify: `scripts/shared/helpers.sh` (add 4 functions before `run_parallel`)

These functions encapsulate the inline install blocks from install.sh lines 133-205. Each uses `mktemp -d` instead of hardcoded `/tmp` paths.

- [ ] **Step 1: Add `install_gitleaks` function**

Add before the `# ─── Parallel Execution` section in helpers.sh:

```zsh
# ─── Parallelizable Install Functions ────────────────────────────────────────

install_gitleaks() {
    if is_installed gitleaks; then return 0; fi
    log_info "Installing gitleaks..."
    if is_macos; then
        brew_install gitleaks
    else
        local version arch tmpd
        version=$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest | grep -o '"tag_name": "v[^"]*' | cut -d'v' -f2 || echo "8.24.3")
        case "$(uname -m)" in
            x86_64)  arch="x64" ;;
            aarch64) arch="arm64" ;;
            *)       log_warning "Unsupported architecture for gitleaks"; return 1 ;;
        esac
        tmpd=$(mktemp -d)
        mkdir -p "$HOME/.local/bin"
        curl -sSL "https://github.com/gitleaks/gitleaks/releases/download/v${version}/gitleaks_${version}_linux_${arch}.tar.gz" -o "$tmpd/gitleaks.tar.gz" && \
        tar -xzf "$tmpd/gitleaks.tar.gz" -C "$tmpd" && \
        mv "$tmpd/gitleaks" "$HOME/.local/bin/" && \
        log_success "gitleaks $version installed" || { log_warning "gitleaks installation failed"; rm -rf "$tmpd"; return 1; }
        rm -rf "$tmpd"
    fi
}
```

- [ ] **Step 2: Add `install_sops` function**

```zsh
install_sops() {
    if is_installed sops; then return 0; fi
    log_info "Installing sops..."
    if is_macos; then
        brew_install sops
    else
        local sops_ver sops_arch
        sops_ver=$(curl -s https://api.github.com/repos/getsops/sops/releases/latest | grep -o '"tag_name": "v[^"]*' | cut -d'v' -f2)
        sops_ver="${sops_ver:-3.9.4}"
        case "$(uname -m)" in
            x86_64)  sops_arch="amd64" ;;
            aarch64) sops_arch="arm64" ;;
            *)       log_warning "Unsupported architecture for sops"; return 1 ;;
        esac
        mkdir -p "$HOME/.local/bin"
        curl -sSL "https://github.com/getsops/sops/releases/download/v${sops_ver}/sops-v${sops_ver}.linux.${sops_arch}" -o "$HOME/.local/bin/sops" && \
            chmod +x "$HOME/.local/bin/sops" && \
            log_success "sops $sops_ver installed" || { log_warning "sops installation failed"; return 1; }
    fi
}
```

- [ ] **Step 3: Add `install_age` function**

```zsh
install_age() {
    if is_installed age; then return 0; fi
    log_info "Installing age..."
    if is_macos; then
        brew_install age
    else
        local age_ver age_arch tmpd
        age_ver=$(curl -s https://api.github.com/repos/FiloSottile/age/releases/latest | grep -o '"tag_name": "v[^"]*' | cut -d'v' -f2)
        age_ver="${age_ver:-1.2.1}"
        case "$(uname -m)" in
            x86_64)  age_arch="amd64" ;;
            aarch64) age_arch="arm64" ;;
            *)       log_warning "Unsupported architecture for age"; return 1 ;;
        esac
        tmpd=$(mktemp -d)
        mkdir -p "$HOME/.local/bin"
        curl -sSL "https://github.com/FiloSottile/age/releases/download/v${age_ver}/age-v${age_ver}-linux-${age_arch}.tar.gz" -o "$tmpd/age.tar.gz" && \
            tar -xzf "$tmpd/age.tar.gz" -C "$tmpd" && \
            mv "$tmpd/age/age" "$tmpd/age/age-keygen" "$HOME/.local/bin/" && \
            log_success "age $age_ver installed" || { log_warning "age installation failed"; rm -rf "$tmpd"; return 1; }
        rm -rf "$tmpd"
    fi
}
```

- [ ] **Step 4: Add `install_direnv` function**

```zsh
install_direnv() {
    if is_installed direnv; then return 0; fi
    log_info "Installing direnv..."
    if is_macos; then
        brew_install direnv
    else
        curl -sfL https://direnv.net/install.sh | bash 2>/dev/null || { log_warning "direnv installation failed"; return 1; }
    fi
}
```

- [ ] **Step 5: Verify helpers.sh still sources cleanly**

Run: `zsh -c 'source /Users/yulong/code/dotfiles/config.sh && source /Users/yulong/code/dotfiles/scripts/shared/helpers.sh && type install_gitleaks && type install_sops && type install_age && type install_direnv && echo OK'`
Expected: All 4 functions found, `OK`.

- [ ] **Step 6: Commit**

```bash
git add scripts/shared/helpers.sh
git commit -m "refactor: extract install_gitleaks, install_sops, install_age, install_direnv into named functions"
```

---

### Task 3: Extract AI tool install functions

**Files:**
- Modify: `scripts/shared/helpers.sh` (add 3 functions after the ones from Task 2)

These encapsulate install.sh lines 287-331. Note: bun must install before Gemini/Codex on Linux (they depend on `bun add -g`).

- [ ] **Step 1: Add `install_claude_code` function**

```zsh
install_claude_code() {
    if is_installed claude; then return 0; fi
    log_info "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash || { log_warning "Claude Code installation failed"; return 1; }
    # Alpine Linux dependencies
    if is_linux && cmd_exists apk; then
        apk add libgcc libstdc++ ripgrep 2>/dev/null || true
        export USE_BUILTIN_RIPGREP=0
    fi
}
```

- [ ] **Step 2: Add `install_gemini_cli` function**

```zsh
install_gemini_cli() {
    if is_installed gemini; then return 0; fi
    log_info "Installing Gemini CLI..."
    if is_macos; then
        brew_install gemini-cli
    elif cmd_exists bun; then
        bun add -g @google/gemini-cli &>/dev/null || { log_warning "Gemini CLI failed"; return 1; }
    else
        log_warning "bun is required to install Gemini CLI on Linux; skipping"
        return 1
    fi
}
```

- [ ] **Step 3: Add `install_codex_cli` function**

```zsh
install_codex_cli() {
    if is_installed codex; then return 0; fi
    log_info "Installing Codex CLI..."
    if is_macos; then
        brew_install codex
    elif cmd_exists bun; then
        bun add -g @openai/codex &>/dev/null || { log_warning "Codex CLI failed"; return 1; }
    else
        log_warning "bun is required to install Codex CLI on Linux; skipping"
        return 1
    fi
}
```

- [ ] **Step 4: Verify**

Run: `zsh -c 'source /Users/yulong/code/dotfiles/config.sh && source /Users/yulong/code/dotfiles/scripts/shared/helpers.sh && type install_claude_code && type install_gemini_cli && type install_codex_cli && echo OK'`
Expected: All 3 found, `OK`.

- [ ] **Step 5: Commit**

```bash
git add scripts/shared/helpers.sh
git commit -m "refactor: extract install_claude_code, install_gemini_cli, install_codex_cli into named functions"
```

---

### Task 4: Wire up parallel groups in install.sh

**Files:**
- Modify: `install.sh` (lines 131-208 for binary downloads, lines 275-331 for AI tools)

**Critical:** Pre-set PATH before parallel groups so subshells can find tools, and so the parent has the right PATH after subshells finish.

- [ ] **Step 1: Replace Linux binary downloads with `run_parallel` (lines 131-208)**

Replace the gitleaks/sops/age/direnv blocks AND the PATH export at line 208 with:

```zsh
# ─── Security & Secrets Tools ────────────────────────────────────────────────

# Pre-set PATH so subshells and subsequent commands can find installed binaries
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

if is_linux; then
    run_parallel "Installing security tools" \
        "gitleaks|install_gitleaks" \
        "sops|install_sops" \
        "age|install_age" \
        "direnv|install_direnv"
else
    # macOS: brew has a global lock, must run sequentially
    install_gitleaks
    install_sops
    install_age
    install_direnv
fi
```

Note: On macOS these call `brew_install` which takes a global lock — cannot parallelize. On Linux they're independent `curl` downloads.

- [ ] **Step 2: Replace AI tool installs with `run_parallel` (lines 275-331)**

Replace the Claude/bun/Gemini/Codex blocks with:

```zsh
if [[ "$INSTALL_AI_TOOLS" == "true" ]]; then
    log_section "INSTALLING AI CLI TOOLS"

    # Rust toolchain (needed for claude-tools build in deploy.sh)
    if ! is_installed cargo; then
        log_info "Installing Rust toolchain (user-level, no root needed)..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --quiet
    fi
    source "$HOME/.cargo/env" 2>/dev/null || true

    # Pre-set PATH for subshells
    [[ -d "$HOME/.claude/bin" ]] && export PATH="$HOME/.claude/bin:$PATH"

    # Bun must install before Gemini/Codex on Linux (they need `bun add -g`)
    if is_linux && ! cmd_exists bun; then
        log_info "Installing bun..."
        curl -fsSL https://bun.sh/install | bash
        export BUN_INSTALL="$HOME/.bun"
        export PATH="$BUN_INSTALL/bin:$PATH"
    fi

    if is_macos; then
        # brew has a global lock — sequential
        install_claude_code
        install_gemini_cli
        install_codex_cli
    else
        run_parallel "Installing AI CLI tools" \
            "claude|install_claude_code" \
            "gemini|install_gemini_cli" \
            "codex|install_codex_cli"
    fi

    # Coven (macOS only, lightweight Claude interface)
    if is_macos && ! is_installed coven; then
        log_info "Installing Coven..."
        brew tap Crazytieguy/tap 2>/dev/null && brew_install coven || log_warning "Coven installation failed"
    fi

    # MCP servers (sequential — unclear if concurrent-safe)
    if cmd_exists claude; then
        log_info "Configuring MCP servers..."
        for server in "${MCP_SERVERS[@]}"; do
            IFS=':' read -r name url <<< "$server"
            claude mcp remove "$name" &>/dev/null || true
            if [[ "$url" == npx* ]]; then
                args="${url#npx }"
                claude mcp add-json --scope user "$name" "{\"command\":\"npx\",\"args\":[\"${args}\"]}" 2>&1 && \
                    log_success "$name configured" || log_warning "$name failed"
            else
                claude mcp add --scope user --transport http "$name" "$url" 2>&1 && \
                    log_success "$name configured" || log_warning "$name failed"
            fi
        done
    fi

    # Local MCP servers (sequential — clone + build + register)
    if cmd_exists go && cmd_exists claude && [[ ${#MCP_SERVERS_LOCAL[@]} -gt 0 ]]; then
        log_info "Building local MCP servers..."
        mcp_base="$HOME/code/marketplaces"
        mkdir -p "$mcp_base"

        for entry in "${MCP_SERVERS_LOCAL[@]}"; do
            IFS=':' read -r name repo binary token_var <<< "$entry"
            repo_dir="$mcp_base/$(basename "$repo")"
            binary_path="$repo_dir/$binary"

            if [[ -d "$repo_dir/.git" ]]; then
                log_info "  Updating $name..."
                git -C "$repo_dir" pull --rebase --quiet 2>/dev/null || true
            else
                log_info "  Cloning $name..."
                git clone --quiet "https://github.com/$repo.git" "$repo_dir" 2>/dev/null || {
                    log_warning "$name: clone failed"; continue
                }
            fi

            log_info "  Building $name..."
            (cd "$repo_dir" && go build -o "$binary" ./cmd/"$binary") 2>/dev/null || {
                log_warning "$name: build failed"; continue
            }

            token_value="${!token_var:-}"
            claude mcp remove "$name" &>/dev/null || true
            if [[ -n "$token_value" ]]; then
                claude mcp add-json --scope user "$name" \
                    "{\"command\":\"$binary_path\",\"args\":[\"--transport\",\"stdio\"],\"env\":{\"$token_var\":\"$token_value\"}}" 2>&1 && \
                    log_success "$name configured" || log_warning "$name MCP registration failed"
            else
                log_warning "$name: $token_var not set — skipping MCP registration (build complete)"
            fi
        done
    elif [[ ${#MCP_SERVERS_LOCAL[@]} -gt 0 ]]; then
        log_warning "Go not installed — skipping local MCP servers"
    fi

    # markitdown
    if ! is_installed markitdown; then
        log_info "Installing markitdown..."
        if cmd_exists uv; then
            uv tool install 'markitdown[pdf,docx,pptx,xlsx,youtube-transcription]' 2>/dev/null
        elif cmd_exists pipx; then
            pipx install 'markitdown[pdf,docx,pptx,xlsx,youtube-transcription]' 2>/dev/null
        else
            pip install 'markitdown[pdf,docx,pptx,xlsx,youtube-transcription]' 2>/dev/null
        fi || log_warning "markitdown installation failed"
    fi

    log_success "AI CLI tools installation complete"
fi
```

- [ ] **Step 3: Verify install.sh parses without errors**

Run: `zsh -n /Users/yulong/code/dotfiles/install.sh`
Expected: No syntax errors.

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat: parallelize Linux binary downloads and AI tool installs"
```

---

### Task 5: Wire up parallel group in deploy.sh

**Files:**
- Modify: `deploy.sh` (lines 794-850, the cleanup/scheduled setup scripts)

The cleanup setup scripts are independent launchd/cron installers. None use `sudo` (verified: they write to `~/Library/LaunchAgents/` or user crontab). Gist sync setup stays sequential (may prompt for `gh auth`).

- [ ] **Step 1: Replace sequential cleanup setups with `run_parallel` (lines 794-850)**

Replace the claude-cleanup, tmpdir-cleanup, ai-update, brew-update, keyboard-repeat blocks with:

```zsh
# ─── Scheduled Tasks (parallel — independent launchd/cron jobs) ──────────────

{
    local scheduled_jobs=()

    if [[ "$DEPLOY_CLAUDE_CLEANUP" == "true" ]]; then
        [[ -f "$DOT_DIR/scripts/cleanup/setup_claude_cleanup.sh" ]] && \
            scheduled_jobs+=("claude-cleanup|$DOT_DIR/scripts/cleanup/setup_claude_cleanup.sh")
        [[ -f "$DOT_DIR/scripts/cleanup/setup_claude_tmpdir_cleanup.sh" ]] && \
            scheduled_jobs+=("tmpdir-cleanup|$DOT_DIR/scripts/cleanup/setup_claude_tmpdir_cleanup.sh")
    fi

    if [[ "$DEPLOY_AI_UPDATE" == "true" ]]; then
        [[ -f "$DOT_DIR/scripts/cleanup/setup_ai_update.sh" ]] && \
            scheduled_jobs+=("ai-update|$DOT_DIR/scripts/cleanup/setup_ai_update.sh")
    fi

    if [[ "$DEPLOY_BREW_UPDATE" == "true" ]]; then
        [[ -f "$DOT_DIR/scripts/cleanup/setup_brew_update.sh" ]] && \
            scheduled_jobs+=("brew-update|$DOT_DIR/scripts/cleanup/setup_brew_update.sh")
    fi

    if [[ "$DEPLOY_KEYBOARD" == "true" ]] && is_macos; then
        [[ -f "$DOT_DIR/scripts/cleanup/setup_keyboard_repeat.sh" ]] && \
            scheduled_jobs+=("keyboard-repeat|$DOT_DIR/scripts/cleanup/setup_keyboard_repeat.sh")
    fi

    if (( ${#scheduled_jobs[@]} > 0 )); then
        log_section "INSTALLING SCHEDULED TASKS"
        run_parallel "Setting up scheduled tasks" "${scheduled_jobs[@]}"
    fi
}
```

Keep the bedtime, text-replacements, and VPN blocks sequential (they're opt-in, interactive, or use `sudo`).

- [ ] **Step 2: Verify deploy.sh parses without errors**

Run: `zsh -n /Users/yulong/code/dotfiles/deploy.sh`
Expected: No syntax errors.

- [ ] **Step 3: Commit**

```bash
git add deploy.sh
git commit -m "feat: parallelize scheduled task setup in deploy.sh"
```

---

### Task 6: Wire up parallel group in setup.sh

**Files:**
- Modify: `scripts/cloud/setup.sh` (lines 207-225, bun + uv installs)

setup.sh uses `#!/bin/bash` (not zsh) and `run_as` for user-context execution. Cannot source `run_parallel` from helpers.sh (requires zsh + config.sh). Use simple indexed arrays (no associative arrays — avoids bash version concerns) since there are only 2 jobs.

- [ ] **Step 1: Replace sequential bun + uv with parallel installs (lines 207-225)**

Replace:
```bash
# ─── Bun ─────────────────────────────────────────────────────────────────────
step "Bun"
if ! run_as 'command -v bun' &>/dev/null; then
    log "Installing bun..."
    run_as 'curl -fsSL https://bun.sh/install | bash'
    ok "Bun installed"
else
    ok "Bun already installed"
fi

# ─── uv ──────────────────────────────────────────────────────────────────────
step "uv"
if ! run_as 'command -v uv' &>/dev/null; then
    log "Installing uv..."
    run_as 'curl -LsSf https://astral.sh/uv/install.sh | sh'
    ok "uv installed"
else
    ok "uv already installed"
fi
```

With:
```bash
# ─── Bun + uv (parallel) ────────────────────────────────────────────────────
step "Bun + uv"

bun_pid="" bun_log=""
uv_pid="" uv_log=""

if ! run_as 'command -v bun' &>/dev/null; then
    bun_log=$(mktemp)
    run_as 'curl -fsSL https://bun.sh/install | bash' &>"$bun_log" &
    bun_pid=$!
else
    ok "Bun already installed"
fi

if ! run_as 'command -v uv' &>/dev/null; then
    uv_log=$(mktemp)
    run_as 'curl -LsSf https://astral.sh/uv/install.sh | sh' &>"$uv_log" &
    uv_pid=$!
else
    ok "uv already installed"
fi

for name in bun uv; do
    eval "pid=\${${name}_pid:-}"
    eval "logfile=\${${name}_log:-}"
    [[ -z "$pid" ]] && continue
    if wait "$pid" 2>/dev/null; then
        ok "$name installed"
    else
        warn "$name installation failed"
    fi
    echo "  ── $name ──"
    cat "$logfile" 2>/dev/null
    rm -f "$logfile"
done
```

- [ ] **Step 2: Verify setup.sh parses without errors**

Run: `bash -n /Users/yulong/code/dotfiles/scripts/cloud/setup.sh`
Expected: No syntax errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/cloud/setup.sh
git commit -m "feat: parallelize bun + uv installs in cloud setup"
```

---

### Task 7: Background cargo build in deploy.sh

**Files:**
- Modify: `deploy.sh` (lines 569-582, claude-tools build)

The cargo build is the slowest single operation in deploy.sh (~30s). Run it in the background while symlink operations proceed, then wait before the done message.

- [ ] **Step 1: Background the cargo build**

Replace the claude-tools block (lines 569-582) with:

```zsh
# ─── claude-tools (Rust binary, backgrounded) ───────────────────────────────

CLAUDE_TOOLS_PID=""
CLAUDE_TOOLS_LOG=""
if [[ "$DEPLOY_CLAUDE_TOOLS" == "true" ]] && [[ -f "$DOT_DIR/tools/claude-tools/Cargo.toml" ]] && cmd_exists cargo; then
    log_info "Building claude-tools (background)..."
    CLAUDE_TOOLS_LOG=$(mktemp)
    (
        cd "$DOT_DIR/tools/claude-tools" && cargo build --release --quiet 2>&1 && \
        cp "$DOT_DIR/tools/claude-tools/target/release/claude-tools" "$DOT_DIR/custom_bins/claude-tools" && \
        chmod +x "$DOT_DIR/custom_bins/claude-tools"
    ) &>"$CLAUDE_TOOLS_LOG" &
    CLAUDE_TOOLS_PID=$!
fi
```

- [ ] **Step 2: Wait for cargo build before the "Done" section**

Add before the `# ─── Done` section at the end of deploy.sh (before line 921):

```zsh
# ─── Wait for background builds ─────────────────────────────────────────────

if [[ -n "${CLAUDE_TOOLS_PID:-}" ]]; then
    if wait "$CLAUDE_TOOLS_PID" 2>/dev/null; then
        log_success "claude-tools built and deployed to custom_bins/"
    else
        log_warning "claude-tools build failed (bash fallback will be used)"
    fi
    [[ -f "$CLAUDE_TOOLS_LOG" ]] && cat "$CLAUDE_TOOLS_LOG" && rm -f "$CLAUDE_TOOLS_LOG"
fi
```

- [ ] **Step 3: Verify deploy.sh parses without errors**

Run: `zsh -n /Users/yulong/code/dotfiles/deploy.sh`
Expected: No syntax errors.

- [ ] **Step 4: Commit**

```bash
git add deploy.sh
git commit -m "feat: background claude-tools cargo build in deploy.sh"
```

---

### Task 8: Smoke test on macOS

**Files:** None (testing only)

- [ ] **Step 1: Run install.sh with --only to test a parallel group**

Run: `cd /Users/yulong/code/dotfiles && ./install.sh --only core --non-interactive 2>&1 | tail -30`

Verify: Security tools section shows grouped log replay (on macOS these run sequentially, but the function calls should work).

- [ ] **Step 2: Run deploy.sh with --only to test scheduled tasks group**

Run: `cd /Users/yulong/code/dotfiles && ./deploy.sh --only claude-cleanup,ai-update,brew-update --non-interactive 2>&1 | tail -30`

Verify: "Setting up scheduled tasks" section shows grouped log replay with pass/fail summary.

- [ ] **Step 3: Dry-run deploy.sh to verify cargo background build**

Run: `cd /Users/yulong/code/dotfiles && ./deploy.sh --only claude --non-interactive 2>&1 | tail -20`

Verify: "Building claude-tools (background)" appears early, "claude-tools built" appears near the end.

- [ ] **Step 4: Commit any fixes from smoke testing**

```bash
git add -A && git commit -m "fix: address issues found during parallel install smoke testing"
```

(Skip if no fixes needed.)
