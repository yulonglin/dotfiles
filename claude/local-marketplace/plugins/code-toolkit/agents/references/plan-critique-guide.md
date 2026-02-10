# Plan Critique Guide

Detailed reference for the `plan-critic` agent. Loaded on demand — not always in context.

## Critique Checklist (Expanded)

### 1. Completeness
- Are all files that need modification listed?
- Missing database migrations, config changes, environment variables?
- Are dependency changes (package.json, requirements.txt) accounted for?
- Does the plan cover both happy path and error path changes?

### 2. Sequencing
- Can steps be executed in the listed order without conflicts?
- Are there circular dependencies between steps?
- Do later steps depend on artifacts from earlier steps that might not exist yet?
- Is the deployment order safe (e.g., database before code, or code before database)?

### 3. Error Paths
- What happens if step N fails after step N-1 succeeded?
- Is there rollback logic or is the system left in an inconsistent state?
- Are cleanup operations idempotent (safe to retry)?
- Are error messages actionable for debugging?

### 4. Edge Cases
- Empty inputs, null values, zero-length collections
- Concurrent access (two users hitting the same endpoint)
- Large data volumes (pagination, memory, timeouts)
- Unicode, special characters, locale differences
- Clock skew, timezone issues, DST transitions

### 5. Implicit Assumptions
- What environment state does the plan assume? (services running, files existing, permissions)
- What data state? (tables populated, caches warm, queues drained)
- What version of dependencies? (API compatibility, breaking changes)
- What about the first run vs. subsequent runs? (idempotency)

### 6. Simpler Alternatives
- Could fewer files be changed to achieve the same result?
- Is there an existing library or pattern that handles this?
- Would a different approach avoid the need for migration/rollback logic?
- Is the plan solving a problem that doesn't exist yet? (YAGNI)

### 7. Verification Gaps
- How will you know each step succeeded?
- Are there automated tests for the changed behavior?
- Can the changes be verified without deploying to production?
- Are there observability gaps (missing logs, metrics, alerts)?

## Full Codex Prompt Template

```
You are a staff engineer reviewing an implementation plan. Your job is to find concrete issues that will cause problems during implementation.

IMPORTANT: Analyze ONLY. Do not create, modify, or delete any files.

[PLAN]
{plan_content}

[SOURCE FILES FOR CONTEXT]
{relevant_source_excerpts}

[CRITIQUE CHECKLIST]
For each item, identify specific issues if they exist:

1. COMPLETENESS — Missing files, configs, migrations, dependencies?
2. SEQUENCING — Steps that depend on later steps? Circular dependencies?
3. ERROR PATHS — What breaks if step N fails? Missing rollback/cleanup?
4. EDGE CASES — Empty inputs, concurrency, large data, unicode?
5. IMPLICIT ASSUMPTIONS — Assumed state, environment, data, versions?
6. SIMPLER ALTERNATIVES — Fewer changes, existing patterns, YAGNI?
7. VERIFICATION GAPS — How to confirm each step worked? Missing tests?

[OUTPUT FORMAT]
Group findings by severity:

## CRITICAL (must fix before implementing)
- [Step X / File Y] Issue description. Recommendation.

## IMPORTANT (should address, risk if ignored)
- [Step X / File Y] Issue description. Recommendation.

## SUGGESTION (nice to have)
- [Step X / File Y] Issue description. Recommendation.

If no issues found for a severity level, state "None found."
End with a 1-2 sentence overall assessment.
```

## Execution Patterns

### Sync (most plans)
```bash
OUTPUT="./tmp/codex-plan-critique-$(date -u +%m%d-%H%M).txt"
codex exec --full-auto -c model_reasoning_effort="xhigh" \
  -C <repo-root> -o "$OUTPUT" "<prompt>"
cat "$OUTPUT"
```

### Async (very large plans with many source files)
```bash
TASK_NAME="codex-plan-critique-$(date -u +%m%d-%H%M)"
tmux has-session -t delegates 2>/dev/null || tmux new-session -d -s delegates -n default
tmux new-window -t delegates -n "$TASK_NAME"
tmux-cli send "cd <repo-root> && codex exec --full-auto -c model_reasoning_effort='xhigh' -o ./tmp/${TASK_NAME}.txt '<prompt>' 2>&1 | tee ./tmp/${TASK_NAME}.log" --pane="delegates:${TASK_NAME}.1"
```

## Differentiation: plan-critic vs claude

| Dimension | plan-critic (Codex) | claude agent |
|-----------|-------------------|--------------|
| **Strength** | Concrete gaps: missing error paths, race conditions, off-by-one, sequencing | Architectural taste: naming, abstractions, approach alternatives |
| **Model type** | Reasoning model (o-series) | General model (Claude) |
| **Mode** | Analysis only (read-only) | Can explore with tools |
| **Best at** | "Will this break when coded?" | "Is this the right approach?" |
| **Output** | Tiered findings (CRITICAL/IMPORTANT/SUGGESTION) | Narrative assessment with recommendations |

**Use both for important plans.** They catch different categories of issues.
