---
name: my-insights
description: Run custom usage analytics on all Claude Code sessions
user-invocable: true
disable-model-invocation: true
---

# Custom Usage Insights

Run deep analytics across **all** Claude Code sessions (not just the last 6).

## Usage

```
/my-insights                              # Full run (uses cache, fast on re-runs)
/my-insights --limit 20                   # Test with 20 sessions
/my-insights --project sandbagging        # Filter by project name
/my-insights --since 30                   # Last 30 days only
/my-insights --dry-run                    # Preview batch plan
/my-insights --report-only               # Regenerate report from cached facets
/my-insights --force                      # Ignore cache, reprocess everything
```

## What It Does

1. **Extracts** clean transcripts from all session JSONL files
2. **Analyzes** each session via Gemini (goal categories, outcomes, friction, etc.)
3. **Generates** an HTML report with charts and per-project breakdowns

Facets are cached per-session — re-runs only process new/changed sessions.

## Execution

```bash
python scripts/insights/run_insights.py $ARGUMENTS
```

Report output: `~/.claude/custom-insights/report.html`
