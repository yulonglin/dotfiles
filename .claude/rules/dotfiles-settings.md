# Dotfiles Settings Safety

This repo is special: `claude/settings.json` is the **source of truth for global Claude Code settings** (deployed via symlink to `~/.claude/settings.json`). The file is dual-written by Claude Code itself and by manual edits, so stash/checkout operations can capture a degraded stub.

## Rule

**NEVER stage `claude/settings.json` without verifying it has `statusLine`, `hooks`, and `permissions` keys.**

Verify:
```bash
python3 -c "import json; d=json.load(open('claude/settings.json')); assert all(k in d for k in ['statusLine','hooks','permissions'])"
```

## The gateway and hook-comment notes load on demand

Why the gateway lives in a managed drop-in, and why comments inside hook groups do not survive Claude Code's own writes, are in [`model-router-gateway.md`](model-router-gateway.md), which loads when a session touches `claude/settings.json`, `config/model-router.toml`, `custom_bins/model-router-wire`, the pre-commit hook, the gateway hooks or the gateway tests.

## The advisor reminder reads the transcript and never blocks

The `Stop` group ends with `nudge_advisor_skipped.py`, which reminds the model once per session, as Stop `hookSpecificOutput.additionalContext`, when a substantive session never called the advisor. **The advisor is a server-side tool, and the transcript records each call**: an assistant content block `{"type":"server_tool_use","name":"advisor","id":"srvtoolu_..."}` followed by an `advisor_tool_result` block, measured on Claude Code 2.1.296 on 2026-10-12 in a live session's own JSONL and in two transcripts from 2026-10-08. Availability is the `{"type":"advisor_tool","available":true,...}` attachment. An earlier draft of this hook (2026-09-20) found no such rows and relied on a `PostToolUse` marker instead; that marker is gone, and whether `PostToolUse` fires for a server-side tool was never shown and no longer matters. If a future release stops recording the call, the reminder fires on every substantive session, which is visible and bounded: it continues the turn once per session and never blocks. Turn it off with `nudges.advisor-skipped = off` in `claude/hooks/features.conf`.

**It goes to the model, not a block.** Since 2026-11-21 (#191) the reminder is Stop `hookSpecificOutput.additionalContext`: the model sees it and the turn continues once, under the same loop limits as `decision: "block"` (`stop_hook_active` and the continuation cap). Before that it was a user-only `systemMessage`; go back to that if the reminder proves inaccurate in daily use.

**The before-work leg is deliberately not enforced.** The advisor is meant to be consulted before substantive work as well as before declaring done, but no event can observe that leg without firing on every session: a `PreToolUse` gate on the first `Write`/`Edit` cannot tell a one-line fix from a day's work.

## Scope

- Applies to: `claude/settings.json` (global source — gets symlinked to `~/.claude/`)
- Does NOT apply to: `.claude/settings.json` (project-level override — only specifies deltas, may legitimately contain just `enabledPlugins` + `permissions` or similar)
