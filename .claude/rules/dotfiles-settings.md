# Dotfiles Settings Safety

This repo is special: `claude/settings.json` is the **source of truth for global Claude Code settings** (deployed via symlink to `~/.claude/settings.json`). The file is dual-written by Claude Code itself and by manual edits, so stash/checkout operations can capture a degraded stub.

## Rule

**NEVER stage `claude/settings.json` without verifying it has `statusLine`, `hooks`, and `permissions` keys.**

Verify:
```bash
python3 -c "import json; d=json.load(open('claude/settings.json')); assert all(k in d for k in ['statusLine','hooks','permissions'])"
```

## The gateway and hook-comment notes load on demand

Why the gateway lives in a managed drop-in, and why comments inside hook groups do not survive Claude Code's own writes, are in [`model-router-gateway.md`](model-router-gateway.md), which loads when a session touches `claude/settings.json`, `config/model-router.toml`, `custom_bins/model-router-wire`, the pre-commit hook or the gateway tests.

## Scope

- Applies to: `claude/settings.json` (global source — gets symlinked to `~/.claude/`)
- Does NOT apply to: `.claude/settings.json` (project-level override — only specifies deltas, may legitimately contain just `enabledPlugins` + `permissions` or similar)
