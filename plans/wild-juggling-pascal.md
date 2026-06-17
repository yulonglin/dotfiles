# Plan: Three-Phase Codex Workflow (Critique → Implement → Review)

## Context

Codex CLI is underutilized — the existing `codex` agent handles implementation but there's no systematic use for **plan critique**, **code review**, or **debugging**. The user wants a three-phase workflow where separate Codex invocations handle each phase, leveraging Codex's reasoning models (o-series) for concrete gap detection that complements Claude's taste/judgment. Codex is also recognized as having strong general engineering capabilities — including debugging — beyond just spec-following implementation.

**Goal**: Add two new agents (`plan-critic`, `codex-reviewer`), enhance the existing `codex` agent, update `debugger` cross-references, and update delegation rules.

**Architecture**: Slim agent files (~30-50 lines) + detailed reference files loaded on demand. Follows the existing pattern at `skills/codex-cli/references/model-selection.md`.

---

## Changes

### 1. CREATE: `agents/plan-critic.md` (slim)

**File**: `claude/local-marketplace/plugins/code-toolkit/agents/plan-critic.md`

~40 lines. Frontmatter + core identity + "read reference for details" pointer.

```yaml
name: plan-critic
description: >
  MUST BE USED before implementing any plan involving architectural decisions,
  migrations, concurrency, auth changes, or schema modifications. Delegates to
  Codex CLI with xhigh reasoning to find concrete implementation gaps: missing
  error paths, race conditions, sequencing issues, implicit assumptions, and
  simpler alternatives. Complements claude agent (taste/architecture) with
  staff-engineer-level concrete critique.
model: inherit
color: orange
tools: ["Bash"]
```

Body covers:
- One-paragraph purpose (staff engineer who asks "will this actually work when you code it?")
- Core workflow: read plan → read key files → delegate to `codex exec --full-auto -c model_reasoning_effort="xhigh"` → present CRITICAL/IMPORTANT/SUGGESTION output
- Safety note: prompt instructs "Analyze only. Do not create, modify, or delete any files."
- Pointer: `For detailed critique checklist and prompt template, read references/plan-critique-guide.md`
- Conflict resolution: block on CRITICAL from either reviewer; present IMPORTANT disagreements to user; let implementer decide SUGGESTIONS

### 2. CREATE: `agents/references/plan-critique-guide.md`

**File**: `claude/local-marketplace/plugins/code-toolkit/agents/references/plan-critique-guide.md`

~100 lines. Detailed operational content the `plan-critic` agent loads when invoked:

- **Critique checklist** (7 items): completeness, sequencing, error paths, edge cases, implicit assumptions, simpler alternatives, verification gaps
- **Codex prompt template**: `[PLAN] + [SOURCE FILES] + [CHECKLIST] + [OUTPUT FORMAT]`
- **Execution patterns**: sync command, output file naming, session naming (`codex-plan-critique-<MMDD>-<HHMM>`)
- **Example**: concrete plan + expected critique output
- **Differentiation table**: plan-critic (Codex) vs claude agent

### 3. CREATE: `agents/codex-reviewer.md` (slim)

**File**: `claude/local-marketplace/plugins/code-toolkit/agents/codex-reviewer.md`

~40 lines. Frontmatter + core identity + reference pointer.

```yaml
name: codex-reviewer
description: >
  Use alongside code-reviewer for a second-model opinion on code changes.
  Delegates to Codex CLI for diff analysis. Excels at concrete bugs:
  off-by-one errors, race conditions, missing null checks, incorrect error
  propagation, type mismatches, and logic errors. Invoke after significant
  implementation (multi-file changes, auth, concurrency, data mutations)
  alongside the existing code-reviewer.
model: inherit
color: green
tools: ["Bash"]
```

