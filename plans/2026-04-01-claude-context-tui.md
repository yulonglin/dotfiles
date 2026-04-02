# claude-context TUI — Design Spec

## Goal

Replace the Python `claude-context` CLI with a Rust implementation inside the existing `claude-tools` binary. Add an interactive TUI (via `ratatui`) for profile selection while keeping all non-interactive CLI modes.

## Current State

- **Python** `custom_bins/claude-context` (675 lines) — full CLI: apply, list, sync, clean, help
- **Rust** `context_apply.rs` (263 lines) — fast-path apply only (SessionStart hook)
- Both implement the same core algorithm: registry → base → profiles → overrides → settings.json

## Architecture

### Single subcommand: `claude-tools context`

Replaces both the Python script and the Rust `context-apply` subcommand.

```
claude-tools context                    # TTY? → TUI. No TTY? → apply context.yaml
claude-tools context <profile> [...]    # Non-interactive apply
claude-tools context --list             # Print status (same as Python --list)
claude-tools context --clean [--force]  # Remove project config
claude-tools context --sync [-v]        # Sync marketplaces (shells out to `claude` CLI)
claude-tools context --apply            # Explicit non-interactive apply (for hooks)
claude-tools context --help             # Help text
```

No backwards-compat wrapper — delete `custom_bins/claude-context` and update the 4 call sites:

| File | Change |
|---|---|
| `claude/hooks/context_auto_apply.sh:6` | `claude-context` → `claude-tools context --apply` |
| `claude/hooks/context_auto_apply.sh:11-12` | Help text: `claude-context` → `claude-tools context` |
| `claude/hooks/context_auto_apply.sh:35,38` | `claude-context --sync` → `claude-tools context --sync` |
| `deploy.sh:644-647` | `claude-context --sync -v` → `claude-tools context --sync -v` |

#### Module layout

```
src/
├── main.rs                 # Route subcommands (manual matching, not clap)
├── util.rs                 # Shared helpers (expand_home, etc.)
├── context/
│   ├── mod.rs              # Public API, CLI arg parsing (clap derive)
│   ├── registry.rs         # Load installed_plugins.json → registry map
│   ├── profiles.rs         # Parse profiles.yaml (base, profiles, marketplaces)
│   ├── builder.rs          # Build enabledPlugins from registry + profiles + overrides
│   ├── settings.rs         # Atomic read/write of settings.json + context.yaml
│   ├── sync.rs             # Marketplace sync (shells out to `claude` CLI)
│   ├── display.rs          # Non-interactive output (--list, apply summary)
│   └── tui/
│       ├── mod.rs          # Elm-style app: init, update, view
│       ├── state.rs        # App state (profiles, selection, scroll position)
│       └── theme.rs        # Colors, borders, symbols
├── context_apply.rs        # DELETE in Phase 6 — absorbed into context/
├── statusline.rs
├── usage.rs
├── check_git_root.rs
└── resolve_file_path.rs
```

Module dependency DAG (no cycles): `registry` ← `profiles` ← `builder` ← `settings` ← `tui/`, `display`, `sync`

### Dependencies to add

Use latest versions at implementation time.

```toml
ratatui = "*"             # TUI framework (pin to latest at impl time)
crossterm = "*"           # Terminal backend (pin to latest at impl time)
clap = { version = "*", features = ["derive"] }  # Arg parsing
```

## TUI Design

### Layout

```
┌ claude-context ──────────────────────────────┐
│                                              │
│  Active: code, python                        │
│                                              │
│  ● code         Software projects            │
│    ├ code-simplifier                         │
│    ├ codex                                   │
│    ├ security-guidance                       │
│    └ workflow                                │
│  ○ design       Frontend, visualizations     │
│  ○ research     Experiments, evals           │
│  ○ writing      Papers, blog posts           │
│  ○ ml           Adds huggingface-skills      │
│  ○ personal     Life — Things 3              │
│  ● python       Adds pyright-lsp             │
│  ○ web          Web dev + browser            │
│                                              │
│  space: toggle  enter: apply  q: quit        │
└──────────────────────────────────────────────┘
```

### Interaction

