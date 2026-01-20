# Bulk Edit Skill

Process bulk edits from a comments/feedback file safely using sequential agents.

## Usage

```
/bulk-edit <comments-file> [--target <file>]
```

**Examples:**
```
/bulk-edit specs/comments-18-jan-mary-gdocs.md --target main.tex
/bulk-edit specs/reviewer-feedback.md
```

## How It Works

For each uncompleted thread in the comments file:

1. **Classify complexity** of the edit:
   - **Simple** (haiku): typos, wording tweaks, small clarifications, dropping sentences
   - **Medium** (sonnet): rewriting paragraphs, adding explanations, moving content
   - **Complex** (sonnet/opus): structural changes, narrative flow, multi-part edits

2. **Spawn a fresh agent** with appropriate model:
   - Agent reads ONLY that specific thread
   - Agent applies the edit to target file
   - Agent marks thread as completed with ✅ prefix
   - Agent returns 1-line summary

3. **Agent is discarded** (context freed)

4. **Continue** to next uncompleted thread

## Execution Instructions

When this skill is invoked, follow this workflow:

### Step 1: Parse the comments file

Read the comments file and identify all threads. A thread is completed if it starts with ✅.

```python
# Pseudocode for identifying threads
threads = []
for section in comments_file.split("## Thread"):
    if section.strip():
        thread_num = extract_thread_number(section)
        completed = section.strip().startswith("✅") or "## Thread" line contains "✅"
        threads.append({"num": thread_num, "content": section, "completed": completed})
```

### Step 2: For each uncompleted thread

For each thread where `completed == False`:

**A. Classify complexity:**

| Complexity | Indicators | Model |
|------------|------------|-------|
| Simple | "typo", "nit", "drop this", "clearer:", single word change | haiku |
| Medium | "rewrite", "clarify", "explain", paragraph-level change | sonnet |
| Complex | "restructure", "move to", multiple parts, narrative changes | sonnet |

**B. Spawn agent:**

```
Task tool:
  subagent_type: "general-purpose"
  model: <haiku|sonnet based on complexity>
  prompt: |
    Apply this reviewer comment to {target_file}:

    ---
    {thread_content}
    ---

    Instructions:
    1. Read {target_file}
    2. Find the relevant section (use the quoted/highlighted text as anchor)
    3. Apply the edit as described in the comment
    4. If there's a reply with more context, incorporate that too
    5. After editing, mark this thread in {comments_file} with appropriate status:
       - ✅ = fully addressed
       - ➖ = N/A (comment is praise, informational, or no edit needed)
       - ⏳ = partially addressed (some aspects done, others need more work)
       - ⚠️ = needs manual attention (unclear, conflicting, or requires user decision)
    6. Return a 1-line summary: "Thread {N} [status]: <what you did or why>"

    Examples:
    - "Thread 5 ✅: Changed 'performs worse than random' per suggestion"
    - "Thread 12 ➖: Comment was praise ('I love this!'), no edit needed"
    - "Thread 23 ⏳: Added explanation but TODO for Yulong to verify numbers"
    - "Thread 34 ⚠️: Unclear what 'restructure this' means - needs user input"
```

**C. Wait for agent to complete, then continue to next thread.**

### Step 3: Summary

After all threads processed, report:
```
Processed: 66 threads
  ✅ Addressed: 45
  ➖ N/A: 10
  ⏳ Partial: 5
  ⚠️ Needs attention: 6
```

## Progress Tracking

Progress is tracked IN the comments file itself:

| Marker | Meaning | Action |
|--------|---------|--------|
| `## 📋 Thread 1` | Not started | Will be processed |
| `## ⏳ Thread 1` | Partially addressed | Will be processed (needs more work) |
| `## ✅ Thread 1` | Addressed/completed | Skipped |
| `## ➖ Thread 1` | N/A / not applicable | Skipped (comment doesn't require edit) |
| `## ⚠️ Thread 1` | Needs manual attention | Skipped (agent couldn't resolve) |

**When to use each:**
- **✅ Addressed**: Edit fully applied as requested
- **➖ N/A**: Comment is informational, praise, or already resolved
- **⏳ Partial**: Some aspects addressed, others remain
- **⚠️ Needs attention**: Unclear request, conflicting info, or requires user decision

**Resumable:** Re-run `/bulk-edit` - only 📋 and ⏳ threads are processed.

## Safety Rules

1. **One agent at a time** - never parallel agents on same file
2. **Fresh agent per edit** - prevents context bloat
3. **Mark progress in source** - enables resume
4. **Unclear edits get ⚠️** - don't guess

## Model Selection Guide

| Edit Type | Examples | Model |
|-----------|----------|-------|
| Typo/nit | "typo", "s/foo/bar" | haiku |
| Drop content | "consider dropping", "remove this" | haiku |
| Wording | "clearer:", "maybe rephrase" | haiku |
| Add clarification | "explain why", "add context" | sonnet |
| Rewrite paragraph | "restructure this", "rewrite to..." | sonnet |
| Move content | "move to methods section" | sonnet |
| Structural | "split into subsections", "reorder" | sonnet |
| Narrative | "the flow is off", "argument unclear" | sonnet |
| Multi-part | Thread with multiple sub-comments | sonnet |

## Example Session

```
User: /bulk-edit specs/comments-mary.md --target main.tex

Claude: Processing 66 threads from specs/comments-mary.md → main.tex

Thread 1 (simple): Spawning haiku agent...
  → Thread 1: Fixed typo "sandbaggs" → "sandbags"

Thread 2 (medium): Spawning sonnet agent...
  → Thread 2: Rewrote abstract opening for clarity

Thread 3 (simple): Spawning haiku agent...
  → Thread 3: Dropped redundant sentence in intro

...

Summary:
  ✅ Addressed: 52/66
  ➖ N/A: 8 (praise, informational)
  ⏳ Partial: 3 (threads 23, 41, 55 - need verification)
  ⚠️ Needs attention: 3 (threads 34, 51, 58 - unclear)

Re-run to process ⏳ threads, or address ⚠️ manually.
```

## Notes

- Agents use `model` parameter in Task tool to select haiku vs sonnet
- Each agent gets ~full context window for its single edit
- Orchestrator context grows ~150 tokens per edit (sustainable for 100+ edits)
- Comments file becomes the source of truth for progress
