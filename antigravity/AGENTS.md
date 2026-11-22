# Global AGENTS.md (Antigravity)

Authoritative personal instructions live in `~/.gemini/config/GEMINI.md` (symlinked to `claude/CLAUDE.md`) and `~/.gemini/config/rules/*.md` (projected from `claude/rules/*.md`). Edit the source files in `~/code/dotfiles/claude/`, never the generated copies.

Shared Claude guidance describes intent; adapt tool-specific wording to the tools exposed in this Antigravity session. Antigravity compatibility guidance below takes precedence over Claude-only tool names.

## Antigravity Tool Mapping

- `Read`, `Write`, `Edit` → `read_file`, `write_file`, `edit_file`
- `Bash` → `run_command` (use `BypassSandbox: true` instead of `dangerouslyDisableSandbox: true`, and `IsDaemon: true` / `WaitMsBeforeAsync` instead of shell `&`)
- `Glob`, `Grep` → `run_command` with `fd` / `rg`, or native search tools when exposed
- `AskUserQuestion` → `ask_question` for multi-option decisions (plain text for trivial yes/no)
- `Task` / `Agent` → `invoke_subagent` / `define_subagent` for a single delegated task, `run_workflow` for code-driven fan-out/pipelines, or `swarm` when coordinating multiple workers on the shared board
- `WebSearch` / `WebFetch` → `search_web` or browser/MCP tools when available
- `TodoWrite` / `TaskCreate` → concise Markdown checklist or artifact when tracking multi-step work
- `Skill` → activate the discovered skill directly by reading its `SKILL.md` (skills load from `~/.claude/skills` via `~/.gemini/config/skills.json`)

## Scope Notes

- The five standards checklists stay at `~/.claude/checklists/` (writing, presentation, results-analysis, research, experiments); read them from there when a rule or skill points to them.
- `claude/rules/background-jobs.md` applies only to Claude Code background jobs (`~/.claude/jobs/`) and is intentionally excluded here.
- Claude-only hooks, plugins, `model-router` subagent routing, and `mcp__claude_ai_*` hosted connectors are not active in Antigravity unless configured natively in `~/.gemini/config/`.
- **Never put a copyable code block or shell command inside a `>` blockquote** — `agy` draws `│` sidebar pipes on every quoted line, which copy into the clipboard and break pasted commands. Put the warning/caveat in the blockquote if needed, and place the fenced code block immediately below it.
