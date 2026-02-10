# Codex Review Guide

Detailed reference for the `codex-reviewer` agent. Loaded on demand — not always in context.

## Review Modes

### Branch Diff (default)
```bash
codex exec review --base main -o ./tmp/codex-review.txt
```
Reviews all changes on the current branch vs main. Best for PR-style review of accumulated work.

### Uncommitted Changes
```bash
codex exec review --uncommitted -o ./tmp/codex-review.txt
```
Reviews staged + unstaged changes. Useful for quick pre-commit review. Note: includes untracked files which can be noisy.

### Specific Commit
```bash
codex exec review --commit <SHA> -o ./tmp/codex-review.txt
```
Reviews a single commit. Useful for reviewing someone else's commit or a specific change.

## Focus Areas (Expanded)

### 1. Logic Errors
- Off-by-one in loops, array indexing, string slicing
- Wrong comparison operators (`<` vs `<=`, `==` vs `===`)
- Inverted boolean logic (`if !condition` when `if condition` intended)
- Short-circuit evaluation side effects
- Integer overflow/underflow in arithmetic

### 2. Boundary Conditions
- Empty collections (arrays, maps, strings)
- Null/undefined/None values at function boundaries
- Maximum values (MAX_INT, large strings, deep nesting)
- First/last element handling in iterations
- Zero-division and modulo edge cases

### 3. Error Propagation
- Swallowed exceptions (empty catch blocks)
- Wrong error type thrown (TypeError when ValueError expected)
- Error messages that don't include enough context for debugging
- Missing error handling for async operations (unhandled promise rejections)
- Inconsistent error return patterns (sometimes throws, sometimes returns null)

### 4. Concurrency Issues
- Race conditions between read-check-write operations
- Missing locks or atomic operations for shared state
- Deadlock potential from lock ordering
- Stale data from cached values in concurrent contexts
- Thread safety of data structures

### 5. Type Safety
- Implicit type conversions (string to number, truthy/falsy)
- Generic types losing specificity
- Union types not fully discriminated
- Nullable types not checked before use
- Type assertions that could fail at runtime

### 6. Resource Management
- File handles, database connections, network sockets not closed
- Missing `finally` blocks for cleanup
- Memory leaks from event listeners or subscriptions not removed
- Temporary files not cleaned up on error paths
- Connection pool exhaustion

## Custom Review Instructions

To focus Codex on specific areas, add instructions to the prompt:

```bash
codex exec review --base main -o ./tmp/review.txt \
  --instructions "Focus on: 1) Race conditions in the cache layer 2) Error handling in API routes 3) Null safety in the new parser"
```

## Execution Patterns

### Sync (most reviews, <500 lines changed)
```bash
OUTPUT="./tmp/codex-review-$(date -u +%m%d-%H%M).txt"
cd <repo-root> && codex exec review --base main -o "$OUTPUT"
cat "$OUTPUT"
```

### Async (large reviews, >500 lines changed)
```bash
TASK_NAME="codex-review-$(date -u +%m%d-%H%M)"
tmux has-session -t delegates 2>/dev/null || tmux new-session -d -s delegates -n default
tmux new-window -t delegates -n "$TASK_NAME"
tmux-cli send "cd <repo-root> && codex exec review --base main -o ./tmp/${TASK_NAME}.txt 2>&1 | tee ./tmp/${TASK_NAME}.log" --pane="delegates:${TASK_NAME}.1"
```

## Differentiation: codex-reviewer vs code-reviewer

| Dimension | codex-reviewer (Codex) | code-reviewer (Claude) |
|-----------|----------------------|----------------------|
| **Strength** | Concrete bugs: off-by-one, race conditions, null checks, logic errors | Design quality, CLAUDE.md compliance, research validity |
| **Model type** | Reasoning model (o-series) | General model (Claude) |
| **Focus** | Correctness and safety | Quality and maintainability |
| **Non-goals** | Style, naming, architecture | Implementation-level bugs (covered but not primary) |
| **Output** | BUG / RISK / NITS | CRITICAL / IMPORTANT / SUGGESTION / NITPICK |
| **Tools** | Codex CLI (`codex exec review`) | Read, Glob, Grep (file analysis) |

## Parallel Execution

Both reviewers can run simultaneously without contention:
- `codex-reviewer` uses Codex CLI (separate process, reads git state)
- `code-reviewer` uses Read/Glob/Grep tools (Claude context)
- Both review the same snapshot of code — no race conditions
- Results are complementary: merge findings before presenting to user
