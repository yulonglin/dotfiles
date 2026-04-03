# TPM + Tmux Session Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add TPM (Tmux Plugin Manager) with resurrect + continuum plugins for persistent tmux sessions across reboots/crashes on macOS and Linux.

**Architecture:** TPM is git-cloned to `~/.tmux/plugins/tpm/`. Plugin declarations go in `config/tmux.conf`. A shared `install_tpm()` helper in `helpers.sh` handles idempotent cloning, called from both `install.sh` and `deploy.sh`. Plugins are installed via direct git clone (not `bin/install_plugins`) to avoid requiring a tmux server.

**Status:** ✅ Complete — all tasks implemented and committed (`51346e3`, `0a98f2e`).

**Tech Stack:** tmux, TPM, tmux-resurrect, tmux-continuum, bash/zsh

---

## Context

Tmux sessions are lost on reboot (macOS updates) or server migration. Adding resurrect + continuum gives:
- **continuum**: auto-saves layout + window state every 15 min, auto-restores on tmux start
- **resurrect**: manual save/restore with `prefix + Ctrl-s` / `prefix + Ctrl-r`

No process relaunching (`@resurrect-processes 'false'`) — processes aren't idempotent and blind relaunch causes stale state.

## Criteria

1. **Idempotent** — deploy twice = same result, no duplicate lines, no broken state
2. **Cross-platform** — macOS + Linux (including containers)
3. **Consistent** — follows existing deploy patterns (flags, logging, helpers)
4. **Gracefully degrading** — no errors if git unavailable or network down
5. **Minimal** — only plugins that earn their keep; no logging plugin
6. **Reversible** — easy to disable without breaking tmux

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `config/tmux.conf` | Modify | Add plugin declarations + TPM init |
| `scripts/shared/helpers.sh` | Modify | Add `install_tpm()` helper; fix tmux-themepack idempotency |
| `deploy.sh` | Modify | Call `install_tpm` + `bin/install_plugins` in tmux block |
| `install.sh` | Modify | Call `install_tpm` gated on `INSTALL_TMUX` |
| `CLAUDE.md` | Modify | Document tmux plugin behavior |

---

### Task 1: Add TPM plugin declarations to tmux.conf

**Files:**
- Modify: `config/tmux.conf:88` (append at end)

- [x] **Step 1: Add plugin block to end of `config/tmux.conf`**

Append after the `update-environment` line (line 88):

```bash

# ─── Plugins (TPM) ────────────────────────────────────────────────────────────

set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'

# Continuum: auto-save every 15 min, auto-restore on tmux start
set -g @continuum-restore 'on'

# Resurrect: don't relaunch processes (not idempotent)
set -g @resurrect-processes 'false'

# Initialize TPM (keep this line at the very bottom of tmux.conf)
if-shell "test -f ~/.tmux/plugins/tpm/tpm" "run-shell '~/.tmux/plugins/tpm/tpm'"
```

Note: Uses `if-shell` guard (not bare `run-shell`) so tmux starts cleanly even without TPM installed.

- [x] **Step 2: Commit**

```bash
git add config/tmux.conf
git commit -m "feat(tmux): add TPM plugin declarations for session persistence"
```

---

### Task 2: Add `install_tpm()` helper + fix tmux-themepack idempotency

**Files:**
- Modify: `scripts/shared/helpers.sh:577-578` (tmux-themepack area)

- [x] **Step 1: Add `install_tpm` function after the tmux-themepack block**

Insert after the tmux-themepack clone (after line 578):

```bash
install_tpm() {
    local tpm_dir="$HOME/.tmux/plugins/tpm"
    if [[ -d "$tpm_dir" ]]; then
        log_info "TPM already installed"
        return 0
    fi
    log_info "Installing TPM (Tmux Plugin Manager)..."
    mkdir -p "$HOME/.tmux/plugins"
    git clone --quiet https://github.com/tmux-plugins/tpm "$tpm_dir" 2>/dev/null || {
        log_warning "TPM clone failed (no network?) — tmux will work without plugins"
        return 0
    }
    log_success "TPM installed"
}
```

- [x] **Step 2: Fix tmux-themepack idempotency (drive-by)**

Replace lines 577-578:

```bash
# Before (not idempotent):
log_info "Installing tmux theme pack..."
git clone --quiet https://github.com/jimeh/tmux-themepack.git ~/.tmux-themepack 2>/dev/null || true

# After (idempotent):
if [[ ! -d "$HOME/.tmux-themepack" ]]; then
    log_info "Installing tmux theme pack..."
    git clone --quiet https://github.com/jimeh/tmux-themepack.git "$HOME/.tmux-themepack" 2>/dev/null || log_warning "tmux-themepack clone failed"
else
    log_info "tmux-themepack already installed"
fi
```

- [x] **Step 3: Commit**

