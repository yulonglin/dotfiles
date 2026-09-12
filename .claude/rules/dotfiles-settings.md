# Dotfiles Settings Safety

This repo is special: `claude/settings.json` is the **source of truth for global Claude Code settings** (deployed via symlink to `~/.claude/settings.json`). The file is dual-written by Claude Code itself and by manual edits, so stash/checkout operations can capture a degraded stub.

## Rule

**NEVER stage `claude/settings.json` without verifying it has `statusLine`, `hooks`, and `permissions` keys.**

Verify:
```bash
python3 -c "import json; d=json.load(open('claude/settings.json')); assert all(k in d for k in ['statusLine','hooks','permissions'])"
```

## The gateway is ON and lives only in the working copy

**The model-router gateway is wired** (re-enabled 2026-09-06 under Option C of [the model-routing decision spec](../../artifacts/model-routing-decision/spec.md), after being unwired 2026-08-18): the deployed `~/.claude/settings.json`, which is this file through the `~/.claude` symlink, carries `env.ANTHROPIC_BASE_URL` pointing at the loopback router plus `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL`, `ENABLE_TOOL_SEARCH`, `CLAUDE_CODE_MAX_CONTEXT_TOKENS` and a `modelPicker` block, and the committed copy carries none of them. **`config/model-router.toml` is the one place that says which foreign models exist, and whether each is on, in the picker, or an agent** (and, under `provider = "anthropic"`, which older Claude models get a picker row, since Claude Code hides its own legacy rows on the first-party provider); `model-router-wire apply` (in `custom_bins/`) renders it into the router's config, those settings keys and the generated `claude/agents/<id>.md` files, `off` unwires the settings, and `status` reports drift. Never hand-edit the rendered keys or the generated agent files. A non-Anthropic `ANTHROPIC_BASE_URL` hard-disables Remote Control, which is the accepted cost: romp over Tailscale is the remote path (`docs/romp-tailnet-access.md`), `remoteControlAtStartup` is off, and the `claude()` wrapper's `rc-direct-settings.json` override (which blanks the gateway for one session) is opt-in under `CLAUDE_RC_OVERRIDE=1` with the file itself archived under `archive/2026-09-06_rc-direct-settings/` — it used to be the default, which un-gated every interactive session, and shells started before the flip kept doing so until the file was gone. `tests/test_model_router_gateway.sh` is the one-command smoke test to run after every Claude Code upgrade.

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
