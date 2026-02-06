# Agents & Delegation Rules

## Subagent Strategy

**Default: delegate, not do.** Prevent context pollution by letting agents summarize.

Available agents are listed in Task tool description. Use **PROACTIVELY**:

| Agent | Trigger |
|-------|---------|
| `efficient-explorer` | Codebase exploration in large repos (>500 line files) |
| `code-reviewer` | After ANY implementation — don't wait to be asked |
| `performance-optimizer` | Slow code, sequential API calls, missing caching |

**Principles**: Parallelize agents • Be specific • Include size limits in prompts • ASK if unclear

### Concurrent Edit Constraint

**One editor per file.** Never spawn multiple agents to edit the same file.

## Task Delegation Strategy

**Principle:** Skills = workflows you execute, Agents = delegation to external tools.

| Agent | Use Case | Strength |
|-------|----------|----------|
| **gemini-cli** | Large context analysis (>100KB) | 1M+ token window, PDFs, entire codebases |
| **code-toolkit:codex** | Well-scoped implementation | Fast, precise, follows specs exactly |
| **code-toolkit:claude** | Judgment-heavy tasks | Taste, tool use, MCP access, nuanced reasoning |

```
Need delegation?
├─ Large context (PDF, codebase)? → gemini-cli
├─ Clear implementation spec? → code-toolkit:codex
├─ Need judgment/taste? → code-toolkit:claude
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
