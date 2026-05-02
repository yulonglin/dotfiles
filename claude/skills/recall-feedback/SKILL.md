---
name: recall-feedback
description: Resurface a random sample of feedback memories for spaced-repetition review — "still true? changed? promote to global rule?". Use when user asks for feedback retrospective, weekly memory review, or to audit accumulated coaching corrections. Also good for periodic via /schedule.
---

# Recall feedback memories

Spaced-repetition retrospective on accumulated feedback memories. Lessons that don't get resurfaced don't compound.

## Instructions

1. **Find feedback files.** Memories live in per-project memory dirs. Scan all of them:
   ```bash
   rg --files -g 'feedback_*.md' /Users/yulong/.claude/projects/*/memory/ 2>/dev/null
   ```

2. **Sample N at random.** Default to 3-5 (don't overwhelm). Use `shuf` if available, else `sort -R`:
   ```bash
   rg --files -g 'feedback_*.md' /Users/yulong/.claude/projects/*/memory/ 2>/dev/null \
     | shuf -n 5
   ```

3. **Read each sampled file.** Extract the rule and the **Why:** line.

4. **Present each as a triage prompt.** Format per item:
   ```
   ### <feedback name>
   <one-line rule>
   _Why:_ <reason from memory>
   _Path:_ <abs path>

   - [ ] **Still true?** (yes / no / partially — explain)
   - [ ] **Changed since?** (new context, exception, refinement?)
   - [ ] **Promote?** (project-local → global CLAUDE.md / rules/*.md / skill)
   - [ ] **Retire?** (rule has been internalised — graduation)
   ```

5. **Wait for user response.** Don't auto-edit. The user makes the call per item.

6. **Apply user's decisions.**
   - "Still true, no change" → no-op
   - "Promote" → suggest the destination, ask for confirmation, then move/edit
   - "Retire / graduated" → delete the memory file (and its line in MEMORY.md)
   - "Refine" → edit the memory file with the new context

## Bonus: commit explain-back (optional, +1 retrieval rep)

After the feedback triage, sample one recent commit and ask the user to explain it back. This is a low-cost, high-yield retrieval rep — if they can't articulate why the change exists, the lesson didn't stick.

```bash
# Pick a commit from the last ~14 days, biased toward non-trivial diffs
git log --since="14 days ago" --pretty=format:'%h %s' --no-merges \
  | shuf -n 1
```

Format the prompt:

```
### Explain-back: <hash> <subject>
_Diff:_ `git show --stat <hash>` ([N] files changed)

In one or two sentences:
1. **Why** does this change exist? (what problem / opportunity)
2. **What** would you do differently if you wrote it today?
```

If they stall or it's clearly stale ("no idea, that was a parallel session"), that *is* the finding — note it and move on. Don't push.

Skip this step if:
- No commits in the window
- The user explicitly said "just feedback today"
- Already done in the last 7 days (avoid review fatigue)

## When to invoke

- Explicit: user says "review my feedback" / "weekly retrospective" / "audit memories"
- Scheduled: via `/schedule` weekly or fortnightly cron
- Symptom: user mentions re-discovering a pattern they swore they'd remember

## Notes

- Don't sample more than 5 per session — review fatigue defeats the purpose.
- This is **active** retrieval — the user must articulate "still true?". Don't pre-answer for them.
- Promotion direction is one-way: memory → rule → skill, not the other direction.
- If a memory file has no `**Why:**` line, that itself is a finding — flag it, since memories without reasons rot fastest.
