# Plan: Three-Phase Codex Workflow (Critique → Implement → Review)

## Context

Codex CLI is currently underutilized — the existing `codex` agent handles implementation but there's no systematic use for **plan critique** or **code review**. The user wants a three-phase workflow where separate Codex invocations handle each phase, leveraging Codex's reasoning models (o-series) for concrete gap detection that complements Claude's taste/judgment.

**Goal**: Add two new agents (`plan-critic`, `codex-reviewer`) and enhance the existing `codex` agent, then update delegation rules to promote the three-phase pattern.

---

## Changes

### 1. NEW: `plan-critic.md` agent

**File**: `claude/local-marketplace/plugins/code-toolkit/agents/plan-critic.md`

**Role**: Staff engineer who critiques plans before implementation. Delegates to Codex CLI with `xhigh` reasoning.

**Frontmatter**:
```yaml
name: plan-critic
description: >
  MUST BE USED before implementing any plan with 3+ files or architectural decisions.
  Delegates to Codex CLI with xhigh reasoning to find concrete implementation gaps:
  missing error paths, race conditions, sequencing issues, implicit assumptions,
  and simpler alternatives. Complements claude agent (taste/architecture) with
  concrete staff-engineer-level critique.
model: inherit
color: orange
tools: ["Bash"]
```

**Key system prompt sections**:
- **Critique checklist**: Completeness (all files listed?), sequencing (can steps execute in order?), error paths (what if X fails?), edge cases (empty/nil/concurrent), implicit assumptions, simpler alternatives, verification gaps
- **Prompt template**: Passes plan content + key source files to Codex, asks for CRITICAL/IMPORTANT/SUGGESTION tiered output
- **Execution**: Always sync (plans are small), always `xhigh` reasoning, `-p plan` profile (read-only sandbox)
- **Session naming**: `codex-plan-critique-<MMDD>-<HHMM>`

**Differentiation from `claude` agent's plan review**:
| `plan-critic` (Codex) | `claude` agent |
|------------------------|----------------|
| Concrete gaps: error paths, race conditions, off-by-one | Taste: naming, abstractions, architecture |
| "Will this work when you code it?" | "Is this the right approach?" |
| Execution path tracing | Design pattern evaluation |

**Recommended pattern**: Run both in parallel for maximum coverage.

---

### 2. ENHANCE: `codex.md` agent

**File**: `claude/local-marketplace/plugins/code-toolkit/agents/codex.md`

**What changes**:
- Update description to mention plan-driven implementation
- Add a **Plan-Driven Implementation** section after Step 3 (construct prompt)
- Add plan-aware prompt template with `[PLAN CONTEXT]` section
- Add plan chunking strategy (1-3 steps → single invocation, 4-7 → 2-3 chunks, 8+ → per-step)
- Update complementary agents table to reference `plan-critic` and `codex-reviewer`

**What stays the same**: All existing content (CLI syntax, workflow steps, best practices, limitations, error handling). Additions only, no removals.

**Updated description**:
```yaml
description: >
  Delegate well-scoped implementation tasks to Codex CLI. Use for: defined functions,
  bug fixes with known cause, scoped refactoring, boilerplate generation, and
  plan-driven implementation (executing approved plans step-by-step).
```

---

### 3. NEW: `codex-reviewer.md` agent

**File**: `claude/local-marketplace/plugins/code-toolkit/agents/codex-reviewer.md`

**Role**: Bug-focused code reviewer using `codex exec review`. Runs alongside existing Claude-based `code-reviewer`.

**Frontmatter**:
```yaml
name: codex-reviewer
description: >
  Use alongside code-reviewer for a second-model opinion on code changes.
  Delegates to Codex CLI's built-in review command. Excels at concrete bugs:
  off-by-one errors, race conditions, missing null checks, incorrect error
  propagation, type mismatches, and logic errors in diffs. Invoke after
  implementation alongside the existing code-reviewer for maximum coverage.
model: inherit
color: green
tools: ["Bash"]
```

