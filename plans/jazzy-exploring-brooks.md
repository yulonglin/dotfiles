# Zed + Antigravity Editor Deployment Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Zed editor and Antigravity (VSCode fork) config to dotfiles with feature parity to Cursor, including gitignored file search.

**Architecture:** Zed gets its own deployment component (`--zed`) with symlinked config. Antigravity slots into the existing `deploy_editor_settings()` as a third VSCode-fork target alongside VSCode/Cursor. Both get documented in CLAUDE.md.

**Tech Stack:** Zsh (deploy scripts), JSONC (Zed settings), JSON (Antigravity/VSCode settings)

**Verification:** All 40 Zed settings verified against canonical `default.json`. Details in `plans/jazzy-exploring-brooks-agent-a993454fd8afcda5b.md`.

---

### Task 1: Create Zed settings.json

**Files:**
- Create: `config/zed/settings.json`

Settings verified against Zed's canonical `default.json` (all keys confirmed VALID).
Only includes settings that differ from defaults (clean config).
Current user settings from `~/.config/zed/settings.json` are preserved where appropriate.

- [ ] **Step 1: Create config/zed/ directory and settings.json**

```jsonc
// Zed editor settings — feature parity with Cursor config
// Deployed via: ./deploy.sh --zed (symlinked to ~/.config/zed/settings.json)
//
// Only non-default settings are listed. For all defaults, run:
//   zed: open default settings (from command palette)
{
  // === Privacy & Security ===
  "redact_private_values": true,

  // === Theme & Appearance ===
  "theme": {
    "mode": "system",
    "dark": "One Dark Pro",
    "light": "One Light"
  },
  "icon_theme": "Material Icon Theme",
  "ui_font_size": 16,
  "buffer_font_family": "Menlo",
  "buffer_font_size": 16,

  // === Editor Behavior (non-default only) ===
  "base_keymap": "VSCode",
  "autosave": "on_focus_change",
  "format_on_save": "off",
  "remove_trailing_whitespace_on_save": false,
  "multi_cursor_modifier": "cmd_or_ctrl",
  "soft_wrap": "editor_width",

  // === Display (non-default only) ===
  "minimap": {
    "show": "auto"
  },
  "indent_guides": {
    "enabled": true,
    "coloring": "indent_aware"
  },
  "inlay_hints": {
    "enabled": true
  },
  "tabs": {
    "show_diagnostics": "errors"
  },
  "toolbar": {
    "breadcrumbs": false,
    "quick_actions": false
  },

  // === Search (CRITICAL: include gitignored files) ===
  "search": {
    "include_ignored": true
  },
  "use_smartcase_search": true,

  // === File Scanning (extends defaults with project-specific exclusions) ===
  "file_scan_exclusions": [
    "**/.git",
    "**/.svn",
    "**/.hg",
    "**/.DS_Store",
    "**/Thumbs.db",
    "**/.cache",
    "**/.venv",
    "**/node_modules",
    "**/__pycache__",
    "**/*.pyc",
    "**/prompt_history"
  ],

  // === Git (inline blame = built-in GitLens) ===
  "git": {
    "inline_blame": {
      "enabled": true,
      "delay_ms": 600,
      "show_commit_summary": true,
      "min_column": 40
    }
  },

  // === Edit Predictions (Zeta — Zed's native AI completion) ===
  "edit_predictions": {
    "provider": "zed",
    "disabled_globs": [
      "**/.env*",
      "**/secrets*"
    ]
  },

  // === AI / Agent ===
  "agent": {
    "default_model": {
      "provider": "anthropic",
      "model": "claude-sonnet-4-6-latest"
    }
  },

  // === Telemetry (disabled) ===
  "telemetry": {
    "diagnostics": false,
    "metrics": false
  },

  // === Terminal (non-default only) ===
  "terminal": {
    "option_as_meta": true,
    "font_family": "Menlo",
    "font_size": 14,
    "detect_venv": {
      "on": {
        "directories": [".venv", "venv", ".env", "env"],
        "activate_script": "default"
      }
    }
  },

  // === Panels (non-default only) ===
  "outline_panel": {
    "dock": "right"
  },
  "notification_panel": {
    "button": false
  },
  "collaboration_panel": {
    "button": false
  },

  // === Auto-install Extensions ===
  "auto_install_extensions": {
    "one-dark-pro": true,
    "ruff": true,
    "toml": true,
    "dockerfile": true,
    "git-firefly": true,
    "csv": true,
    "just": true,
    "html": true
  },

  // === Language Overrides ===
  "languages": {
    "Python": {
      "tab_size": 4,
      "format_on_save": "off",
      "preferred_line_length": 100,
      "language_servers": ["pyright", "ruff"]
    },
    "TypeScript": {
      "tab_size": 2,
      "format_on_save": "on",
      "formatter": "language_server"
    },
    "JavaScript": {
      "tab_size": 2,
      "format_on_save": "on"
    },
    "JSON": {
      "tab_size": 2
    },
    "JSONC": {
      "tab_size": 2
    },
    "YAML": {
      "tab_size": 2
    },
    "Markdown": {
      "soft_wrap": "editor_width",
      "show_edit_predictions": false
    },
    "Rust": {
      "tab_size": 4,
      "format_on_save": "on",
      "formatter": "language_server",
      "preferred_line_length": 100
    }
  },

  // === File Type Associations ===
  "file_types": {
    "JSONC": ["**/.zed/**/*.json", "tsconfig.json", "tsconfig.*.json"],
    "XML": ["*.strings", "*.plist"]
  },

  // === SSH Connections ===
  // Zed reads hosts from ~/.ssh/config (managed by gist sync).
  // This array stores recently-used connections with project paths.
  // Machine-specific — added via Zed UI, not hardcoded.
  "ssh_connections": []
}
```

