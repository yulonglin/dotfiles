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
