# Plan: Update CLI delegation skills with review capabilities + add claude-code skill

## Summary

Three updates to the CLI delegation ecosystem:
1. **codex-cli**: Add second-opinion/plan-review use case, model switching (`-m` / `-c model_reasoning_effort`), and sharper characterization (instruction-following > judgment)
2. **gemini-cli**: Add second-opinion/plan-review use case
3. **New `claude-code` skill**: Delegate tasks to Claude Code CLI (`claude -p`) for a Claude-powered second pair of eyes

All three share the `delegates` tmux session and `<tool>-<task>-<MMDD>-<HHMM>` naming.

## Changes

### 1. Update `codex-cli` skill

**File:** `claude/local-marketplace/plugins/code-toolkit/skills/codex-cli/SKILL.md`

**a) Frontmatter — add to "Use when":**
- Getting a second opinion on an implementation plan or approach

**b) Frontmatter — add to "Do NOT use for":**
- Tasks requiring judgment, taste, or subjective design decisions (Codex is instruction-following, not taste-driven)

**c) New section: "Strengths & Limitations"** (after "When to Use"):
- **Strong at**: Precise implementation, following specs exactly, catching concrete errors, structured code generation
- **Weak at**: Ambiguous requirements, architectural taste, naming/style judgment, subjective quality decisions
- **Rule of thumb**: If you can write a verification command, Codex can probably do the task well

**d) New section: "Model Selection"** (replace existing brief note):
- Default: trust `~/.codex/config.toml` (`model` and `model_reasoning_effort` keys)
- Override per-call with `-m <model>` or `-c model_reasoning_effort="xhigh"`
- Guidelines:
  | Task complexity | Flag |
  |---|---|
  | Simple implementation, boilerplate | Default (high) |
  | Complex logic, tricky edge cases | `-c model_reasoning_effort="xhigh"` |
  | Plan review / second opinion | `-c model_reasoning_effort="xhigh"` |

**e) New section: "Second Opinion on Plans"** (after Result Integration):
- Use sync mode with xhigh reasoning
- Prompt template: provide plan text, ask to critique — missed edge cases, simpler alternatives, potential issues
- Example command: `codex exec --full-auto -c model_reasoning_effort="xhigh" -C <dir> -o /tmp/review.txt "Review this plan: <plan>. Identify: 1) Missed edge cases 2) Simpler alternatives 3) Potential issues"`

### 2. Update `gemini-cli` agent

**File:** `claude/agents/gemini-cli.md`

**a) Add example to description block:**
```
<example>
Context: User wants a second opinion on an implementation plan
user: "Review my implementation plan before I start coding"
assistant: "I'll use the gemini-cli agent to review the plan alongside the relevant source code for a comprehensive second opinion."
<commentary>
Gemini's large context lets it review the plan AND the full codebase simultaneously, catching missed files or architectural issues.
</commentary>
</example>
```

**b) New section: "SECOND OPINION ON PLANS"** (before LIMITATIONS):
- Gemini excels here because it can ingest the full plan + entire codebase in one pass
- Prompt pattern: `gemini -p "@.claude/plans/plan.md @src/ Review this implementation plan. Identify: 1) Missed edge cases 2) Simpler alternatives 3) Files needing changes not mentioned 4) Potential breaking changes"`
- Add to Common Patterns section as a new pattern block

### 3. Create `claude-code` skill

**File:** `claude/local-marketplace/plugins/code-toolkit/skills/claude-code/SKILL.md`

**Frontmatter:**
- name: `claude-code`
- description: Delegate tasks to Claude Code CLI for a Claude-powered second opinion, parallel implementation, or plan review. Use when you want Claude (not Codex/Gemini) as a delegate — e.g., tasks needing Claude's judgment, tool use, or MCP access.
- Do NOT use for: tasks better suited to Codex (pure implementation) or Gemini (large context analysis)

**Body sections:**

**When to Use** table:
| Use claude-code | Don't use |
|---|---|
| Second opinion on plan/approach | Pure implementation (use codex-cli) |
| Tasks needing Claude's judgment/taste | Large context analysis (use gemini-cli) |
| Parallel independent implementation | Quick <10 line edits |
| Tasks needing MCP server access | Tasks you're already doing |

**Strengths & Limitations:**
- Strong at: judgment, taste, nuanced reasoning, tool use, MCP access
- Complementary to Codex (instruction-following) and Gemini (large context)

**Execution Modes:**

Sync:
```bash
claude -p --model sonnet --permission-mode bypassPermissions "<prompt>"
# Or pipe to file:
claude -p --model sonnet --permission-mode bypassPermissions "<prompt>" > /tmp/claude-review.txt
```

Async (tmux):
```bash
TASK_NAME="claude-<short-desc>-$(date -u +%m%d-%H%M)"
tmux has-session -t delegates 2>/dev/null || tmux new-session -d -s delegates -n default
tmux new-window -t delegates -n "$TASK_NAME"
tmux-cli send "cd $(pwd) && claude -p --model sonnet --permission-mode bypassPermissions '<prompt>' 2>&1 | tee /tmp/${TASK_NAME}.log" --pane="delegates:${TASK_NAME}.1"
```

**Model Selection:**
| Task | Model |
|---|---|
| Quick review, simple tasks | `--model haiku` |
| Standard tasks, plan review | `--model sonnet` |
| Complex judgment, architecture | `--model opus` |

**Second Opinion on Plans:**
- Same pattern as codex-cli but leveraging Claude's judgment
- Example: `claude -p --model sonnet "Review this implementation plan and identify missed edge cases, simpler alternatives, and potential issues: $(cat .claude/plans/plan.md)"`

**Session naming:** `claude-<task>-<MMDD>-<HHMM>` in shared `delegates` session.

## Verification

1. Read all three updated/created files and confirm coherence
2. Verify YAML frontmatter parses correctly (no syntax issues)
3. Smoke test: `codex exec --full-auto -c model_reasoning_effort="xhigh" -C . -o /tmp/test.txt "echo hello"` works
4. Smoke test: `claude -p --model haiku "echo hello"` works
