# Minimise Installations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trim bloated install/deploy scripts, uninstall unused brew packages, and add interactive toggle UI via gum.

**Architecture:** `config.sh` is the single source of truth for defaults. `helpers.sh` gets a new `show_component_menu()` function using gum. Both `install.sh` and `deploy.sh` call it after loading config to let users toggle components interactively. Graceful fallback: if gum unavailable or non-interactive (piped, CI, `--non-interactive`), use defaults silently.

**Tech Stack:** Zsh, Homebrew, gum (charmbracelet)

**Important notes for implementers:**
- `helpers.sh` uses `#!/usr/bin/env zsh` — all code must use zsh syntax
- `install.sh` shebang will be changed from `#!/bin/bash` to `#!/usr/bin/env zsh` to match (deploy.sh and helpers.sh are already zsh)
- `gum choose --selected` takes a **comma-separated** string, NOT repeated flags
- Working directory: `/Users/yulong/code/dotfiles/.claude/worktrees/minimise-installations`

---

### Task 1: Update config.sh — Package Lists

**Files:**
- Modify: `config.sh:30` (INSTALL_EXTRAS comment)
- Modify: `config.sh:119-157` (package arrays)

- [ ] **Step 1: Add `sd` and `gum` to PACKAGES_MACOS**

Change PACKAGES_MACOS (lines 119-131) to:

```bash
PACKAGES_MACOS=(
    "coreutils"  # GNU utilities on macOS (gdate, gawk, gsed)
    "bat"
    "eza"
    "zoxide"
    "delta"
    "gitleaks"
    "dust"
    "fd"
    "ripgrep"
    "jless"
    "just"
    "sd"          # sed replacement (preferred over sed)
    "gum"         # interactive shell UI (toggle menus)
)
```

- [ ] **Step 2: Add `gum` to PACKAGES_LINUX_MISE**

Add to PACKAGES_LINUX_MISE (after the `just` entry at line 143):

```bash
    "github:charmbracelet/gum"
```

- [ ] **Step 3: Replace lazygit with gitui in extras, remove code2prompt**

Change PACKAGES_EXTRAS_MACOS (lines 147-151) to:

```bash
PACKAGES_EXTRAS_MACOS=(
    "hyperfine"
    "gitui"
    "terminal-notifier"
)
```

Change PACKAGES_EXTRAS_LINUX (lines 153-157) to:

```bash
PACKAGES_EXTRAS_LINUX=(
    "github:sharkdp/hyperfine"
    "github:extrawurst/gitui"
)
```

- [ ] **Step 4: Update INSTALL_EXTRAS comment**

Change line 30 from:
```bash
INSTALL_EXTRAS=false            # hyperfine, lazygit, code2prompt
```
to:
```bash
INSTALL_EXTRAS=false            # hyperfine, gitui, terminal-notifier
```

- [ ] **Step 5: Verify and commit**

Run: `bash -n config.sh` — expected exit 0.

```bash
git add config.sh && git commit -m "chore: update package lists — add sd/gum, replace lazygit with gitui, remove code2prompt"
```

---

### Task 2: Update config.sh — Trim Plugins and MCP

**Files:**
- Modify: `config.sh:76-105` (MCP_SERVERS_LOCAL and OFFICIAL_PLUGINS)

- [ ] **Step 1: Empty MCP_SERVERS_LOCAL**

Change lines 78-80 from:
```bash
MCP_SERVERS_LOCAL=(
    "slack:yulonglin/slack-mcp-server:slack-mcp-server:SLACK_MCP_XOXP_TOKEN"
)  # Consider if this is safe to include here, or if it'll break something
```
to:
```bash
MCP_SERVERS_LOCAL=()
```

- [ ] **Step 2: Trim OFFICIAL_PLUGINS**

Remove: claude-code-setup, serena, figma, supabase, stripe, huggingface-skills, coderabbit.

Change lines 92-105 to:
```bash
OFFICIAL_PLUGINS=(
    # Base profile (always-on)
    "superpowers" "hookify" "plugin-dev" "commit-commands"
    "claude-md-management" "context7"
    # Development
    "code-simplifier" "code-review" "security-guidance" "feature-dev"
    "pr-review-toolkit" "playground" "ralph-loop"
    # Integrations
    "Notion" "linear" "vercel" "playwright"
    # Language servers
    "pyright-lsp" "typescript-lsp"
    # Specialized
    "frontend-design"
)
```

- [ ] **Step 3: Verify and commit**

Run: `bash -n config.sh` — expected exit 0.

```bash
git add config.sh && git commit -m "chore: trim plugins and remove local slack MCP (using claude.ai MCPs instead)"
```

