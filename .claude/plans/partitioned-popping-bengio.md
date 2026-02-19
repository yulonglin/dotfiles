# Plan: Add Language & Tooling Preferences to Coding Conventions

## Context

Coding conventions (`rules/coding-conventions.md`) already cover Python basics (uv, ruff) and JS package managers (bun > pnpm > npm), but lack:
1. Language selection philosophy (when to use what)
2. TypeScript tooling stack (biome as ruff equivalent)
3. Systems language preference for performance-critical work
4. `ty` mention for Python type checking

## Changes

### File: `claude/rules/coding-conventions.md`

**1. Add `ty` to Python Basics section** (after the existing ruff mention):
- Add `ty` as the type checker alongside existing ruff linting

**2. Add new "TypeScript" section** (after Python Basics):
```
## TypeScript

- Prefer TypeScript over JavaScript for all frontend/Node work
- Tooling: bun (runtime + pkg mgr) + tsc (types) + Biome (lint + format)
- Biome replaces ESLint + Prettier — single Rust-based binary
```

**3. Add new "Language Selection" section** (after Package Managers):
```
## Language Selection

| Need | Default | When to reconsider |
|------|---------|-------------------|
| ML / research / prototyping | Python | — |
| Frontend / scripting / APIs | TypeScript | Plain JS only for trivial scripts |
| Performance-critical CLI/tools | Rust | Go if team familiarity matters; Zig for low-level/embedded |
| Shell glue | Bash/Zsh | Python if >50 lines or needs error handling |

This is a preference order, not a mandate. Match the tool to the job.
```

## Verification

- `shellcheck` not applicable (markdown only)
- Confirm no duplication with existing sections
- Confirm MEMORY.md doesn't need a copy (rules/ is auto-loaded, memory is for ephemeral insights)
