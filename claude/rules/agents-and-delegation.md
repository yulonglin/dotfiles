# Agents & Delegation Rules

## Subagent Strategy

**Default: delegate, not do.** Prevent context pollution by letting agents summarize.

Available agents are listed in Task tool description. Use **PROACTIVELY**:

| Agent | Trigger |
|-------|---------|
| `efficient-explorer` | Codebase exploration in large repos (>500 line files) |
| `code-reviewer` | After ANY implementation — don't wait to be asked |
| `plan-critic` | Before implementing plans with arch decisions, migrations, auth, concurrency |
| `codex-reviewer` | After significant implementation, alongside code-reviewer |
| `performance-optimizer` | Slow code, sequential API calls, missing caching |

**Principles**: Parallelize agents • Be specific • Include size limits in prompts • ASK if unclear

### Concurrent Edit Constraint

**One editor per file.** Never spawn multiple agents to edit the same file.

## Task Delegation Strategy

**Principle:** Skills = workflows you execute, Agents = delegation to external tools.

| Agent | Use Case | Strength |
|-------|----------|----------|
| **gemini-cli** | Large context analysis (>100KB); image generation/editing (Nano Banana / Nano Banana Pro); Google Workspace (Docs, Sheets, Drive) | 1M+ token window, PDFs, entire codebases, multimodal, native Google auth |
| **core:codex** | Well-scoped implementation | Fast, precise, follows specs exactly |
| **core:claude** | Judgment-heavy tasks | Taste, tool use, MCP access, nuanced reasoning |

### Google Workspace Access

Two options for Google Docs/Sheets/Drive/Gmail/Calendar:

| Tool | Use Case | How |
|------|----------|-----|
| **gws** (Google Workspace CLI) | Direct API calls — read/write Docs, Sheets, Drive, Gmail, Calendar | `gws docs documents get --id <docId>`, `gws drive files list` — structured JSON output, works from Bash |
| **gemini-cli** (via agent) | AI-mediated Google Workspace tasks — summarize, analyze, compose | Delegate via `core:gemini-cli` agent — native Google auth, can reason over content |

**Decision tree:**
- Need raw content (read a doc, list files, export)? → `gws` via Bash (faster, no agent overhead)
- Need AI reasoning over Google content (summarize, draft, analyze)? → `gemini-cli` agent
- Both fail? → Ask user to export/copy-paste

```
Need delegation?
├─ Large context (PDF, codebase)? → gemini-cli
├─ Generate or edit images? → gemini-cli (Nano/Flash/Pro)
├─ Google Workspace (read/write)?
│   ├─ Raw API call (get doc, list files)? → gws via Bash
│   └─ AI reasoning over content? → gemini-cli agent
├─ Plan needs critique? → code:plan-critic (+ core:claude in parallel)
├─ Clear implementation spec/plan? → core:codex
├─ Bug with clear repro? → core:codex (+ debugger for investigation)
├─ Need judgment/taste? → core:claude
├─ Code review needed? → code:code-reviewer (+ code:codex-reviewer for significant changes)
└─ Multi-step workflow? → Use skills
```

## CLI Agent Delegation Enforcement

**Problem:** `core:codex`, `core:gemini-cli`, and `core:claude` agents are Claude instances that can answer directly instead of calling their CLI. Without explicit CLI invocation in the prompt, they sometimes just respond with their own reasoning — defeating the purpose.

**Rule:** When spawning CLI-backed agents, the prompt MUST include the exact Bash command to run.

| Agent | Required prompt pattern |
|-------|------------------------|
| `core:codex` | `You MUST use the Bash tool to run: codex exec --full-auto -C <dir> -o <out> "<prompt>"` |
| `core:gemini-cli` | `You MUST use the Bash tool to run: gemini -p "<prompt>"` |
| `core:claude` | `You MUST use the Bash tool to run: claude -p --model <model> --permission-mode bypassPermissions "<prompt>"` |

**Anti-pattern** (agent answers directly instead of delegating):
```
prompt: "What's the architecture of this codebase?"
→ Agent writes a text response using its own reasoning ❌
```

**Correct pattern** (agent delegates to CLI):
```
prompt: "You MUST use the Bash tool to run: gemini -p '@src/ Summarize the architecture of this codebase'"
→ Agent calls Bash with the gemini command ✅
```

**Diagnostic:** If a CLI agent returns with 0 tool_uses, it failed to delegate — the prompt was too question-like. Rephrase as an explicit CLI command.

## Known Issue: Codex CLI Sandbox Crash on macOS (Temporary)

**Bug:** `codex exec` panics inside Claude Code's sandbox with `SCDynamicStoreCreate NULL` (system-configuration crate v0.6.1). The sandbox blocks access to macOS's `configd` daemon unix socket, and the Rust crate panics on NULL instead of handling it gracefully. Tracked: openai/codex#15640, #15296.

**Workaround:** ALL Bash tool calls that invoke `codex exec` (directly or via agents like `core:codex`, `code:plan-critic`, `code:codex-reviewer`) MUST use `dangerouslyDisableSandbox: true`. The agent definitions include this instruction, but the parent agent spawning them should also be aware.

**Not affected:** `codex --version`, `codex --help`, `codex models` (no HTTP client initialization).

**Remove this section** when codex upgrades the `system-configuration` crate.

## Agent Teams (Escalation)

For multi-agent communication, see `~/.claude/docs/agent-teams-guide.md`.

```
Task complexity?
├─ Single focused output? → Subagent (Task tool)
├─ 2-3 independent outputs? → Parallel subagents
├─ Parallel + needs inter-agent communication? → Agent Team
└─ Unclear? → Start with subagents, escalate if needed
```

## Known Issue: `classifyHandoffIfNeeded` False Failures (Temporary)

**Bug:** Claude Code agents crash on completion with `classifyHandoffIfNeeded is not defined`. This is a build bug — the function is referenced but never defined. Tracked in 16+ issues: https://github.com/anthropics/claude-code/issues?q=classifyHandoffIfNeeded

**What actually happens:** Agent work completes successfully (files written, commits made, all tool calls finish). The crash occurs AFTER completion during the handoff step. Task tool falsely reports `status: failed`.

**Required behavior when you see this error:**

1. **Do NOT treat as a real failure** — the work is done
2. **Verify the output exists** — check files, git log, or expected artifacts on disk
3. **If output exists → proceed as if agent succeeded** — use the results normally
4. **Do NOT retry the agent** — retrying wastes context and produces duplicate work
5. **For background agents** — read the output file; the data is there despite the failure notification

**Remove this section** when the upstream fix lands (check: `claude --version` changelog).
