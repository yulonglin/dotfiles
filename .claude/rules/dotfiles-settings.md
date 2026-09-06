# Dotfiles Settings Safety

This repo is special: `claude/settings.json` is the **source of truth for global Claude Code settings** (deployed via symlink to `~/.claude/settings.json`). The file is dual-written by Claude Code itself and by manual edits, so stash/checkout operations can capture a degraded stub.

## Rule

**NEVER stage `claude/settings.json` without verifying it has `statusLine`, `hooks`, and `permissions` keys.**

Verify:
```bash
python3 -c "import json; d=json.load(open('claude/settings.json')); assert all(k in d for k in ['statusLine','hooks','permissions'])"
```

## If the gateway is ever re-enabled, it lives only in the working copy

**The gateway is currently OFF** (unwired 2026-08-18): neither the committed `claude/settings.json` nor the deployed `~/.claude/settings.json` carries any `ANTHROPIC_*` env key, so today there is no permanent diff on this file. The rest of this section describes the state to return to if it is re-enabled — and note that a non-Anthropic `ANTHROPIC_BASE_URL` hard-disables Remote Control, which is why it was unwired (`docs/remote-control-and-foreign-models.md`, 2026-09-01).

`claude/settings.json` is public, but it is also the **only** place Claude Code reads `ANTHROPIC_BASE_URL` from — model-router's own measurements (2.1.222) found an ambient shell `ANTHROPIC_BASE_URL`, a project-level `settings.local.json`, and `CLAUDE_CONFIG_DIR` were all ignored for the base URL, and a user-level `settings.local.json` does not exist at all. So model-router's `http://127.0.0.1:<port>/t/<token>` endpoint cannot be relocated — it can only be kept out of commits.

While the gateway is on, the working tree carries a permanent diff on this file, and that is the intended state, not something to tidy away. gitleaks does not catch the value (a bare hex token in a URL path has no adjacent secret keyword), so the guard is `_validate_no_local_gateway` in `config/git-hooks/pre-commit`, pinned by `tests/test_pre_commit_gateway_guard.sh`.

To commit the file's *other* changes, stage a stripped copy rather than editing the live file (editing it changes your running environment):

```bash
# write a copy without the model-router env keys, then:
SHA=$(git hash-object -w /path/to/stripped.json)
git update-index --cacheinfo 100644,$SHA,claude/settings.json
```

## Comments inside hook groups do not survive Claude Code's own writes

Claude Code rewrites this file itself — `/model`, `/plugin` and any other settings write parse it through a zod schema and re-serialise. The hook-group schema is a plain `{matcher, hooks}` object, so an unknown key such as `"//"` inside a hook group is stripped on the next write (measured 2.1.261, 2026-09-06: `/model fable` deleted the only comment in the file 1.3 s after the command). Restoring such a comment only recreates a permanent dirty diff. Notes about the hooks belong here instead. The one that was stripped:

> Gating a hook off compact is only safe when EVERYTHING it does is redundant after a compaction, and that is a property of the hook body, not of the source. show_auth_account.sh was tried here and moved back above: it recomputes a near-limit warning from a mutable usage cache — a side effect, not display — and now suppresses only its static output when source=compact, which recovers the noise without dropping live work. check_git_root.sh is left because it is purely a warning; the accepted cost is that a mid-session CWD change stops being re-warned after a compact. WARNING, this matcher IS a four-value allowlist despite reading like an exclusion of compact: SessionStart currently emits exactly startup, resume, clear, compact and fork, so today it excludes compact and nothing else, but a source added in a future release would be silently skipped here with no error and must be added by hand. Said explicitly because a comment asserting a safety property the code does not have is what hid the consent bug in issue #55.

## Scope

- Applies to: `claude/settings.json` (global source — gets symlinked to `~/.claude/`)
- Does NOT apply to: `.claude/settings.json` (project-level override — only specifies deltas, may legitimately contain just `enabledPlugins` + `permissions` or similar)
