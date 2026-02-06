# Plan: Custom Insights — Scalable Usage Analytics

## Problem
Built-in `/insights` samples only ~6 recent sessions, over-indexing on atypical work.
User has **956 sessions with content** across 33 projects — need to analyze them all.

## Architecture

**Standalone script** (not a skill — avoids polluting Claude session context):

```
scripts/insights/
├── run_insights.py        # Single entry point: extract → facets → report
└── prompts/
    ├── facet_prompt.txt   # Prompt template for facet generation
    └── report_prompt.txt  # Prompt template for report synthesis
```

Output: `~/.claude/usage-data/` (same location as built-in)

Run from terminal: `python scripts/insights/run_insights.py [--project X] [--since 30] [--force]`

## Data Profile

- **956 sessions** with content (after filtering agent-only, empty)
- **12.4M chars total** (cleaned: stripped progress/hook/file-history noise)
- Median: 5K chars, Mean: 13K, P90: 28K, Max: 434K
- Gemini 1M context → ~700K useful per call → **~18 batches**
- ~30 sec per call → **~9 min end-to-end**

## Pipeline (all in `run_insights.py`)

### Phase 1: Extract & Clean
**Pure Python** — no LLM.

For each session JSONL in `~/.claude/projects/*/`:
1. Strip noise entries: `progress`, `file-history-snapshot`, hook metadata
2. Keep only text content from `user` and `assistant` messages, plus `summary`
3. Package as cleaned transcript with metadata (session_id, project, timestamp)
4. Skip sessions already having facets (caching)

Filters: `--project PATTERN`, `--since DAYS`, `--limit N`, `--force`

### Phase 2: Generate Facets (Gemini CLI)
**Full transcripts to Gemini** — no lossy digest compression.

Batching strategy:
- Sort sessions by size (small first for early results)
- Group into batches targeting **~700K chars** (leaves 300K for prompt + response)
- Small sessions: ~100+ per batch. Large sessions (>50K): fewer per batch
- Very large sessions (>200K): process individually

For each batch:
1. Build prompt: facet_prompt.txt + batch of cleaned transcripts
2. Call `gemini -p "PROMPT" < batch_input.txt`
3. Parse response as JSON array of facets
4. Save each facet to `~/.claude/usage-data/facets/{session_id}.json`

Facet schema (compatible with built-in `/insights`):
```json
{
  "underlying_goal": "string",
  "goal_categories": {"category": count},
  "outcome": "fully_achieved|partially_achieved|unclear",
  "claude_helpfulness": "essential|very_helpful|moderately_helpful",
  "session_type": "single_task|iterative_refinement|quick_question|exploratory",
  "friction_counts": {"type": count},
  "friction_detail": "string",
  "primary_success": "string",
  "brief_summary": "string",
  "session_id": "UUID",
  "project": "string"
}
```

### Phase 3: Generate Report (Gemini CLI)
All facets (~500 x ~500 chars = ~250K) fit in one Gemini call.

1. Python computes aggregate stats (totals, frequencies, per-project breakdowns)
2. Feed stats + all facets to Gemini with report_prompt.txt
3. Gemini outputs HTML report
4. Save to `~/.claude/usage-data/report.html`
5. `open report.html` (macOS) or print path

## Key Design Decisions

1. **Standalone script, not skill**: Avoids polluting Claude session context.
   Can run in a separate terminal while working. Progress via stdout.
2. **Full transcripts to Gemini**: No lossy digest step. Gemini's 1M context
   handles even large sessions. More accurate facets.
3. **Gemini CLI (free)**: No API costs, no litellm, no async complexity.
   Just subprocess calls to `gemini`.
4. **Caching at facet level**: Each `{session_id}.json` is cached on disk.
   Re-runs skip existing facets. `--force` regenerates everything.
5. **Compatible output**: Same schema/location as built-in `/insights`.

## Files to Create

| File | Purpose | LOC est. |
|------|---------|----------|
| `scripts/insights/run_insights.py` | Main script (extract + facets + report) | ~250 |
| `scripts/insights/prompts/facet_prompt.txt` | Facet generation prompt | ~40 |
| `scripts/insights/prompts/report_prompt.txt` | Report synthesis prompt | ~60 |

**~350 lines total.** Single script, two prompt files.

## Human Contribution Opportunity

The **facet prompt** is where domain expertise matters most.
It determines what goal categories, friction types, and success patterns
the system tracks. Should reflect AI safety research workflows,
not generic coding patterns (which is what the built-in `/insights` defaults to).

## Verification

1. `python scripts/insights/run_insights.py --limit 5` → quick test (5 sessions)
2. Check `~/.claude/usage-data/facets/` for generated JSONs
3. `python scripts/insights/run_insights.py --limit 20` → medium test
4. Open `report.html` in browser, verify content makes sense
5. Full run: `python scripts/insights/run_insights.py` (~9 min, all 956 sessions)
6. Re-run → should skip all cached facets, only regenerate report
