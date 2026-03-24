# Fix Hidden Actions in install.sh and deploy.sh

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure every action in install.sh and deploy.sh is represented in the gum selection menu — nothing runs silently when the user deselects everything.

**Architecture:** Merge main (which has the gum menu) into this branch, then wrap all currently-unconditional sections behind new menu items. Group related unconditionals into logical components to keep the menu manageable.

**Tech Stack:** Bash/ZSH, gum CLI

---

## Context

Running `./install.sh` or `./deploy.sh` performs many actions even when nothing is selected in the gum menu. These "hidden actions" run unconditionally and aren't represented in the selection UI:

**install.sh unconditional actions (lines 82-225 on main):**
- Core packages (jq, fzf, htop, ripgrep, bat, eza, etc.) + Homebrew/apt/mise setup
- GitHub CLI
- Gitleaks
- SOPS + age + direnv
- Atuin
- uv
- macOS system settings (line 463)
- Finicky installation (line 470)

**deploy.sh unconditional actions:**
- ZSH install if missing (line 108-115)
- Finicky symlink (line 412-419)
- claude-tools Rust binary build (line 546-556)
- Safari web app registry scan (line 892-893)

## File Structure

**Files to modify:**
- `scripts/shared/helpers.sh` — Add new items to `show_component_menu()` comp_defs
- `install.sh` — Wrap unconditional sections behind `INSTALL_*` flags
- `deploy.sh` — Wrap unconditional sections behind `DEPLOY_*` flags
- `config.sh` — Add new default variables + update `apply_profile()` minimal/server presets

---

### Task 0: Merge main into worktree branch

- [ ] **Step 1: Merge main**

```bash
git merge main
```

This picks up the gum menu (`show_component_menu`), SOPS fixes, and other changes (18 commits).

- [ ] **Step 2: Resolve any conflicts**

- [ ] **Step 3: Verify gum menu works**

```bash
./install.sh --help
grep show_component_menu install.sh deploy.sh
```

Expected: Both scripts call `show_component_menu`.

- [ ] **Step 4: Commit merge if needed**

---

### Task 1: Add new config variables for currently-unconditional sections

**Files:**
- Modify: `config.sh` (defaults + `apply_profile()`)

Group the unconditional actions into logical components:

| New variable | Controls | Default |
|---|---|---|
| `INSTALL_CORE` | Core packages, Homebrew/apt/mise, GitHub CLI, gitleaks, SOPS/age/direnv, Atuin, uv | `true` |
| `INSTALL_MACOS_SETTINGS` | macOS system defaults | `true` |
| `INSTALL_FINICKY` | Finicky browser router (macOS) | `true` |
| `DEPLOY_FINICKY` | Finicky config symlink (macOS) | `true` |
| `DEPLOY_CLAUDE_TOOLS` | claude-tools Rust binary build | `true` |

Note: deploy.sh's "install zsh if missing" (lines 108-115) should move inside the `DEPLOY_SHELL` guard — it only matters if we're deploying shell config. Safari web app scan is trivial/fast and can go under an existing flag (DEPLOY_EDITOR or just keep unconditional) — but for completeness, remove it or gate on a flag.

- [ ] **Step 1: Add new defaults to config.sh**

In the `# ─── Install Components` section, add:
```bash
INSTALL_CORE=true               # Core packages, CLI tools, GitHub CLI, SOPS/age, Atuin, uv
INSTALL_MACOS_SETTINGS=true     # macOS system defaults (Dock, Finder, etc.)
INSTALL_FINICKY=true            # Finicky browser routing (macOS only)
```

In the `# ─── Deploy Components` section, add:
```bash
DEPLOY_FINICKY=true             # Finicky config symlink (macOS only)
DEPLOY_CLAUDE_TOOLS=true        # Build claude-tools Rust binary
```

- [ ] **Step 2: Update `apply_profile()` minimal preset**

Add to the `minimal)` case:
```bash
INSTALL_CORE=false
INSTALL_MACOS_SETTINGS=false
INSTALL_FINICKY=false
DEPLOY_FINICKY=false
DEPLOY_CLAUDE_TOOLS=false
```

- [ ] **Step 3: Update `apply_profile()` server preset**

Add to the `server)` case:
```bash
INSTALL_FINICKY=false
INSTALL_MACOS_SETTINGS=false
DEPLOY_FINICKY=false
DEPLOY_CLAUDE_TOOLS=false
```

`INSTALL_CORE` stays `true` for server (core tools are always useful).

- [ ] **Step 4: Add to `_known_components` in `parse_args()`**

In `scripts/shared/helpers.sh`, add `core`, `macos_settings`, `finicky`, `claude_tools` to the known components array.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: add config variables for previously-unconditional actions"
```

---

### Task 2: Add new items to the gum menu

**Files:**
- Modify: `scripts/shared/helpers.sh` — `show_component_menu()` function

- [ ] **Step 1: Add install menu items**

In the `install` mode comp_defs array, add at the top (before zsh):
```bash
"core|Core packages, CLI tools, gh, SOPS/age, Atuin, uv|$INSTALL_CORE"
```

And in the macOS section (alongside existing platform-specific items):
```bash
if is_macos; then
    comp_defs+=(
        "macos-settings|Dock, Finder, keyboard system defaults|$INSTALL_MACOS_SETTINGS"
        "finicky|Browser routing (Safari/Chrome/Zoom)|$INSTALL_FINICKY"
    )