---

### Task 3: Update install.sh — Remove code2prompt cargo install + fix shebang

**Files:**
- Modify: `install.sh:1` (shebang)
- Modify: `install.sh:253-277` (extras section)

- [ ] **Step 1: Change install.sh shebang**

Change line 1 from:
```bash
#!/bin/bash
```
to:
```bash
#!/usr/bin/env zsh
```

This matches deploy.sh and helpers.sh — helpers.sh already uses zsh-specific syntax (`read -rA`, `${(U)var}`, `${(Ie)}`) that would fail under bash.

- [ ] **Step 2: Remove the code2prompt cargo block and extras-only Rust install**

Replace the entire extras section (lines 253-277) with:

```bash
if [[ "$INSTALL_EXTRAS" == "true" ]]; then
    log_section "INSTALLING EXTRAS"

    if is_macos; then
        install_packages brew "${PACKAGES_EXTRAS_MACOS[@]}"
    else
        for pkg in "${PACKAGES_EXTRAS_LINUX[@]}"; do
            mise_install "$pkg"
        done
    fi
fi
```

Rust is still installed in the AI tools section (lines 285-289), so no loss.

- [ ] **Step 3: Verify and commit**

Run: `zsh -n install.sh` — expected exit 0.

```bash
git add install.sh && git commit -m "chore: fix shebang to zsh, simplify extras section"
```

---

### Task 4: Add interactive toggle menu to helpers.sh

**Files:**
- Modify: `scripts/shared/helpers.sh` (add function after line 21, modify parse_args)

- [ ] **Step 1: Add `show_component_menu()` function**

Add after the logging section (after line 21, before `# ─── Command Checking`):

```bash
# ─── Interactive Component Menu ──────────────────────────────────────────────

# Show interactive toggle menu for component selection
# Usage: show_component_menu install|deploy
# Requires: gum (graceful fallback to defaults if unavailable)
show_component_menu() {
    local mode="$1"

    # Skip if non-interactive
    if [[ "${NON_INTERACTIVE:-false}" == "true" ]] || ! [[ -t 0 ]] || ! cmd_exists gum; then
        return 0
    fi

    # Define components and their current state
    # Format: "name:variable_value" — order determines display order
    typeset -a comp_defs
    if [[ "$mode" == "install" ]]; then
        comp_defs=(
            "zsh:$INSTALL_ZSH"
            "tmux:$INSTALL_TMUX"
            "ai-tools:$INSTALL_AI_TOOLS"
            "extras:$INSTALL_EXTRAS"
            "cleanup:$INSTALL_CLEANUP"
            "experimental:$INSTALL_EXPERIMENTAL"
        )
        if is_linux; then
            comp_defs+=("docker:$INSTALL_DOCKER" "create-user:$INSTALL_CREATE_USER")
        fi
    elif [[ "$mode" == "deploy" ]]; then
        comp_defs=(
            "shell:$DEPLOY_SHELL"
            "tmux:$DEPLOY_TMUX"
            "git-config:$DEPLOY_GIT_CONFIG"
            "vim:$DEPLOY_VIM"
            "editor:$DEPLOY_EDITOR"
            "claude:$DEPLOY_CLAUDE"
            "codex:$DEPLOY_CODEX"
            "ghostty:$DEPLOY_GHOSTTY"
            "htop:$DEPLOY_HTOP"
            "pdb:$DEPLOY_PDB"
            "matplotlib:$DEPLOY_MATPLOTLIB"
            "git-hooks:$DEPLOY_GIT_HOOKS"
            "secrets:$DEPLOY_SECRETS"
            "secrets-env:$DEPLOY_SECRETS_ENV"
            "cleanup:$DEPLOY_CLEANUP"
            "claude-cleanup:$DEPLOY_CLAUDE_CLEANUP"
            "ai-update:$DEPLOY_AI_UPDATE"
            "brew-update:$DEPLOY_BREW_UPDATE"
        )
        if is_macos; then
            comp_defs+=("keyboard:$DEPLOY_KEYBOARD" "bedtime:$DEPLOY_BEDTIME"
                        "text-replacements:${DEPLOY_TEXT_REPLACEMENTS:-false}"
                        "mouseless:$DEPLOY_MOUSELESS" "vpn:$DEPLOY_VPN")
        fi
        comp_defs+=("serena:$DEPLOY_SERENA")
    fi

    # Build items and selected lists
    typeset -a items
    local selected_csv=""
    for def in "${comp_defs[@]}"; do
        local name="${def%%:*}"
        local value="${def#*:}"
        items+=("$name")
        if [[ "$value" == "true" ]]; then
            [[ -n "$selected_csv" ]] && selected_csv+=","
            selected_csv+="$name"
        fi
    done

    # Show gum menu
    local result
    local gum_args=(choose --no-limit --ordered
        --header "Select ${mode} components (space=toggle, enter=confirm):"
        --cursor-prefix "• " --selected-prefix "✓ " --unselected-prefix "• ")
    [[ -n "$selected_csv" ]] && gum_args+=(--selected "$selected_csv")

    result=$(gum "${gum_args[@]}" -- "${items[@]}") || return 0  # user cancelled (ctrl-c)

    # Disable all components in this mode, then re-enable selected
    for def in "${comp_defs[@]}"; do
        local name="${def%%:*}"
        local var_name="${(U)name//-/_}"
        if [[ "$mode" == "install" ]]; then
            typeset -g "INSTALL_${var_name}=false"
        else
            typeset -g "DEPLOY_${var_name}=false"
        fi
    done

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local var_name="${(U)line//-/_}"
        if [[ "$mode" == "install" ]]; then
            typeset -g "INSTALL_${var_name}=true"
        else
            typeset -g "DEPLOY_${var_name}=true"
        fi
    done <<< "$result"
}
```