- [ ] **Step 2: Commit**

```bash
git add config/zed/settings.json
git commit -m "feat(zed): add Zed editor settings with Cursor feature parity"
```

---

### Task 2: Create Zed keymap.json

**Files:**
- Create: `config/zed/keymap.json`

- [ ] **Step 1: Create keymap.json**

```jsonc
// Zed keymap — Cursor-compatible bindings
// Deployed via: ./deploy.sh --zed (symlinked to ~/.config/zed/keymap.json)
[
  // Cmd+K for inline AI edit (matches Cursor's Cmd+K)
  // Note: this overrides Zed's cmd-k chord prefix.
  // If you need cmd-k chords back, change to "cmd-k cmd-k" or "cmd-i"
  {
    "context": "Editor && mode == full",
    "bindings": {
      "cmd-k": "assistant::InlineAssist"
    }
  },
  // Toggle terminal (matches Cursor's Ctrl+`)
  {
    "context": "Workspace",
    "bindings": {
      "ctrl-`": "workspace::ToggleBottomDock"
    }
  }
]
```

- [ ] **Step 2: Commit**

```bash
git add config/zed/keymap.json
git commit -m "feat(zed): add keymap with Cmd+K inline AI edit"
```

---

### Task 3: Add Zed deployment to deploy.sh infrastructure

**Files:**
- Modify: `config.sh:~40` (add DEPLOY_ZED default, after DEPLOY_GHOSTTY)
- Modify: `config.sh:~193,~230` (disable in server/minimal profiles)
- Modify: `scripts/shared/helpers.sh:~70` (add to component menu after ghostty)
- Modify: `scripts/shared/helpers.sh:~1347` (add to _known_components)
- Modify: `deploy.sh:~65` (add --zed help text)
- Modify: `deploy.sh:~479` (add deployment block after Ghostty)

- [ ] **Step 1: Add DEPLOY_ZED=true to config.sh defaults (after DEPLOY_GHOSTTY line ~40)**

```bash
DEPLOY_ZED=true                 # Zed editor config (symlinked)
```

- [ ] **Step 2: Disable DEPLOY_ZED in server and minimal profiles in config.sh**

In the `server` profile block (~line 193, after `DEPLOY_GHOSTTY=false`):
```bash
DEPLOY_ZED=false
```

In the `minimal` profile block (~line 230, after `DEPLOY_GHOSTTY=false`):
```bash
DEPLOY_ZED=false
```

- [ ] **Step 3: Add Zed to show_component_menu in helpers.sh (~line 70)**

After the ghostty line:
```bash
"zed|Zed editor config (symlinked)|$DEPLOY_ZED"
```

- [ ] **Step 4: Add `zed` to _known_components in helpers.sh (~line 1347)**

Add `zed` after `ghostty`:
```bash
local _known_components=(core vim editor claude codex ghostty zed htop pdb matplotlib
```

- [ ] **Step 5: Add --zed to deploy.sh help text (~line 65, after --ghostty)**

```
    --zed             Deploy Zed editor config (settings + keymap, symlinked)
```

- [ ] **Step 6: Add Zed deployment block in deploy.sh (after Ghostty block, ~line 479)**

```bash
# ─── Zed ──────────────────────────────────────────────────────────────────────

if [[ "$DEPLOY_ZED" == "true" ]]; then
    log_info "Deploying Zed configuration..."

    ZED_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zed"

    if [[ -d "$DOT_DIR/config/zed" ]]; then
        mkdir -p "$ZED_DIR"

        # Settings
        if [[ -f "$ZED_DIR/settings.json" && ! -L "$ZED_DIR/settings.json" ]]; then
            backup_file "$ZED_DIR/settings.json"
        fi
        safe_symlink "$DOT_DIR/config/zed/settings.json" "$ZED_DIR/settings.json"

        # Keymap
        if [[ -f "$DOT_DIR/config/zed/keymap.json" ]]; then
            if [[ -f "$ZED_DIR/keymap.json" && ! -L "$ZED_DIR/keymap.json" ]]; then
                backup_file "$ZED_DIR/keymap.json"
            fi
            safe_symlink "$DOT_DIR/config/zed/keymap.json" "$ZED_DIR/keymap.json"
        fi

        log_info "  Search: gitignored files included"
        log_info "  AI: Cmd+K for inline edit, Anthropic agent"
        log_info "  Theme: One Dark Pro (auto dark/light switching)"
        log_info "  SSH: reads hosts from ~/.ssh/config"
    else
        log_warning "Zed config not found at $DOT_DIR/config/zed/"
    fi
fi
```

- [ ] **Step 7: Commit**

```bash
git add config.sh scripts/shared/helpers.sh deploy.sh
git commit -m "feat(zed): add Zed as deployment component (--zed flag)"
```

---

### Task 4: Add Antigravity to deploy_editor_settings()

**Files:**
- Modify: `scripts/shared/helpers.sh:~1126-1164` (deploy_editor_settings function)

Antigravity is a VSCode fork (`com.google.antigravity`). Same settings format as VSCode/Cursor.
- Config: `~/Library/Application Support/Antigravity/User/`
- CLI: `/Applications/Antigravity.app/Contents/Resources/app/bin/antigravity` (confirmed exists)

- [ ] **Step 1: Add Antigravity directory detection in deploy_editor_settings()**

In `scripts/shared/helpers.sh`, in `deploy_editor_settings()` (~line 1126), after the `cursor_dir` variable:

```bash
antigravity_dir="$HOME/Library/Application Support/Antigravity/User"
```

- [ ] **Step 2: Add Antigravity deployment block after Cursor block (~line 1158)**

```bash
# Deploy to Antigravity
if [[ -d "$antigravity_dir" ]]; then
    merge_json_settings "$settings_file" "$antigravity_dir/settings.json" "Antigravity"
    install_editor_extensions "antigravity" "$DOT_DIR/config/vscode_extensions.txt"
    deployed=true
fi
```

- [ ] **Step 3: Verify install_editor_extensions handles the antigravity CLI name**

Read the `install_editor_extensions` function to confirm it uses the first arg as the CLI command name. The Antigravity CLI is at `/Applications/Antigravity.app/Contents/Resources/app/bin/antigravity` — check if it's in PATH. If not, either:
- Add a check for the full path as fallback, or
- Skip extension install with a warning if CLI not in PATH

- [ ] **Step 4: Update the log message in deploy_editor_settings() that says "Neither VSCode nor Cursor found"**

Change to:
```bash
log_warning "Neither VSCode, Cursor, nor Antigravity found"
```

- [ ] **Step 5: Commit**

```bash
git add scripts/shared/helpers.sh
git commit -m "feat(antigravity): add Antigravity to editor settings deployment"
```

---

### Task 5: Update CLAUDE.md documentation

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add Zed to deployment components list**

Add after the "Ghostty" bullet:
```
- Zed - Editor config (settings + keymap, symlinked to ~/.config/zed/)
```

Update the existing editor bullet:
```
- VSCode/Cursor/Antigravity settings - Merges with existing settings
```

- [ ] **Step 2: Add config/zed/ to architecture tree**

In the config/ section, after the ghostty line:
```
├── zed/                      # Zed editor config (symlinked to ~/.config/zed/)
│   ├── settings.json         # Zed settings (JSONC, feature parity with Cursor)
│   └── keymap.json           # Custom keybindings (Cmd+K = inline AI edit)
```

- [ ] **Step 3: Add Zed and Antigravity to Important Behaviors / Gotchas**

Add "Zed Deployment" section:
```
**Zed Deployment**:
- Symlinks `config/zed/settings.json` → `~/.config/zed/settings.json`
- Symlinks `config/zed/keymap.json` → `~/.config/zed/keymap.json`
- Backs up existing files if not already symlinks
- SSH connections: Zed reads hosts from `~/.ssh/config` (managed by gist sync). Project paths are machine-specific, added via Zed UI
- Search includes gitignored files by default (`search.include_ignored: true`)
- Extensions auto-installed via `auto_install_extensions` setting (no CLI needed)
- Cmd+K mapped to inline AI edit (overrides Zed's chord prefix — see keymap.json comments for alternatives)
```

Update "Editor Settings" section:
```
**Editor Settings (`deploy_editor_settings()`)**:
- Merges with existing VSCode/Cursor/Antigravity settings (doesn't overwrite)
```

Add to gotchas:
```
- **Zed config**: Symlinked (like Ghostty/Claude). `ssh_connections` are machine-specific (added via Zed UI, hosts from ~/.ssh/config)
- **Antigravity config**: VSCode fork by Google (`com.google.antigravity`). Same settings as Cursor, deployed via `--editor` flag. CLI at `/Applications/Antigravity.app/Contents/Resources/app/bin/antigravity`
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add Zed and Antigravity to CLAUDE.md"
```

---

### Task 6: Curate and update vscode_extensions.txt

**Files:**
- Modify: `config/vscode_extensions.txt`

Currently only 5 of Cursor's 67 installed extensions are tracked. Curated from 67 → ~38 based on user review + community research.

- [ ] **Step 1: Replace config/vscode_extensions.txt with curated list**

```txt
# VSCode/Cursor/Antigravity Extensions
# Deployed by: ./deploy.sh --editor
# Curated from 67 installed → 38 tracked. One extension ID per line.

# === Core Python ===
ms-python.python
ms-python.debugpy
charliermarsh.ruff
astral-sh.ty

# === Jupyter + Data ===
ms-toolsai.jupyter
ms-toolsai.jupyter-keymap
ms-toolsai.jupyter-renderers
ms-toolsai.datawrangler

# === Rust ===
rust-lang.rust-analyzer
vadimcn.vscode-lldb
serayuzgur.crates

# === TypeScript / Web ===
esbenp.prettier-vscode
astro-build.astro-vscode
mattpocock.ts-error-translator
ms-vscode.live-server

# === Remote Development ===
ms-vscode-remote.remote-ssh
ms-vscode-remote.remote-ssh-edit
ms-vscode.remote-explorer

# === Git ===
eamodio.gitlens

# === Data & Config Formats ===
mechatroner.rainbow-csv
lehoanganh298.json-lines-viewer
richie5um2.vscode-sort-json
redhat.vscode-yaml
tamasfe.even-better-toml
dotjoshjohnson.xml
dnicolson.binary-plist

# === Writing ===
james-yu.latex-workshop
ltex-plus.vscode-ltex-plus
mermaidchart.vscode-mermaid-chart

# === AI / Research ===
ukaisi.inspect-ai
rsip-vision.nvidia-smi-plus

# === Productivity ===
usernamehw.errorlens
Gruntfuggly.todo-tree
aaron-bond.better-comments
johnpapa.vscode-peacock
oderwat.indent-rainbow
alefragnani.project-manager

# === Utilities ===
wakatime.vscode-wakatime
tomoki1207.pdf
vscode-icons-team.vscode-icons
```

- [ ] **Step 2: Commit**

```bash
git add config/vscode_extensions.txt
git commit -m "chore: curate editor extensions (5 → 38, categorized)"
```

---

## Verification

1. **Zed config symlinks:**
   - `ls -la ~/.config/zed/settings.json` → symlink to `dotfiles/config/zed/settings.json`
   - `ls -la ~/.config/zed/keymap.json` → symlink to `dotfiles/config/zed/keymap.json`
2. **Zed opens correctly:** `zed .` in a project — verify theme, search includes gitignored files
3. **Cmd+K works:** Open a file in Zed, select text, press Cmd+K → inline AI assist
4. **Antigravity settings:** Open Antigravity, check Settings JSON matches Cursor config
5. **Deploy flags:**
   - `./deploy.sh --help` shows `--zed`
   - `./deploy.sh --minimal --zed` deploys only Zed
   - `./deploy.sh --no-zed` skips Zed
   - `./deploy.sh --only zed` deploys ONLY Zed
6. **Server profile:** `./deploy.sh --profile=server` should NOT deploy Zed
7. **Extension install:** Run `./deploy.sh --only editor` and verify extensions install to Cursor + Antigravity
8. **Antigravity CLI:** Verify `antigravity --list-extensions` works (check PATH or full path fallback)

## Design Decisions

- **Zed as separate component** (not bundled with `--editor`): Different config format (JSONC vs JSON), different deployment (symlink vs merge), different extension system (declarative vs CLI). Bundling would complicate existing merge logic.
- **Symlink (not merge)**: Unlike VSCode/Cursor where existing user settings take precedence, Zed config is fully managed by dotfiles. SSH connections are the only machine-specific part (and those are added via UI, backed by `~/.ssh/config`).
- **Cmd+K override**: User explicitly asked for Cursor's Cmd+K behavior. Breaks Zed's chord prefix, but worth it for muscle memory. Alternatives documented in keymap.json comments.
- **Antigravity in existing --editor flow**: VSCode fork with identical settings format → belongs in `deploy_editor_settings()`, not its own flag.
- **Non-default settings only**: Keeps config readable and forward-compatible. When Zed updates defaults, we don't carry stale values.
- **SSH connections not hardcoded**: Zed reads hosts from `~/.ssh/config` (already synced via gist). Project paths are machine-specific and ephemeral.
- **Extension list curated, not dumped**: Categorized by domain so it's easy to prune. Cursor-specific extensions commented out (won't install on other editors).
- **Cherry-picked community settings**: From SaltyAom and jellydn configs — `indent_aware` coloring, error-only tab diagnostics, toolbar cleanup, hidden notification/collaboration panels. Skipped their opinionated choices (vim mode, hard tabs, copilot, custom fonts).
