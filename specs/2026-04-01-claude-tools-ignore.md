# Spec: `claude-tools ignore` — Interactive Ignore Pattern Manager

**Date:** 2026-04-01
**Status:** Draft

## Problem

Git-ignored files (data/, experiments/, logs/) should still be searchable by rg, fd, Claude Code, and Cursor. Today this requires manually creating `.ignore` files with negation patterns per-repo. No tooling exists to apply or manage these patterns.

## Goals

1. Reorganize ignore source files into `config/ignore/` with clear naming and intent comments
2. Build `claude-tools ignore apply` — a ratatui TUI for managing per-repo `.gitignore` and `.ignore` patterns
3. Update `deploy.sh` to use the new file paths

## Non-Goals

- Replacing the global ignore deployment (`deploy.sh --git-config`) — that stays as-is, just new paths
- Per-project config file (`.claude/ignore.yaml`) — the files themselves are the persistence
- Presets/profiles — can be added later; TUI is the primary interface

## Design

### 1. File Reorganization

**Before:**
```
config/
├── ignore_global      # Universal patterns (OS, editors, .venv, node_modules)
├── ignore_research    # Research dirs (data/, experiments/, logs/)
└── ignore_template    # Negation patterns for per-repo .ignore
```

**After:**
```
config/ignore/
├── gitignore_base       # Universal patterns — deployed to git AND search tools
├── gitignore_research   # Research dirs — deployed to git ONLY (search tools skip this)
└── patterns             # Pattern definitions for the interactive TUI
```

Each file gets a clear header comment block explaining:
- What it is
- Who consumes it (git, rg, fd, Claude Code, Cursor)
- How it's deployed (symlink, copy, concatenation)
- How to add new entries

**`config/ignore/patterns`** — simple annotated gitignore-style file, one section per category:

```gitignore
# Pattern definitions for `claude-tools ignore apply`
#
# Format: standard gitignore patterns with inline annotations.
# - Lines starting with # are comments (category headers use ## prefix)
# - Each pattern has a trailing comment: description + default state
# - Default states: [G+S] = gitignore + searchable, [G] = gitignore only
# - The TUI reads this file; users can add custom patterns here.

## research — Research project directories
data/                    # Dataset files [G+S]
experiments/             # Experiment outputs [G+S]
results/                 # Result artifacts [G+S]
out/                     # Output directory [G+S]
output/                  # Output directory (alt) [G+S]
outputs/                 # Output directory (alt) [G+S]
logs/                    # Log files [G+S]
archive/                 # Archived runs [G]

## python — Python build and runtime artifacts
.venv/                   # Virtual environment [G]
__pycache__/             # Bytecode cache [G]
*.egg-info/              # Package metadata [G]
.eggs/                   # Egg build dir [G]
dist/                    # Distribution packages [G]
build/                   # Build output [G]
.mypy_cache/             # Mypy cache [G]
.ruff_cache/             # Ruff cache [G]
.pytest_cache/           # Pytest cache [G]

## node — Node.js artifacts
node_modules/            # Dependencies [G]
.next/                   # Next.js build [G]
.nuxt/                   # Nuxt build [G]

## ml — Machine learning artifacts
checkpoints/             # Model checkpoints [G+S]
wandb/                   # W&B run logs [G+S]
models/                  # Saved models [G]
.cache/huggingface/      # HF model cache [G]

## misc — Common project artifacts
.env                     # Environment secrets [G]
.env.*                   # Environment variants [G]
*.sqlite                 # SQLite databases [G]
```

**Migration:** `ignore_template` is deleted — its role is replaced by the `[G+S]` patterns in `patterns`. The TUI generates `.ignore` negation patterns from these.

### 2. TUI Design (`claude-tools ignore apply`)

Single-screen ratatui TUI. Each pattern gets a tri-state toggle:

