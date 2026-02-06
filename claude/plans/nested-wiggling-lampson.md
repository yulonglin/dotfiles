# Plan: Actionable Insights — Refocus Report on Feedback

## Context

The insights pipeline is built and running (86 batches, ~60 facets cached so far).
The current report prompt produces a generic analytics dashboard (charts, distributions, tables).
User wants the report restructured around **4 actionable sections**:

1. **What I use Claude Code for** — session type/goal breakdown
2. **What makes my sessions unique** — distinctive patterns, unusual usage
3. **What to do more of** — effective patterns worth reinforcing
4. **What to change** — concrete critique with targeted advice per use-case

This is a **prompt-only change** — no script modifications needed.

## Changes

### 1. `scripts/insights/prompts/facet_prompt.txt` — Add improvement field

**Why**: Current facets have `primary_success` and `friction_detail` but no forward-looking
"what could be better" field. Adding `improvement_opportunity` gives the report prompt
raw material for section 4 (what to change).

**Changes**:
- Add `"improvement_opportunity"` field to schema: "One concrete thing the user or Claude
  could have done differently for a better outcome, or empty string"
- Clean up `TODO(human)` comments (keep the generic categories — they work fine)
- Keep all existing fields intact (backward compatible with already-cached facets)

### 2. `scripts/insights/prompts/report_prompt.txt` — Complete rewrite

Replace the dashboard-style report with an actionable feedback report structured as:

**Section 1: "How You Use Claude Code"** (descriptive)
- Goal category breakdown with context (not just counts — what the patterns mean)
- Session type distribution
- Per-project summary (which projects, what kind of work)
- Time patterns if available

**Section 2: "What Makes Your Usage Distinctive"** (analytical)
- Unusual patterns (e.g., heavy planning vs jumping to implementation)
- Ratio of tooling/meta work vs actual project work
- Session length patterns (many short vs few long)
- Interaction style (single-task vs iterative refinement)
- Helpfulness distribution and what it suggests

**Section 3: "What's Working Well — Do More Of This"** (positive actionable)
- Most successful session types/patterns (high outcome + high helpfulness)
- Effective workflows worth reinforcing
- Projects with best outcomes and what they have in common
- Specific `primary_success` themes grouped by pattern

**Section 4: "What to Change — Concrete Improvements"** (critical actionable)
- Friction analysis organized by use-case (not just global frequency)
- Per-goal-category advice: "When doing X, consider Y"
- Common failure modes with specific remedies
- `improvement_opportunity` themes grouped into actionable recommendations
- Abandoned/unclear sessions — what went wrong and how to prevent it

**Style**: Keep the HTML/CSS quality (dark mode, collapsible sections) but shift
tone from "dashboard for a manager" to "coach feedback for the user".

### 3. `scripts/insights/run_insights.py` — Add new field to report payload

Tiny change: include `improvement_opportunity` in the facet summary sent to the report
generator (line in `generate_report()` where `facet_summaries` are built).

## Files to Modify

| File | Change | Size |
|------|--------|------|
| `scripts/insights/prompts/facet_prompt.txt` | Add field, clean TODOs | ~5 lines |
| `scripts/insights/prompts/report_prompt.txt` | Full rewrite | ~80 lines |
| `scripts/insights/run_insights.py` | Add field to report payload | ~1 line |

## Cache Compatibility

- **Existing facets** (from the running pipeline): Missing `improvement_opportunity` field.
  The report prompt handles this gracefully (field is optional, empty if absent).
- **New/re-run facets**: Will include the new field.
- **No need to `--force` reprocess** — old facets still work, just with less data for section 4.
  Can optionally `--force` later for richer critique after the full run completes.

## Verification

1. Wait for current background run to complete (~60/1008 facets done)
2. Update prompts and script
3. `python3 scripts/insights/run_insights.py --report-only` — regenerate from existing facets
4. Open `report.html` — verify the 4 sections appear with actionable content
5. Check section 4 has concrete per-use-case advice (not just "reduce friction")
6. Optionally: `--force --limit 20` to test new `improvement_opportunity` field
