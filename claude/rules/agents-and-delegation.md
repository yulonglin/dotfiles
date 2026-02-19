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

```
Need delegation?
├─ Large context (PDF, codebase)? → gemini-cli
├─ Generate or edit images? → gemini-cli (Nano/Flash/Pro)
├─ Create/edit Google Docs, Sheets, Drive files? → gemini-cli
├─ Plan needs critique? → code:plan-critic (+ core:claude in parallel)
├─ Clear implementation spec/plan? → core:codex
├─ Bug with clear repro? → core:codex (+ debugger for investigation)
├─ Need judgment/taste? → core:claude
├─ Code review needed? → code:code-reviewer (+ code:codex-reviewer for significant changes)
└─ Multi-step workflow? → Use skills
```

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
