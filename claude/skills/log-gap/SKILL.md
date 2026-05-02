---
name: log-gap
description: Log a one-line knowledge gap to the project's gaps.md file. Use when the user is surprised by Claude's answer, says "I didn't know that", "wait what", or wants to record a misconception they just discovered. Format "I assumed X but actually Y". Personal misconception log — much higher learning signal than feedback memories.
---

# Log a knowledge gap

Captures the gap *between what you assumed and what's actually true*. This is the highest-signal learning artifact — feedback memories capture Claude's mistakes; gaps capture yours.

## Instructions

1. **Locate or create `gaps.md` in the project root.**
   ```bash
   GAPS_FILE="$(git rev-parse --show-toplevel)/gaps.md"
   [ -f "$GAPS_FILE" ] || printf '%s\n\n' "# Knowledge Gaps" "Personal misconception log. One line per gap. Format: 'I assumed X but actually Y'." > "$GAPS_FILE"
   ```

2. **Append the gap with date prefix.**
   ```bash
   printf -- '- %s — %s\n' "$(date -u +%Y-%m-%d)" "<the gap text>" >> "$GAPS_FILE"
   ```

3. **Format guidance:**
   - One line. Keep it terse.
   - Format: `I assumed <X> but actually <Y>` — both halves are required.
   - If the gap doesn't fit that frame, you don't have a gap yet — you have an observation. Don't log observations.
   - Bad: `learned about Arc vs Rc` (no contrast)
   - Good: `I assumed Rc::clone allocated, but actually it just bumps the refcount`

4. **Don't auto-fill.** The user must articulate both sides. If they only say "I learned X", reflect: "what did you assume before?" — and only log once they've answered.

5. **Confirm with absolute path of the line added.**

## When to invoke

- User says "I didn't realize", "wait what", "I assumed", "I thought X did Y" right before/after Claude clarifies
- User explicitly asks to log a gap
- Don't proactively interrupt if user is in flow — wait for a natural pause or explicit invocation

## Notes

- Gaps live **per-project** in repo root, not in global memory dirs. Project-specific misconceptions are the most valuable to revisit when you return to that codebase.
- Add `gaps.md` to `.gitignore` if you don't want it committed. Most users will commit — surfacing past gaps in `git log` is itself useful.
- Pair with `/recall-feedback`-style review monthly: read the file, ask "still relevant? graduated?".