fi
```

- [ ] **Step 2: Add deploy menu items**

In the `deploy` mode comp_defs array, add in the macOS section:
```bash
"finicky|Browser routing config (symlinked)|$DEPLOY_FINICKY"
```

And in the general section:
```bash
"claude-tools|Build claude-tools Rust binary|$DEPLOY_CLAUDE_TOOLS"
```

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: add core, macos-settings, finicky, claude-tools to gum menu"
```

---

### Task 3: Wrap install.sh unconditional sections behind flags

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Wrap core packages section (lines 82-225) with INSTALL_CORE guard**

```bash
if [[ "$INSTALL_CORE" == "true" ]]; then
    # ─── Platform-Specific Package Managers ───...
    # ... (all existing code from Homebrew through uv)
fi
```

This wraps: Homebrew/apt/mise setup, core packages, GitHub CLI, gitleaks, SOPS+age+direnv, Atuin, uv.

- [ ] **Step 2: Wrap macOS settings behind INSTALL_MACOS_SETTINGS**

Change:
```bash
if is_macos && [[ -f "$DOT_DIR/config/macos_settings.sh" ]]; then
```
To:
```bash
if [[ "$INSTALL_MACOS_SETTINGS" == "true" ]] && is_macos && [[ -f "$DOT_DIR/config/macos_settings.sh" ]]; then
```

- [ ] **Step 3: Wrap Finicky install behind INSTALL_FINICKY**

Change:
```bash
if is_macos && ! is_cask_installed finicky; then
```
To:
```bash
if [[ "$INSTALL_FINICKY" == "true" ]] && is_macos && ! is_cask_installed finicky; then
```

- [ ] **Step 4: Commit**

```bash
git commit -m "feat: gate all install.sh actions behind menu-selectable flags"
```

---

### Task 4: Wrap deploy.sh unconditional sections behind flags

**Files:**
- Modify: `deploy.sh`

- [ ] **Step 1: Move "install zsh if missing" inside DEPLOY_SHELL guard**

Move lines 108-116 (`if ! cmd_exists zsh; then ... fi`) inside the `if [[ "$DEPLOY_SHELL" == "true" ]]; then` block (before the shell detection logic).

- [ ] **Step 2: Wrap Finicky deployment behind DEPLOY_FINICKY**

Change:
```bash
if is_macos && [[ -f "$DOT_DIR/config/finicky.js" ]]; then
```
To:
```bash
if [[ "$DEPLOY_FINICKY" == "true" ]] && is_macos && [[ -f "$DOT_DIR/config/finicky.js" ]]; then
```

- [ ] **Step 3: Wrap claude-tools build behind DEPLOY_CLAUDE_TOOLS**

Change:
```bash
if [[ -f "$DOT_DIR/tools/claude-tools/Cargo.toml" ]]; then
```
To:
```bash
if [[ "$DEPLOY_CLAUDE_TOOLS" == "true" ]] && [[ -f "$DOT_DIR/tools/claude-tools/Cargo.toml" ]]; then
```

- [ ] **Step 4: Wrap Safari web app scan behind DEPLOY_EDITOR** (or remove)

Change:
```bash
if is_macos && [[ -f "$DOT_DIR/custom_bins/safari-web-apps-scan" ]]; then
```
To:
```bash
if [[ "$DEPLOY_EDITOR" == "true" ]] && is_macos && [[ -f "$DOT_DIR/custom_bins/safari-web-apps-scan" ]]; then
```

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: gate all deploy.sh actions behind menu-selectable flags"
```

---

### Task 5: Verify empty selection does nothing

- [ ] **Step 1: Test install.sh with minimal profile**

```bash
./install.sh --minimal --non-interactive
```

Expected: Only prints header, then "Installation complete!" — no packages installed.

- [ ] **Step 2: Test deploy.sh with minimal profile**

```bash
./deploy.sh --minimal --non-interactive
```

Expected: Only prints header, then "Deployment complete!" — no configs deployed.

- [ ] **Step 3: Test default profile still works**

```bash
./install.sh --non-interactive 2>&1 | head -30
./deploy.sh --non-interactive 2>&1 | head -30
```

Expected: All default components run as before.

- [ ] **Step 4: Manual gum test (interactive)**

Run `./install.sh`, deselect everything in the gum menu, confirm — should do nothing.
Run `./deploy.sh`, deselect everything in the gum menu, confirm — should do nothing.

---

## Verification

1. `./install.sh --minimal --non-interactive` should produce no side effects
2. `./deploy.sh --minimal --non-interactive` should produce no side effects
3. `./install.sh --non-interactive` should behave identically to current main
4. `./deploy.sh --non-interactive` should behave identically to current main
5. Interactive gum menu with empty selection → nothing happens
6. `grep -c 'INSTALL_\|DEPLOY_' install.sh deploy.sh` — every section gated
