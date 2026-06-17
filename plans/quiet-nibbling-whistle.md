# Update Atuin Configuration

## Context

Atuin (v18.12.1) is already installed and integrated in the dotfiles. The user wants: `--disable-ctrl-r` on init, `filter_mode = "directory"`, `workspaces = true`, `sync_frequency = "5m"`, and no keyboard shortcuts.

All config keys validated against `atuin default-config`. Both init flags (`--disable-ctrl-r`, `--disable-up-arrow`) confirmed as the only two available.

## Changes (6 edits across 3 files)

### 1. `config/zshrc.sh` — Add `--disable-ctrl-r` flag (2 edits)

Lines 141 and 143: append `--disable-ctrl-r` to both `atuin init zsh` calls (if/elif branches).

```diff
-    eval "$(atuin init zsh --disable-up-arrow)"
+    eval "$(atuin init zsh --disable-up-arrow --disable-ctrl-r)"
```

### 2. `deploy.sh` — Add `--disable-ctrl-r` to bash init (2 edits)

Lines 178 and 180 (inside bashrc heredoc): append `--disable-ctrl-r` to both `atuin init bash` calls.

```diff
-    eval "\$(atuin init bash --disable-up-arrow)"
+    eval "\$(atuin init bash --disable-up-arrow --disable-ctrl-r)"
```

### 3. `config/atuin.toml` — Update config (4 changes, 2 edits)

| Line | Change | Notes |
|------|--------|-------|
| 9 | `filter_mode = "global"` → `"directory"` | With `--disable-ctrl-r`, only affects manual `atuin search` |
| 5 | After `auto_sync = true`, add `sync_frequency = "5m"` | Default is `"10m"` |
| 8 | After `search_mode = "fuzzy"`, add `workspaces = true` | Auto-detects git repos, no extra config needed |
| 26-27 | Delete `# Key bindings` comment + `ctrl_n_shortcuts = true` | TUI-only, but user wants no shortcuts |

Keep all other settings (fuzzy search, secrets_filter, show_preview, etc.).

`filter_mode_shell_up_key_binding = "directory"` stays — inactive (up-arrow disabled) but harmless.

## Not Changed

- `install.sh` — already installs Atuin (brew/macOS, setup.sh/Linux)
- `deploy.sh:209-214` — already copies `config/atuin.toml` → `~/.config/atuin/config.toml`
- `--disable-up-arrow` kept (user confirmed)

## Verification

1. Diff all 3 files to confirm 6 edits
2. Run `./deploy.sh --minimal --shell` to deploy
3. Verify `~/.config/atuin/config.toml` has: `workspaces = true`, `filter_mode = "directory"`, `sync_frequency = "5m"`, no `ctrl_n_shortcuts`
4. `source ~/.zshrc` — no errors
5. Press Ctrl+R — verify shell's native `reverse-i-search` appears (not Atuin TUI)
6. User manually runs `atuin register`/`atuin login` + `atuin sync`