```
┌─ claude-tools ignore ──────────────────────────────────┐
│                                                         │
│  ↑↓ navigate   space cycle state   enter apply   q quit │
│                                                         │
│  [ ] skip   [G] gitignore only   [G+S] gitignore + searchable │
│                                                         │
│  research                                               │
│    [G+S] data/              Dataset files               │
│    [G+S] experiments/       Experiment outputs           │
│    [G+S] results/           Result artifacts             │
│    [G+S] out/               Output directory             │
│    [ ]   logs/              Log files                    │
│    [ ]   archive/           Archived runs                │
│                                                         │
│  python                                                 │
│    [G]   .venv/             Virtual environment          │
│    [G]   __pycache__/       Bytecode cache              │
│    [ ]   *.egg-info/        Package metadata             │
│                                                         │
│  ml                                                     │
│    [ ]   checkpoints/       Model checkpoints            │
│    [G+S] wandb/             W&B run logs                │
│                                                         │
│  3 patterns → .gitignore   2 patterns → .ignore         │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**State cycle:** `[ ]` → `[G]` → `[G+S]` → `[ ]` (space key)

**Initial state on launch:**
1. Parse existing `.gitignore` and `.ignore` managed sections
2. For each pattern in `config/ignore/patterns`:
   - If in `.gitignore` managed section AND negated in `.ignore` managed section → `[G+S]`
   - If in `.gitignore` managed section only → `[G]`
   - Otherwise → `[ ]` (but show the default from `patterns` file as hint)
3. Patterns NOT in `config/ignore/patterns` but in managed sections → show as "custom" category

**On enter (apply):**
1. Rewrite `.gitignore` managed section with all `[G]` and `[G+S]` patterns
2. Rewrite `.ignore` managed section with `!` negations for all `[G+S]` patterns
3. If no patterns selected for `.ignore`, don't create it / remove managed section
4. Show summary: "Added N to .gitignore, M searchable in .ignore"

**Status bar** (bottom of TUI): live count of patterns going to each file.

### 3. Managed Sections

Both `.gitignore` and `.ignore` use paired markers:

```gitignore
# User's existing patterns above...

# --- claude-tools ignore begin ---
# Managed by `claude-tools ignore apply`. Do not edit manually.
data/
experiments/
.venv/
__pycache__/
# --- claude-tools ignore end ---
```

```gitignore
# .ignore — search tool overrides
# Managed by `claude-tools ignore apply`. Do not edit manually.

# --- claude-tools ignore begin ---
!data/
!experiments/
# --- claude-tools ignore end ---
```

Rules:
- Managed section always at END of file (after user content)
- On re-apply, only the managed section is rewritten — user entries untouched
- Dedup: if a pattern exists in the user section, skip it in managed section (warn in TUI)
- Normalize trailing slashes for dedup (`data/` matches `data`)
- Preserve leading slashes (anchoring) as-is — `/data` ≠ `data`
- If managed section is empty after apply, remove markers too
- If `.ignore` would be empty (no `[G+S]` patterns), don't create the file

### 4. Other Subcommands

**`claude-tools ignore status`** — non-interactive, shows current state:
```
.gitignore: 4 managed patterns (data/, experiments/, .venv/, __pycache__/)
.ignore:    2 managed patterns (!data/, !experiments/)
Unmanaged:  .gitignore has 12 manual entries
```

**`claude-tools ignore apply --dry-run`** — shows what would change without writing.

**`claude-tools ignore apply --non-interactive`** — applies defaults from `patterns` file without TUI (for scripting/CI).

### 5. Deployment Changes (`deploy.sh` / `helpers.sh`)

Update paths in `deploy_git_config()`:
- `config/ignore_global` → `config/ignore/gitignore_base`
- `config/ignore_research` → `config/ignore/gitignore_research`
- Delete reference to `config/ignore_template`

Logic unchanged:
- `~/.gitignore_global` = `cat gitignore_base gitignore_research`
- `~/.ignore_global` = symlink to `gitignore_base`
- `~/.config/fd/ignore` = symlink to `gitignore_base`
- `~/.config/ripgrep/config` = `--no-ignore-global --ignore-file ~/.ignore_global`

### 6. Documentation Updates

- `CLAUDE.md` architecture section: update `config/` tree and ignore file descriptions
- `README.md`: add `claude-tools ignore` usage
- File header comments in all three `config/ignore/` files

## Implementation Order

1. **File reorganization** — move + rename files, update `helpers.sh` paths, update comments
2. **Pattern file** — create `config/ignore/patterns` with categories and defaults
3. **Ignore module** — `src/ignore/mod.rs`: pattern parser, managed section reader/writer, dedup logic
4. **TUI** — `src/ignore/tui/`: ratatui tri-state toggle, reuse theme from `context/tui/theme.rs`
5. **Wire up** — add `ignore` subcommand to `main.rs`, add `status` and `apply` subcommands
6. **Tests** — managed section parsing, dedup edge cases, round-trip apply
7. **Docs** — update CLAUDE.md, README.md

## Edge Cases

- Repo has no `.gitignore` → create one with only the managed section
- Repo has `.gitignore` but no managed section → append managed section
- Pattern exists in user section AND patterns file → show as already applied, skip in managed section, warn
- Trailing slash normalization: `data/` and `data` treated as equivalent for dedup
- Leading slash preserved: `/data` stays anchored, `data` stays unanchored
- Glob patterns (`*.egg-info/`) — dedup is exact-match only, no glob expansion
- Empty selections → remove managed sections, don't create empty files
- TUI terminal restore on panic — use `crossterm` cleanup hook (same as context TUI)
