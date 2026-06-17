# Plan: Split Global Gitignore — Let Search Tools See Research Files

## Context

`config/gitignore_global` contains universal patterns (OS, editors, Python, LaTeX) AND research patterns (`archive/`, `/data`, `/experiments/`, etc.). Since ripgrep and fd respect `.gitignore` by default, AI tools (Claude Code, Cursor) can't search research files — even though those files are useful context.

**Goal**: Git keeps ignoring everything. Search tools can see research files.

## Research Findings (empirically tested)

| Tool | Global ignore mechanism | Can negate git's global ignore? |
|------|------------------------|-------------------------------|
| **git** | `core.excludesFile` → `~/.gitignore_global` | N/A |
| **rg CLI** | `RIPGREP_CONFIG_PATH` → `--no-ignore-global` + `--ignore-file` | Yes (skips git global, uses own) |
| **fd CLI** | `~/.config/fd/ignore` (native) | **No** (negation doesn't cross ignore layers) |
| **Claude Code** | Uses rg internally, inherits `RIPGREP_CONFIG_PATH` | Yes (via rg) |
| **VS Code/Cursor** | Passes `--no-config` to rg (ignores RIPGREP_CONFIG_PATH) | No via rg; use `search.useGlobalIgnoreFiles: false` |
| **Per-project `.ignore`** | Higher precedence than `.gitignore` in both rg and fd | **Yes** (negation works) |

**Key insight**: Most research projects don't have research patterns in their per-project `.gitignore` — they rely on the global gitignore. So disabling the global ignore for search tools handles the common case. Per-project `.ignore` with negation handles the rest.

## Approach: Two Source Files + Tool-Specific Config

### Step 1: Split source files

```
config/ignore_global    ← Universal patterns (OS, editors, Python, LaTeX, IDE, Claude Code)
                          Expanded from current 3-line version. Single source of truth.
config/ignore_research  ← Research patterns only (~10 lines). Rarely changes.
config/gitignore_global ← DELETE. Generated during deploy from the two above.
```

### Step 2: Deploy targets

| Source | Target | Method | Auto-updates? |
|--------|--------|--------|--------------|
| `ignore_global` + `ignore_research` | `~/.gitignore_global` | concatenate (copy) | No — re-deploy needed |
| `ignore_global` | `~/.ignore_global` | **symlink** | Yes |
| `ignore_global` | `~/.config/fd/ignore` | **symlink** | Yes |
| generated | `~/.config/ripgrep/config` | generated (copy) | No — re-deploy needed |

Symlinks mean changes to `config/ignore_global` take effect immediately for rg and fd. Only `~/.gitignore_global` (composed) needs re-deploy — but that file rarely changes.

### Step 3: Configure ripgrep

Create `~/.config/ripgrep/config`:
```
--no-ignore-global
--ignore-file
/Users/yulong/.ignore_global
```

This tells rg: skip git's `core.excludesFile` (which has research patterns), use `~/.ignore_global` instead (universal only). Per-project `.gitignore` still respected.

Set in `config/zshrc.sh` (near other tool config):
```bash
export RIPGREP_CONFIG_PATH="$HOME/.config/ripgrep/config"
```

### Step 4: Configure VS Code/Cursor

Add to `config/vscode_settings.json`:
```json
"search.useGlobalIgnoreFiles": false
```

This stops editor search from reading `~/.gitignore_global`. Per-project `.gitignore` still respected. Universal patterns (`.DS_Store`, `__pycache__/`, etc.) are covered by per-project `.gitignore` in most projects.

### Step 5: fd — accept limitation

fd has no `--no-ignore-global` flag, and `~/.config/fd/ignore` negation can't override git's global ignore (empirically confirmed). The symlinked `~/.config/fd/ignore` provides universal patterns for fd's own global layer.

For fd to see research files:
- Per-project `.ignore` with negation (same file that helps rg/VS Code)
- Or `fd -I` flag for one-off searches

### Step 6: Per-project `.ignore` template (optional)

For projects that ALSO have research patterns in their per-project `.gitignore`, provide a template:

```gitignore
# .ignore — let search tools (rg, fd, Claude Code, Cursor) see research files
# These patterns negate .gitignore entries so search tools can index them.
# Git still ignores them.
!archive/
!/data
!/experiments
!/results
!/logs
!/out
!/output
!/outputs
```

This can live in `config/ignore_template` and be copied to research projects as needed.

## Files to Modify

| File | Action | Size |
|------|--------|------|
| `config/ignore_global` | EXPAND (3 → ~460 lines, all universal patterns from gitignore_global minus research) | Large |
| `config/ignore_research` | CREATE (~12 lines, research patterns) | Small |
| `config/gitignore_global` | DELETE (replaced by concatenation during deploy) | — |
| `config/ignore_template` | CREATE (~10 lines, negation template for per-project .ignore) | Small |
| `scripts/shared/helpers.sh` | UPDATE `deploy_git_config()` — concatenate, symlink, generate rg config | Medium |
| `config/zshrc.sh` | ADD `RIPGREP_CONFIG_PATH` export | 1 line |
| `config/vscode_settings.json` | ADD `search.useGlobalIgnoreFiles: false` | 1 line |
| `CLAUDE.md` | UPDATE architecture docs | Small |

### deploy_git_config() changes (helpers.sh)

```bash
# Deploy global gitignore (composed from universal + research)
if [[ -f "$DOT_DIR/config/ignore_global" ]] && [[ -f "$DOT_DIR/config/ignore_research" ]]; then
    cat "$DOT_DIR/config/ignore_global" "$DOT_DIR/config/ignore_research" > "$HOME/.gitignore_global"
    log_success "Deployed ~/.gitignore_global (universal + research)"
fi

# Deploy search tool ignore files (universal only, symlinked for auto-update)
if [[ -f "$DOT_DIR/config/ignore_global" ]]; then
    # ripgrep + Claude Code: symlink universal ignore
    ln -sf "$DOT_DIR/config/ignore_global" "$HOME/.ignore_global"
    log_success "Symlinked ~/.ignore_global"

    # fd: symlink to same file
    local fd_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fd"
    mkdir -p "$fd_config_dir"
    ln -sf "$DOT_DIR/config/ignore_global" "$fd_config_dir/ignore"
    log_success "Symlinked $fd_config_dir/ignore"

    # ripgrep config
    if command -v rg &>/dev/null; then
        local rg_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/ripgrep"
        mkdir -p "$rg_config_dir"
        printf '%s\n' "--no-ignore-global" "--ignore-file" "$HOME/.ignore_global" > "$rg_config_dir/config"
        log_success "Deployed $rg_config_dir/config"
    fi
fi
```

## Verification

1. `deploy.sh` and check:
   - `~/.gitignore_global` has universal + research patterns
   - `~/.ignore_global` is a symlink to `config/ignore_global` (universal only)
   - `~/.config/fd/ignore` is a symlink to `config/ignore_global`
   - `~/.config/ripgrep/config` has `--no-ignore-global` and `--ignore-file`
2. In a research project with `data/` dir (only globally gitignored):
   - `git status` → `data/` not listed (still ignored by git)
   - `rg "pattern" data/` → can search
   - Claude Code Grep → can search `data/`
3. VS Code/Cursor search → can find files in `data/`
4. `shellcheck` all modified scripts

## Limitations

- **fd**: No global solution for overriding git's global ignore. Use per-project `.ignore` or `fd -I`.
- **Composed file**: `~/.gitignore_global` is a copy (not symlink) — changes to `config/ignore_global` or `config/ignore_research` need re-deploy. But these change rarely.
- **VS Code/Cursor**: `search.useGlobalIgnoreFiles: false` means universal patterns from the global gitignore aren't applied to editor search. This is fine — per-project `.gitignore` covers them.