Body covers:
- One-paragraph purpose (bug-focused reviewer, different model = different blind spots)
- Core workflow: determine review scope → `cd <repo> && codex exec review --base main -o <output>` → present BUG/RISK/NITS findings
- Scope note: use `--base main` over `--uncommitted` to avoid untracked file noise
- Pointer: `For detailed review guide and focus areas, read references/codex-review-guide.md`
- Severity mapping: BUG≈CRITICAL, RISK≈IMPORTANT, NITS≈SUGGESTION

### 4. CREATE: `agents/references/codex-review-guide.md`

**File**: `claude/local-marketplace/plugins/code-toolkit/agents/references/codex-review-guide.md`

~80 lines. Detailed operational content the `codex-reviewer` agent loads when invoked:

- **Review modes**: `--uncommitted`, `--base <branch>`, `--commit <SHA>` — when to use each
- **Focus areas** (6 items): logic errors, boundary conditions, error propagation, concurrency, type safety, resource management
- **Non-goals**: explicitly NOT style, naming, design patterns, CLAUDE.md compliance
- **Custom review instructions template**: how to pass focus areas to Codex
- **Execution patterns**: sync vs async (tmux for >500-line diffs), session naming
- **Differentiation table**: codex-reviewer (Codex) vs code-reviewer (Claude)
- **Parallel execution note**: no contention (different tools), review same git state

### 5. ENHANCE: `agents/codex.md`

**File**: `claude/local-marketplace/plugins/code-toolkit/agents/codex.md`

**Changes**:

a) **Update description** to add plan-driven implementation and debugging:
```yaml
description: >
  Delegate well-scoped tasks to Codex CLI. Use for: defined functions, bug fixes,
  scoped refactoring, boilerplate generation, plan-driven implementation (executing
  approved plans step-by-step), and debugging concrete bugs with clear reproduction
  steps. Codex reasoning models excel at tracing execution paths.
```

b) **Update suitability table**: Remove "debugging" from "Not for Codex" column. Add:
```
| Debugging with clear repro steps | Vague "something feels wrong" |
```

c) **Add Plan-Driven Implementation section** (after Step 3). Keep it brief (~20 lines) with pointer:
- Plan-aware prompt template with `[PLAN CONTEXT]` block
- Pointer: `For chunking strategy and full template, read references/plan-implementation.md`

d) **Remove "Second Opinion on Plans" section** (lines 191-202) — moves to `plan-critic`

e) **Update complementary agents table** to add `plan-critic`, `codex-reviewer`, `debugger`

### 6. CREATE: `agents/references/plan-implementation.md`

**File**: `claude/local-marketplace/plugins/code-toolkit/agents/references/plan-implementation.md`

~50 lines. Loaded by `codex` agent when doing plan-driven implementation:

- **Plan-aware prompt template**: full `[DELEGATION HEADER] + [PLAN CONTEXT] + [TASK] + [CONSTRAINTS] + [VERIFICATION]`
- **Chunking strategy**: 1-3 steps → single invocation, 4-7 → 2-3 chunks, 8+ → per-step
- **Commit pattern**: commit after each verified chunk
- **Example**: concrete plan step + delegation prompt

### 7. UPDATE: `agents/debugger.md` — add Codex cross-reference

**File**: `claude/local-marketplace/plugins/code-toolkit/agents/debugger.md`

Append ~8 lines:
```markdown
# COMPLEMENTARY DEBUGGING

For bugs with clear reproduction steps and concrete error output, consider
also delegating to the `codex` agent. Codex reasoning models excel at tracing
execution paths and finding off-by-one errors, race conditions, and logic bugs
when given stack traces and minimal repro code. Use `debugger` (Claude) for
systematic investigation; use `codex` for focused execution-path analysis.
```

### 8. UPDATE: `agents/code-reviewer.md` — cross-reference

**File**: `claude/local-marketplace/plugins/code-toolkit/agents/code-reviewer.md`

Append ~6 lines:
```markdown
# COMPLEMENTARY REVIEW

For significant changes (multi-file, auth, concurrency, data mutations), run
`codex-reviewer` in parallel. It uses Codex reasoning models to find concrete
bugs (off-by-one, race conditions, logic errors) that complement the
design/quality/CLAUDE.md focus of this reviewer.
```

