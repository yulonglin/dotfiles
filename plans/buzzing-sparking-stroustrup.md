# Plan: Cross-Platform claude-tools + Symlink Fix

## Context

`claude-tools` (Rust binary) only works on macOS arm64 due to dynamic linking against Homebrew OpenSSL. On Linux (RunPod), all three subcommands fail silently — statusline breaks, context profiles don't auto-apply, git root check doesn't run. The `claude()` shell wrapper also incorrectly `cd`s when CWD is a symlinked git root.

## Critic Feedback Applied

- **Dropped shell statusline fallback** — overengineered; vendored deps make Rust build portable; shell reimplementation would be slow (forks jq, git per prompt) and fragile (YAML parsing with grep/awk)
- **Dropped full personal config system** — `config.sh` with profiles already handles this; at most one line for `config.local.sh`
- **Simplified plugin fallbacks** — use wrapper scripts (not inline shell in JSON commands); update existing plugin shell scripts instead of creating new ones
- **Only edit source plugin.json** — cache syncs automatically via `claude-cache-link`
- **Keep check_git_root.sh** — useful as fallback at stable `$HOME/.claude/hooks/` path
- **Consider removing LTO** — first vendored build with LTO takes 5-10min; for a personal tool, not worth it

## Changes

### 1. Fix symlink comparison in `claude()` wrapper ✅ (already done)

**File:** `config/aliases.sh:59`
- Use `realpath` to resolve `$PWD` before comparing with `git rev-parse --show-toplevel`

### 2. Vendored Rust deps for cross-platform builds

**File:** `tools/claude-tools/Cargo.toml`

```toml
git2 = { version = "0.19", default-features = false, features = ["vendored-libgit2"] }

[profile.release]
opt-level = "s"    # size-optimized (faster compile than opt-level 3)
strip = true
# Removed LTO — adds 3-5min to vendored builds for marginal gain on a personal tool
```

**Why `default-features = false`:** The binary only uses `Repository::discover()`, `.workdir()`, `.statuses()` — zero network operations (no fetch/push/clone). Default features pull in `openssl-sys` + `libssh2-sys` which cause the Linux build failure. Disabling them eliminates the entire OpenSSL dependency chain, cutting Linux build time by ~2-3min vs vendoring OpenSSL.

### 3. Add Rust to `install.sh --ai-tools` path

**File:** `install.sh` (inside `INSTALL_AI_TOOLS` block, early — before deploy.sh needs cargo)

Rust is currently only installed via `--extras`. Since `deploy.sh` needs `cargo` to build `claude-tools`, add it to `--ai-tools` too (idempotent — skips if already installed):

```bash
if ! is_installed cargo; then
    log_info "Installing Rust toolchain (user-level, no root needed)..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --quiet
    source "$HOME/.cargo/env" 2>/dev/null || true
fi
```

### 4. Plugin SessionStart hooks with shell fallback

**File:** `claude/ai-safety-plugins/plugins/core/.claude-plugin/plugin.json` (source only — cache syncs via `claude-cache-link`)

**Problem:** Plugin hook `command` strings may not support shell operators (`||`, `2>/dev/null`) if Claude Code uses exec-style invocation. All existing hooks use simple single-command strings.

**Solution:** Reuse existing hook scripts in the plugin — don't create new files. Add Rust-first dispatch to the top of each.

**File:** `claude/ai-safety-plugins/plugins/core/hooks/check_git_root.sh` (edit existing)
- Add `claude-tools check-git-root 2>/dev/null && exit 0` after shebang
- Apply `realpath` fix to the shell fallback logic (currently stale, compares raw `$PWD`)

**File:** `claude/ai-safety-plugins/plugins/core/hooks/context_auto_apply.sh` (edit existing)
- Add `claude-tools context-apply 2>/dev/null && exit 0` after shebang
- Keep existing `claude-context 2>/dev/null` as Python fallback

Update plugin.json SessionStart hooks to point to these:
```json
"SessionStart": [
  {
    "hooks": [
      { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/check_git_root.sh" },
      { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/context_auto_apply.sh" }
    ]
  }
]
```

**File:** `claude/hooks/check_git_root.sh`
- Keep as-is (already has `realpath` fix from step 1) — stable path at `$HOME/.claude/hooks/`

### 6. Optional: one-line config.local.sh support

**File:** `config.sh` — add at bottom, after all defaults and `apply_profile`:
```bash
# User overrides (gitignored) — create config.local.sh to customize defaults
# Precedence: defaults -> apply_profile() -> config.local.sh -> CLI flags (parse_args)
[[ -n "$DOT_DIR" && -f "$DOT_DIR/config.local.sh" ]] && source "$DOT_DIR/config.local.sh"
```

**File:** `.gitignore` — add `config.local.sh`

This is optional and low-effort. CLI flags (`--minimal`, `--no-*`) still override since `parse_args` runs after `source config.sh` in install.sh.

### 7. Resolve config.sh FIXMEs and TODOs

**File:** `config.sh`

