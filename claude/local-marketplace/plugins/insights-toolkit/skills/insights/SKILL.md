---
name: insights
description: |
  Generate Claude Code usage insights reports. Analyzes session transcripts,
  extracts structured facets via Gemini CLI, and produces coaching-style HTML reports
  with temporal trends and actionable recommendations.

  Use when:
  - You want to understand your Claude Code usage patterns
  - You want a report filtered to a specific project
  - You want to see how your usage has changed over time
  - You want to list all projects with session counts

  Requires: Python 3.9+, Gemini CLI (`brew install gemini-cli`)
---

# Claude Code Usage Insights

Generate personalized coaching reports from your Claude Code session history.

## Prerequisites

- **Gemini CLI** installed and authenticated (`brew install gemini-cli && gemini`)
- **claude-code-insights** repo cloned at `~/code/claude-code-insights`
  - If not cloned: `git clone https://github.com/yulonglin/claude-code-insights.git ~/code/claude-code-insights`

## Usage

```
/insights                          # Full pipeline: extract new sessions + generate report
/insights --report-only            # Regenerate report from cached facets (fast)
/insights --project dotfiles       # Filter to a specific project
/insights --list-projects          # Show all projects with session counts
/insights --since 7                # Last 7 days only
/insights --dry-run                # Preview what would be processed
```

## Execution

When the user invokes `/insights`, run the appropriate command based on arguments:

### Default (no args or `--report-only`)

```bash
python3 -m claude_insights --report-only
```

This regenerates the report from cached facets. Fast (~30s).

### With arguments

Pass all arguments through to the CLI:

```bash
python3 -m claude_insights <args>
```

The working directory MUST be `~/code/claude-code-insights`.

### Full extraction

If the user explicitly asks to extract/process new sessions (or uses no `--report-only` flag):

```bash
python3 -m claude_insights [--project X] [--since N] [--force] [--verbose]
```

This calls Gemini CLI for each batch of unprocessed sessions. Can take 5-30 minutes depending on session count.

### List projects

```bash
python3 -m claude_insights --list-projects
```

Shows all projects with human-readable names and session counts.

## Output

Reports are saved to `~/.claude/custom-insights/`:

```
~/.claude/custom-insights/
├── facets/                          # Cached per-session facets
├── report_20260206_034800.html      # Timestamped report
├── report_dotfiles_20260206_035200.html  # Project-filtered report
└── report_latest.html → report_...  # Symlink to most recent
```

After generation, open the report in the browser:

```bash
open ~/.claude/custom-insights/report_latest.html
```

## Report Contents

The HTML report has five sections:

1. **How You Use Claude Code** — usage pattern mirror
2. **What Makes Your Usage Distinctive** — non-obvious patterns
3. **Temporal Trends** — weekly session counts and success rates (CSS-only charts)
4. **What's Working Well** — effective patterns to reinforce
5. **What to Change** — friction analysis with specific remedies and CLAUDE.md suggestions

## Tips

- First run requires `--force` to process all sessions (can take 15-30 min with 500+ sessions)
- Subsequent runs only process new/modified sessions (incremental, cached by mtime)
- Use `--project X --report-only` for focused per-project reports
- Use `--since 7 --report-only` for weekly check-ins
- Reports accumulate with timestamps — compare how your patterns evolve