### 9. UPDATE: `agents/claude.md` — complementary agents

**File**: `claude/local-marketplace/plugins/code-toolkit/agents/claude.md`

- Update complementary agents table: add `plan-critic` and `codex-reviewer`
- In "SECOND OPINION ON PLANS", add: "For concrete implementation gaps, also run `plan-critic` in parallel"
- Update pattern: "Claude reviews approach → plan-critic catches gaps → Codex implements → code-reviewer + codex-reviewer review"

### 10. UPDATE: `rules/agents-and-delegation.md`

**File**: `claude/rules/agents-and-delegation.md`

Add to proactive trigger table:
```
| `plan-critic` | Before implementing plans with arch decisions, migrations, auth, concurrency |
| `codex-reviewer` | After significant implementation, alongside code-reviewer |
```

Update delegation decision tree:
```
Need delegation?
├─ Large context (PDF, codebase)? → gemini-cli
├─ Plan needs critique? → code-toolkit:plan-critic (+ code-toolkit:claude in parallel)
├─ Clear implementation spec/plan? → code-toolkit:codex
├─ Bug with clear repro? → code-toolkit:codex (+ debugger for investigation)
├─ Need judgment/taste? → code-toolkit:claude
├─ Code review needed? → code-toolkit:code-reviewer (+ code-toolkit:codex-reviewer for significant changes)
└─ Multi-step workflow? → Use skills
```

### 11. UPDATE: `skills/codex-cli/SKILL.md` — align with new workflow

**File**: `claude/local-marketplace/plugins/code-toolkit/skills/codex-cli/SKILL.md`

- Reference `plan-critic` agent for plan critique (instead of inline plan review)
- Add debugging to "When to Use" table
- Add plan-driven implementation to examples
- Remove "Not for Codex: debugging" restriction

---

## Files Summary

| File | Action | Est. lines |
|------|--------|-----------|
| `agents/plan-critic.md` | **CREATE** (slim) | ~40 |
| `agents/references/plan-critique-guide.md` | **CREATE** (reference) | ~100 |
| `agents/codex-reviewer.md` | **CREATE** (slim) | ~40 |
| `agents/references/codex-review-guide.md` | **CREATE** (reference) | ~80 |
| `agents/references/plan-implementation.md` | **CREATE** (reference) | ~50 |
| `agents/codex.md` | EDIT | ~25 added, ~15 removed |
| `agents/debugger.md` | EDIT (append cross-ref) | ~8 |
| `agents/code-reviewer.md` | EDIT (append cross-ref) | ~6 |
| `agents/claude.md` | EDIT (update tables) | ~12 |
| `rules/agents-and-delegation.md` | EDIT (add triggers, update tree) | ~15 |
| `skills/codex-cli/SKILL.md` | EDIT (align workflow) | ~15 |

All agent/skill paths relative to `claude/local-marketplace/plugins/code-toolkit/`. Rules path relative to `claude/`.

---

## Verification

1. **Structural**: Restart Claude Code, verify `code-toolkit:plan-critic` and `code-toolkit:codex-reviewer` appear in agent picker
2. **plan-critic**: Write a test plan, invoke agent, confirm it reads reference file, delegates to Codex, returns tiered critique without modifying files
3. **codex-reviewer**: Make a multi-file change, invoke agent, confirm it reads reference, runs `codex exec review --base main`, returns bug-focused findings
4. **codex (enhanced)**: Pass a plan file, confirm plan-aware prompt template is used and reference is loaded
5. **Debugging path**: Invoke codex agent with bug + repro steps, confirm accepted (no longer rejected)
6. **Cross-references**: All complementary agent tables updated in codex.md, claude.md, code-reviewer.md, debugger.md
7. **No duplicate authority**: codex.md no longer has "Second Opinion on Plans" section
8. **Skills alignment**: codex-cli/SKILL.md references plan-critic and includes debugging