| Key | Action |
|-----|--------|
| `↑`/`k` | Move cursor up |
| `↓`/`j` | Move cursor down |
| `space` | Toggle profile on/off |
| `enter` | Apply selection → write context.yaml + settings.json → exit |
| `q`/`esc` | Quit without changes |
| `a` | Select all |
| `n` | Select none |

### Behavior

- **Highlighted profile expands** to show its plugins (tree view: `├`/`└` branches)
- **Base plugins** are not shown (always on, not toggleable)
- **Active profiles** loaded from `context.yaml` on startup (pre-checked)
- **"Active:" header** updates live as user toggles profiles
- **No confirmation dialog** — `enter` applies immediately (matches current CLI behavior)
- **Dirty indicator** — if selection differs from current context.yaml, show `[modified]` in header

### TTY Detection

Use `std::io::IsTerminal` (stable since Rust 1.70, no extra crate — `atty` is deprecated):

```rust
use std::io::IsTerminal;

if std::io::stdout().is_terminal() && args.profiles.is_empty() && !args.list && !args.clean && !args.sync {
    tui::run()?;  // Interactive
} else {
    // Non-interactive (same as current behavior)
}
```

Add `--tui` flag to force TUI even when not a TTY (useful for testing).

## Core Logic (reuse from context_apply.rs)

The existing functions move into `context/` modules with minimal changes:

| Current function | New location | Changes |
|---|---|---|
| `load_registry()` | `registry.rs` | Make public, add `&self` on struct |
| `build_plugins()` | `builder.rs` | Return `Vec<(name, qid, enabled)>` for TUI consumption |
| `apply_to_settings()` | `settings.rs` | Add `write_context_yaml()` |
| `expand_home()` | `util.rs` (new, shared across all modules) | Also used by statusline.rs |

### Marketplace sync

Shells out to `claude` CLI (same as Python):
- `claude plugin marketplace list` → parse registered names
- `claude plugin marketplace add <source>` → register new
- `claude plugin marketplace update <name>` → update (parallel via `std::thread::spawn` + `join` — simple, no new deps, fine for 3-7 marketplaces)

Post-sync steps (all ported from Python, ~100 lines total):
1. `fix_hook_permissions()` — chmod +x all `.sh` files in `~/.claude/plugins/marketplaces/`
2. `apply_auto_update()` — set `autoUpdate` in `known_marketplaces.json` from profiles.yaml config
3. `normalize_scopes()` — replace `"local"` → `"project"` scope in `installed_plugins.json`
4. Stale settings check — warn if project settings.json references plugins with changed qualified IDs

### Concurrency & safety

- **Atomic writes**: temp file + `fs::rename()` (POSIX atomic on same filesystem — guaranteed for settings.json since temp is in same dir)
- **No lockfile needed**: TUI is only run interactively; hooks use `--apply` which is fire-and-forget. User won't be in TUI during SessionStart hook.

## Migration Plan

1. **Phase 1**: Build `context/` module with all core logic (registry, profiles, builder, settings)
2. **Phase 2**: Build TUI (`tui/` submodule)
3. **Phase 3**: Build CLI modes (list, clean, sync) + arg parsing
4. **Phase 4**: Wire into `main.rs` — add `"context"` subcommand, keep `"context-apply"` as alias
5. **Phase 5**: Update hooks + deploy.sh call sites, delete Python `custom_bins/claude-context`
6. **Phase 6**: Delete `context_apply.rs`, add `util.rs` (shared `expand_home`)
7. **Phase 7**: Update docs (CLAUDE.md, README.md)

### clap strategy

Use clap derive only within the `context` subcommand (not for top-level routing in main.rs — keep that as manual matching to avoid bloating other subcommands' compile paths).

## Non-goals

- Plugin-level toggling in TUI (only profiles — individual plugin overrides stay CLI-only via context.yaml `enable:`/`disable:` fields)
- Fuzzy search (8 profiles don't need it)
- Mouse support (keyboard-only is fine)

## Success Criteria

- `claude-tools context` binary starts in <10ms (non-interactive), <50ms (TUI render)
- All existing `claude-context` CLI flags work identically
- TUI shows profiles with expand-on-highlight plugin list
- SessionStart hook uses `claude-tools context --apply` (no Python dependency)
- Python `claude-context` script deleted after migration
