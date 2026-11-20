# Global AGENTS.md

Authoritative instructions for Codex CLI agents on this machine. `CLAUDE.md` — global (`~/.claude/CLAUDE.md`) and at the repo root — is the source of truth and is updated more often; adapt tool-specific guidance to the tools exposed in this Codex session. Codex compatibility guidance takes precedence over Claude-only tool assumptions.

For library/API documentation, in order: Context7 MCP → `gh api` for specific files → read the locally installed library → WebSearch last.

# ---------------------------------------------------------------------
# CODEX-ONLY SECTION (do not overwrite from CLAUDE.md syncs)
# ---------------------------------------------------------------------

You MUST refer to instructions in global `CLAUDE.md` at `~/.claude/CLAUDE.md`, and also at the project root.

## Codex-Only Additions
- When listing completed work, use short, clear bullet points suitable for a coworker or manager; avoid run-on sentences.
- Codex runtime files (e.g., `codex/cache/`, `codex/state_*.sqlite`) may change during normal use and around commits/hooks; keep them gitignored to avoid commit churn.

# ---------------------------------------------------------------------
# END CODEX-ONLY SECTION
# ---------------------------------------------------------------------

## Safety
- Never revert or overwrite user changes you did not make. Treat a dirty tree as intentional — uncommitted work is unrecoverable.
- Avoid destructive commands (`git reset --hard`, `rm -rf`, etc.) unless the user demands it.
- Never commit secrets, API keys, or tokens.

## Editing
- Prefer editing existing files over creating new ones, documentation included. If a new file is necessary, explain why.
- Respect repo conventions (helper scripts in `scripts/`, config in `config/`).
- Start shell scripts with `#!/bin/bash` and `set -euo pipefail`; match existing option-parsing patterns.
- Comment only non-obvious logic; don't restate code.
- Run the linters/tests relevant to your change. If you can't (time, sandbox), say so explicitly and suggest follow-ups.

## Reporting
- Concise, friendly, factual. No filler like "Summary:". Lead with the outcome.
- Cite files as clickable `path/to/file:line` — never a line range.
- Name the tests/linters you ran (`Tests: …`); if none, say why.
- Summarize the key lines of command output rather than pasting it whole.
- Keep the response self-contained; the user should not need to scroll back.

## Agent Throughput Awareness
- Never give time estimates — you operate at machine speed, so "days/weeks" is wrong. Never state a cost you haven't actually calculated. Naming complexity is fine; translating it into human-scale duration is not.
- On solo codebases, large breaking changes for quality are encouraged. On shared codebases, keep backwards compatibility.

## Tool Mapping for Skills
Skills under `~/.codex/skills` are written for Claude Code and name its tools. Substitute:
- `TodoWrite` → the exposed plan tool, or a concise checklist if absent
- `Task` / subagents → the exposed Codex collaboration tools
- `Skill` tool references → apply the discovered skill's instructions directly
- `Read`, `Grep`, `Glob` → shell reads, `rg`, `rg --files`, `bat`
- `Write`, `Edit` → `apply_patch`; `Bash` → the exposed shell tool
- `Monitor` / `codex-companion` → native collaboration or review; do not launch nested Codex merely to satisfy a Claude-only workflow

**If a skill applies to the task, use it** — and say which one you're using and why.

<!-- BEGIN CODEX TOOL COMPATIBILITY -->
## Codex tool compatibility

Shared Claude guidance describes intent; adapt it to tools actually exposed in
this Codex session. Do not require tools that are absent.

- Read/search with the exposed shell tool: `rg`, `rg --files`, `bat`, and ordinary
  shell reads are valid. Claude `Read`, `Grep`, and `Glob` are not prerequisites.
- Edit with `apply_patch` when available, otherwise use scoped shell writes.
- Use exposed collaboration tools for subagents. Use an exposed plan tool when
  available, otherwise a concise checklist; do not invent `TodoWrite`.
- Use exposed web/browser tools for lookup; `WebFetch` is not guaranteed.
- `Monitor` and `codex-companion` belong to Claude-to-Codex delegation.
  Inside Codex, use native collaboration/review capabilities. Do not launch
  nested Codex merely to satisfy a Claude-only instruction.
- Follow the shell tool's actual schema for backgrounding and polling; do not
  assume Claude's `run_in_background` or `timeout` parameters exist.

Codex hooks are maintained by `scripts/setup/sync_codex_hooks.py` in dotfiles.
Do not copy Claude credentials, transcript writers, or context-profile hooks
into Codex unchanged. Preserve native approval policy and hook trust review.
<!-- END CODEX TOOL COMPATIBILITY -->
