# Context Management Rules

**Problem**: Large outputs consume context rapidly and can exhaust the entire conversation.

## Reading Large Files (PDFs, Papers, Long Documents)

⚠️ **ALWAYS use a subagent to read PDFs and large files** ⚠️

PDFs and long documents can consume the ENTIRE context window. Use:
```
Task tool → subagent_type: "general-purpose" or "literature-scout"
```

**Never** read these directly in main context:
- PDF files (research papers, documentation, exported slides)
- Files >500 lines
- Multiple files for comparison/analysis
- Slide decks for review/fixing (use `/fix-slide` which delegates appropriately)

## Efficient Codebase Exploration (CRITICAL FOR SUBAGENTS)

⚠️ **Search first, read targeted sections. NEVER read entire large files.** ⚠️

**The Strategy:**
```
1. Glob → map file patterns (*.py, **/cli/*.py)
2. Grep → find specific content (function names, keywords)
3. Read with limit/offset → only the relevant 50-100 lines
```

**Hard Limits:** (configurable via `CLAUDE_READ_THRESHOLD`, default 500)

| File Size | Action |
|-----------|--------|
| <200 lines | Read directly OK |
| 200-500 lines | Use Grep first, then Read with offset/limit |
| >500 lines | NEVER read without offset/limit |

## Verbose Command Output

**Solutions** (use in order of preference):

| Tool | Use for | Persistence |
|------|---------|-------------|
| **tmux-cli** (PREFERRED) | Experiments, long-running jobs (>5 min) | Survives disconnects |
| `run_in_background: true` | Quick commands (<5 min) you'll check immediately | Lost if session ends |
| Output redirection | One-off verbose commands | Requires manual log management |

**NEVER** run these synchronously in main context:
- Scripts with verbose output, progress bars, or debug logging
- `pytest` with verbose output
- `make`/build commands
- Any Hydra experiment (use Hydra's built-in logging)

For tmux workflow details, see `~/.claude/docs/tmux-reference.md`.

## Bulk Edit Operations (CRITICAL)

⚠️ **NEVER spawn multiple agents to edit the same file concurrently** ⚠️

The Edit tool requires exact `old_string` matches. Concurrent edits cause cascading failures.

| Batch Size | Approach |
|------------|----------|
| 1-15 edits | Single session, sequential (no agents) |
| 15-40 edits | Single session + `/compact` every 15 edits |
| 40+ edits | Sequential sessions, commit between batches |