```bash
git add scripts/shared/helpers.sh
git commit -m "feat(tmux): add idempotent install_tpm helper, fix themepack idempotency"
```

---

### Task 3: Call `install_tpm` from install.sh

**Files:**
- Modify: `install.sh:175-186` (tmux install block)

- [x] **Step 1: Add `install_tpm` call after tmux binary installation**

The tmux block in install.sh currently installs the tmux binary. Add `install_tpm` after it:

```bash
if [[ "$INSTALL_TMUX" == "true" ]]; then
    if ! is_installed tmux; then
        log_info "Installing tmux..."
        if is_macos; then
            brew_install tmux
        else
            apt_install tmux
        fi
    fi
    install_tpm
fi
```

This keeps TPM installation gated on `INSTALL_TMUX` (not buried inside `install_ohmyzsh()` where it doesn't belong — TPM is a tmux concern, not a zsh concern).

- [x] **Step 2: Commit**

```bash
git add install.sh
git commit -m "feat(tmux): install TPM alongside tmux binary"
```

---

### Task 4: Expand deploy.sh tmux block

**Files:**
- Modify: `deploy.sh:117-120` (expand existing tmux block)

- [x] **Step 1: Expand the tmux deploy block to include TPM + plugin install**

The existing eval line is preserved. New code added after it uses **direct git clone** (not `bin/install_plugins`) to avoid requiring a tmux server — this was redesigned after discovering that `bin/install_plugins` needs `TMUX_PLUGIN_MANAGER_PATH` set via a running tmux server, which risks killing user sessions.

```bash
if [[ "$DEPLOY_TMUX" == "true" ]]; then
    log_info "Deploying tmux configuration..."
    eval "echo \"source $DOT_DIR/config/tmux.conf\" $OP \"\$HOME/.tmux.conf\""

    # Ensure TPM is installed (idempotent — skips if already present)
    install_tpm

    # Install plugins directly (avoids needing a tmux server running)
    local plugin_dir="$HOME/.tmux/plugins"
    for plugin in tmux-resurrect tmux-continuum; do
        if [[ ! -d "$plugin_dir/$plugin" ]]; then
            log_info "Installing $plugin..."
            git clone --quiet "https://github.com/tmux-plugins/$plugin" "$plugin_dir/$plugin" 2>/dev/null || \
                log_warning "$plugin clone failed"
        fi
    done
fi
```

`install_tpm` is available because `deploy.sh` sources `helpers.sh` (line 29). No duplication.

- [x] **Step 2: Commit**

```bash
git add deploy.sh
git commit -m "feat(tmux): install TPM and plugins during deployment"
```

---

### Task 5: Update documentation

**Files:**
- Modify: `CLAUDE.md` (deployment components, gotchas)

- [x] **Step 1: Update deployment components description**

In the "Deployment Components" section, update the tmux bullet:

```
- Tmux configuration - Shell multiplexer config + TPM plugins (resurrect, continuum) for session persistence
```

- [x] **Step 2: Add tmux plugins gotcha**

Add to the "Important Gotchas" section:

```
- **TPM plugins**: `run-shell` in tmux.conf fails silently if TPM isn't cloned — tmux works fine without plugins. Deploy auto-installs plugins to disk, but already-running tmux sessions need `prefix + I` or a tmux restart to load them. `prefix + Ctrl-s` saves session, `prefix + Ctrl-r` restores.
```

- [x] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document tmux plugin behavior and keybindings"
```

---

### Task 6: End-to-end verification

- [x] **Step 1: Run deploy with tmux flag**

```bash
./deploy.sh --only tmux
```

Expected: tmux config deployed, TPM cloned to `~/.tmux/plugins/tpm/`, plugins installed to `~/.tmux/plugins/tmux-resurrect/` and `~/.tmux/plugins/tmux-continuum/`.

- [x] **Step 2: Verify idempotency**

```bash
./deploy.sh --only tmux
```

Expected: Same output, "TPM already installed", no errors, no duplicate work.

- [x] **Step 3: Verify tmux loads cleanly**

```bash
tmux new-session -d -s tpm-test && tmux kill-session -t tpm-test
```

Expected: No errors.

- [x] **Step 4: Verify plugins are loaded**

```bash
tmux new-session -d -s tpm-test
tmux list-keys | grep -i resurrect
tmux kill-session -t tpm-test
```

Expected: Key bindings for resurrect-save and resurrect-restore visible.

- [x] **Step 5: Test graceful degradation (no TPM)**

```bash
mv ~/.tmux/plugins/tpm ~/.tmux/plugins/tpm.bak
./deploy.sh --only tmux 2>&1 | grep -i "warning\|error"
mv ~/.tmux/plugins/tpm.bak ~/.tmux/plugins/tpm
```

Expected: Warning about TPM clone (or success if it re-clones), no hard errors. Tmux starts without plugins.