- [ ] **Step 2: Add `--non-interactive` flag to parse_args()**

In the `parse_args()` function, add this case **immediately before** the `--no-*` pattern (which is at approximately line 935 after the function insertion). It must come before both `--no-*` and `--*` catch-alls:

```bash
            --non-interactive)
                NON_INTERACTIVE=true
                ;;
```

- [ ] **Step 3: Verify and commit**

Run: `zsh -n scripts/shared/helpers.sh` — expected exit 0.

```bash
git add scripts/shared/helpers.sh && git commit -m "feat: add interactive component toggle menu via gum"
```

---

### Task 5: Wire up toggle menu in install.sh and deploy.sh

**Files:**
- Modify: `install.sh` (add line after parse_args + update help)
- Modify: `deploy.sh` (add line after parse_args + update help)

- [ ] **Step 1: Add toggle call to install.sh**

After `parse_args "$@"` (line 71), add:

```bash
show_component_menu install
```

- [ ] **Step 2: Add toggle call to deploy.sh**

After `parse_args "$@"` (line 96), add:

```bash
show_component_menu deploy
```

- [ ] **Step 3: Add `--non-interactive` to help text in install.sh**

In the `show_help()` function, add under the COMPONENTS section:

```
    --non-interactive Skip interactive component menu
```

- [ ] **Step 4: Add `--non-interactive` to help text in deploy.sh**

In the `show_help()` function, add under the COMPONENTS section:

```
    --non-interactive Skip interactive component menu
```

- [ ] **Step 5: Verify and commit**

Run: `zsh -n install.sh && zsh -n deploy.sh` — expected exit 0.

```bash
git add install.sh deploy.sh && git commit -m "feat: wire up interactive toggle menu in install.sh and deploy.sh"
```

---

### Task 6: Uninstall unused brew formulae

**Files:** None (local machine state)

- [ ] **Step 1: Uninstall unused formulae**

```bash
brew uninstall cmake nasm php btop ncdu duf
```

- [ ] **Step 2: Clean up orphaned deps**

```bash
brew autoremove
```

---

### Task 7: Uninstall unused brew casks

**Files:** None (local machine state)

- [ ] **Step 1: Uninstall unused casks**

```bash
brew uninstall --cask audacity dockdoor espanso gcloud-cli jordanbaird-ice shortcat swiftdefaultappsprefpane wave
```

---

### Task 8: Uninstall shell-ask from bun global

- [ ] **Step 1: Uninstall**

```bash
bun remove -g shell-ask
```

---

### Task 9: Final verification

- [ ] **Step 1: Syntax check all modified scripts**

```bash
cd /Users/yulong/code/dotfiles/.claude/worktrees/minimise-installations && zsh -n config.sh && zsh -n install.sh && zsh -n deploy.sh && zsh -n scripts/shared/helpers.sh
```

Expected: All exit 0

- [ ] **Step 2: Test help output**

```bash
./install.sh --help
./deploy.sh --help
```

Expected: Both show `--non-interactive` in help text

- [ ] **Step 3: Test non-interactive mode**

```bash
./install.sh --non-interactive --help
```

Expected: No toggle menu, straight to help

- [ ] **Step 4: Verify brew state**

```bash
brew leaves | wc -l
```

Expected: ~39 (was 44, minus 6 removals, plus 1 gum already installed)