| Line | Current | Resolution |
|------|---------|------------|
| 30 | `INSTALL_CREATE_USER=true # TODO: Check it doesn't do anything if non-Linux or non-root` | **Remove TODO comment only** — guards already exist: `install.sh:373` checks `is_linux`, `helpers.sh:303` checks `$EUID -ne 0`. No code change needed. |
| 59 | `SECRETS_GIST_ID="..." # FIXME: Consider if safe` | **Remove FIXME, add comment** — gist IDs are public identifiers (like repo names), not secrets. The gist content is private. Safe to commit. |
| 77 | `"fzf" # FIXME: Is this useful?` | **Remove FIXME — KEEP fzf** — heavily integrated: `fgb`, `fgc`, `fga` (git fuzzy), `fzf-cd`, `fzf-kill`, `hist`, zoxide `zi`, `.fzf.zsh` sourcing in zshrc |
| 79 | `"ncdu" # FIXME: Is this useful?` | **Drop entirely** (PACKAGES_CORE + `scripts/cloud/setup.sh`) — `dust` is the modern replacement. `du -sh` covers bare containers. |
| 87 | `"coreutils" # FIXME: Is this useful?` | **Remove FIXME — KEEP** — provides GNU utilities on macOS. While `realpath` is now native (macOS 13+), coreutils gives `gdate`, `gawk`, `gsed` which scripts may need. Low cost to keep. |
| 106 | `"ubi:PaulJuliusMartinez/jless" # FIXME: github instead?` | **Keep `ubi:` for jless** — no aarch64-linux binaries in releases (only x86_64). Change `ubi:sharkdp/hyperfine` and `ubi:jesseduffield/lazygit` in extras to `github:` (both have ARM Linux releases). Remove FIXME. |
| 111-112 | `"fd" # FIXME: promote to core?` / `"ripgrep" # FIXME: promote to core?` | **Promote to PACKAGES_MACOS** — fd and ripgrep are essential (used by Claude Code, Cursor, grep tool). Already in Linux core via PACKAGES_LINUX_MISE. |
| 134 | `work) # FIXME: consider if useful?` | **Drop work profile** — only adds Speechmatics aliases, which are all dead code (SGE queues, internal machines, Singularity). Also delete `config/aliases_speechmatics.sh` and remove `--aliases` deploy flag references. |
| 138 | `server) # FIXME: consider if useful?` | **Keep** — useful for RunPod/cloud minimal installs |

Also clean up Speechmatics/work references in:
- `install.sh:35` — remove "work" from profile list in help text
- `install.sh:49` — delete "work" profile description line
- `deploy.sh:11` — update aliases example in help
- `deploy.sh:40` — remove "work" from profile list in help text
- `deploy.sh:65` — delete speechmatics example line
- `config.sh:18` — delete work profile comment
- `config.sh:49` — update `DEPLOY_ALIASES` comment (remove "speechmatics")
- `README.md` — remove work profile documentation
- Note: Keep the generic aliases deploy loop in deploy.sh — it handles any alias file. Only remove help text and the work profile case.

### 8. README.md — document `--minimal` for other users

Brief note in README that `--minimal` disables all defaults for a lean install.

## File Summary

| File | Action |
|------|--------|
| `config/aliases.sh` | ✅ Done — realpath fix |
| `claude/hooks/check_git_root.sh` | ✅ Done — realpath fix, keep as fallback |
| `tools/claude-tools/Cargo.toml` | Edit — vendored features, remove LTO |
| `install.sh` | Edit — add Rust to --ai-tools path |
| `claude/ai-safety-plugins/plugins/core/.claude-plugin/plugin.json` | Edit — point SessionStart to plugin hook scripts |
| `claude/ai-safety-plugins/plugins/core/hooks/check_git_root.sh` | Edit — add Rust-first dispatch + realpath fix |
| `claude/ai-safety-plugins/plugins/core/hooks/context_auto_apply.sh` | Edit — add Rust-first dispatch |
| `config.sh` | Edit — resolve 9 FIXMEs/TODOs + one line for config.local.sh |
| `.gitignore` | Edit — add config.local.sh |
| `install.sh` | Edit — add Rust to --ai-tools + non-root guard for create_user |
| `config/aliases_speechmatics.sh` | Delete — all dead code (Speechmatics-specific) |
| `deploy.sh` | Edit — remove speechmatics alias deploy logic |
| `README.md` | Edit — document --minimal, remove work profile |

## Verification

1. **macOS build:** `cd tools/claude-tools && cargo build --release` → succeeds; verify all 3 subcommands work (`claude-tools statusline`, `check-git-root`, `context-apply`) — confirms `default-features = false` doesn't break anything
2. **Symlink test:** `cd` to a symlinked git root → `claude` wrapper should NOT cd away
3. **Fallback test:** Temporarily rename `custom_bins/claude-tools`:
   - Start a session → SessionStart hooks use shell fallbacks (no errors in output)
   - Context profiles apply via `claude-context` Python fallback
4. **Linux:** On RunPod, `cargo build --release` succeeds with vendored deps (first build ~3-5min)
5. **Cache sync:** After editing source plugin.json, run `claude-cache-link --apply` to sync
