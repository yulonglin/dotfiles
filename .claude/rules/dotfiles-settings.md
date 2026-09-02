# Dotfiles Settings Safety

This repo is special: `claude/settings.json` is the **source of truth for global Claude Code settings** (deployed via symlink to `~/.claude/settings.json`). The file is dual-written by Claude Code itself and by manual edits, so stash/checkout operations can capture a degraded stub.

## Rule

**NEVER stage `claude/settings.json` without verifying it has `statusLine`, `hooks`, and `permissions` keys.**

Verify:
```bash
python3 -c "import json; d=json.load(open('claude/settings.json')); assert all(k in d for k in ['statusLine','hooks','permissions'])"
```

## The machine-local gateway stays dirty on purpose

`claude/settings.json` is public, but it is also the **only** place Claude Code reads `ANTHROPIC_BASE_URL` from — model-router's own measurements (2.1.222) found an ambient shell `ANTHROPIC_BASE_URL`, a project-level `settings.local.json`, and `CLAUDE_CONFIG_DIR` were all ignored for the base URL, and a user-level `settings.local.json` does not exist at all. So model-router's `http://127.0.0.1:<port>/t/<token>` endpoint cannot be relocated — it can only be kept out of commits.

That means the working tree carries a permanent diff on this file, and that is the intended state, not something to tidy away. gitleaks does not catch the value (a bare hex token in a URL path has no adjacent secret keyword), so the guard is `_validate_no_local_gateway` in `config/git-hooks/pre-commit`, pinned by `tests/test_pre_commit_gateway_guard.sh`.

To commit the file's *other* changes, stage a stripped copy rather than editing the live file (editing it changes your running environment):

```bash
# write a copy without the model-router env keys, then:
SHA=$(git hash-object -w /path/to/stripped.json)
git update-index --cacheinfo 100644,$SHA,claude/settings.json
```

## Scope

- Applies to: `claude/settings.json` (global source — gets symlinked to `~/.claude/`)
- Does NOT apply to: `.claude/settings.json` (project-level override — only specifies deltas, may legitimately contain just `enabledPlugins` + `permissions` or similar)