**Key system prompt sections**:
- **Review modes**: `codex exec review --uncommitted`, `--base <branch>`, `--commit <SHA>`
- **Focus**: Concrete bugs only (logic errors, boundary conditions, error propagation, concurrency, type safety, resource management). Explicitly NOT style, naming, or design patterns (that's `code-reviewer`'s job)
- **Reasoning effort**: Always `xhigh`
- **Output format**: File:Line with severity (BUG/RISK/NITS) and concrete fix suggestions
- **Session naming**: `codex-review-<MMDD>-<HHMM>`

**Differentiation from `code-reviewer` (Claude)**:
| `codex-reviewer` (Codex) | `code-reviewer` (Claude) |
|--------------------------|--------------------------|
| "Is this correct code?" (bugs, logic) | "Is this good code?" (quality, patterns) |
| Diff-scoped, execution path tracing | Full codebase awareness via tools |
| BUG/RISK/NITS severity | CRITICAL/IMPORTANT/SUGGESTION |
| 30-90 seconds via built-in review | Slower, more thorough exploration |

**Parallel execution**: No contention — `code-reviewer` uses Read/Glob/Grep, `codex-reviewer` uses Bash.

---

### 4. UPDATE: `agents-and-delegation.md`

**File**: `claude/rules/agents-and-delegation.md`

Add `plan-critic` and `codex-reviewer` to the proactive trigger table:

```
| `plan-critic` | Before implementing any plan with 3+ files |
| `codex-reviewer` | After implementation, alongside code-reviewer |
```

Update the delegation decision tree:

```
Need delegation?
├─ Large context (PDF, codebase)? → gemini-cli
├─ Plan needs critique? → code-toolkit:plan-critic (+ code-toolkit:claude in parallel)
├─ Clear implementation spec? → code-toolkit:codex
├─ Need judgment/taste? → code-toolkit:claude
├─ Code review needed? → code-toolkit:code-reviewer + code-toolkit:codex-reviewer
└─ Multi-step workflow? → Use skills
```

---

### 5. UPDATE: `code-reviewer.md` — minor cross-reference

**File**: `claude/local-marketplace/plugins/code-toolkit/agents/code-reviewer.md`

Add a note at the end recommending parallel invocation with `codex-reviewer`:

```
# COMPLEMENTARY REVIEW

For maximum coverage, run `codex-reviewer` in parallel. It uses Codex's reasoning
models to find concrete bugs (off-by-one, race conditions, logic errors) that
complement the design/quality focus of this reviewer.
```

---

### 6. UPDATE: `claude.md` — complementary agents table

**File**: `claude/local-marketplace/plugins/code-toolkit/agents/claude.md`

Update the complementary agents table and patterns section to include `plan-critic` and `codex-reviewer`.

---

## Files Summary

| File | Action | Lines changed (est.) |
|------|--------|---------------------|
| `agents/plan-critic.md` | **CREATE** | ~150 |
| `agents/codex.md` | EDIT (add sections) | ~60 added |
| `agents/codex-reviewer.md` | **CREATE** | ~140 |
| `rules/agents-and-delegation.md` | EDIT (add to tables) | ~15 |
| `agents/code-reviewer.md` | EDIT (add cross-ref) | ~8 |
| `agents/claude.md` | EDIT (update tables) | ~10 |

All paths relative to `claude/local-marketplace/plugins/code-toolkit/` except the rules file which is at `claude/rules/`.

---

## Verification

1. **Structural**: Confirm all 3 agents appear in Claude Code's slash command picker (restart session, check `/` menu for `code-toolkit:plan-critic`, `code-toolkit:codex-reviewer`)
2. **Functional - plan-critic**: Write a small plan, invoke `plan-critic` agent, confirm it delegates to Codex and returns tiered critique
3. **Functional - codex-reviewer**: Make a code change, invoke `codex-reviewer`, confirm it runs `codex exec review --uncommitted` and returns bug-focused findings
4. **Functional - codex (enhanced)**: Test plan-driven implementation by passing a plan file to the codex agent
5. **Cross-references**: Verify updated complementary agents tables in `codex.md`, `claude.md`, `code-reviewer.md` all reference the new agents
6. **Delegation rules**: Read `agents-and-delegation.md` and confirm the decision tree includes the new agents
