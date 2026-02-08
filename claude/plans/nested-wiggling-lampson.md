# Plan: Open-Source Claude Code Insights + Repo-Specific Reports

## Context

The Claude Code usage insights pipeline (`scripts/insights/`) is working:
- 528+ sessions analyzed across 23 projects, 480+ facets cached
- Report generates a coaching-style HTML with 4 actionable sections
- Uses Gemini CLI for both facet extraction and report generation

User wants:
1. **Open-source it** as a standalone repo others can use
2. **Repo-specific reports** — filter reports by project
3. **Temporal graphs** — show usage trends over time
4. **Timestamped reports** — dated outputs to track how usage changes over time

## Decisions

- **Keep both copies**: `scripts/insights/` stays in dotfiles (personal), new repo is standalone
- **Full execution**: Create repo, modularize, enhance prompts, push — all in this session
- **3 modules** (not 5): `cli.py`, `sessions.py`, `gemini.py` — less navigation overhead
- **Pre-compute temporal stats** in Python, pass structured data to Gemini (don't ask Gemini to do math)
- **Timestamped report filenames**: `report_YYYYMMDD_HHMMSS.html` with `report_latest.html` symlink

---

## Step 1: Create `~/code/claude-code-insights` repo

### Repo structure

```
claude-code-insights/
├── README.md
├── LICENSE                    # MIT
├── pyproject.toml             # Metadata only, zero pip deps
├── .gitignore
├── claude_insights/
│   ├── __init__.py
│   ├── __main__.py            # Enables `python -m claude_insights`
│   ├── cli.py                 # argparse, main(), open_report()
│   ├── sessions.py            # discover, clean, filter, load_facets, aggregate_stats, temporal_stats
│   ├── gemini.py              # call_gemini, batching, facet parsing, report generation
│   └── prompts/
│       ├── facet_prompt.txt
│       └── report_prompt.txt
└── examples/
    └── sample_report.png      # Screenshot for README
```

**Why 3 modules** (not 5): `sessions.py` is the data layer (load + compute), `gemini.py` is the
LLM layer (call + parse), `cli.py` wires them together. A contributor can understand the architecture
by reading 3 files. `aggregate.py` and `report.py` at 80 lines each would be trivial standalone files.

### Source: lift from `scripts/insights/run_insights.py`

| Module | Functions from run_insights.py |
|--------|-------------------------------|
| `cli.py` | argparse setup, `main()`, `open_report()` |
| `sessions.py` | `discover_sessions()`, `clean_transcript()`, `filter_cached()`, `load_all_facets()`, `compute_aggregate_stats()`, NEW: `compute_temporal_stats()` |
| `gemini.py` | `call_gemini()`, `make_batches()`, `build_batch_prompt()`, `parse_facets_response()`, `process_batch()`, `save_facet()`, `generate_report()` |

### Key changes from current code

1. **Configurable paths**: `--sessions-dir` (default `~/.claude/projects/`), `--output-dir` (default `~/.claude/custom-insights/`)
2. **No hardcoded `/tmp/claude`**: Use `tempfile.gettempdir()` for temp files
3. **Gemini CLI check**: `shutil.which("gemini")` at startup with helpful error message
4. **`__main__.py`**: `from claude_insights.cli import main; main()` — enables `python -m claude_insights` from cloned repo without pip install
5. **`--list-projects`**: Show available project names (human-readable, demangled)

### Dependencies

- **Python 3.9+** (stdlib only — pathlib, json, argparse, tempfile, shutil, datetime)
- **Gemini CLI** (external tool, must be installed separately)
- No pip dependencies

---

## Step 2: Repo-specific report filtering

### Current state
- `discover_sessions(project_filter=...)` already filters during extraction
- `load_all_facets()` does NOT filter — loads everything
- `--report-only --project X` doesn't work

### Changes (~15-20 lines across functions)

1. **`load_all_facets(project_filter=None)`** — add substring filter on `facet["project"]`

2. **Wire to CLI**: Both `--report-only` and normal mode pass `project_filter`

3. **Report prompt awareness**: "If facets are filtered to a single project, tailor the report
   to that project specifically rather than cross-project comparisons."

4. **Output naming**: `report_<project_slug>_<timestamp>.html` when `--project` used,
   `report_<timestamp>.html` otherwise, plus `report_latest.html` symlink

5. **`--list-projects`**: New flag that loads facets, extracts unique projects, prints them
   with human-readable names and session counts:
   ```
   dotfiles                    (180 sessions)
   sandbagging-detection-dev   (87 sessions)
   papers/sandbagging-detection (114 sessions)
   ```

6. **`--since` in `--report-only`**: Filter by `start_timestamp` in loaded facets.
   Print warning if combined: "Filtering cached facets to last N days"

---

## Step 3: Pre-computed temporal stats

### Why pre-compute (not let Gemini do it)

Gemini CSS chart output is inconsistent across runs — it sometimes leaks JavaScript template
literals into "pure HTML/CSS" output, and asking it to both aggregate 500 timestamps AND
design charts in one pass produces errors.

### New function: `compute_temporal_stats(facets)` in `sessions.py`

```python
def compute_temporal_stats(facets):
    """Group facets by week, return structured temporal data."""
    weekly = defaultdict(lambda: {"count": 0, "fully_achieved": 0, "projects": set()})
    for f in facets:
        ts = f.get("start_timestamp")
        if not ts:
            continue
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        week_key = dt.strftime("%Y-W%W")
        weekly[week_key]["count"] += 1
        if f.get("outcome") == "fully_achieved":
            weekly[week_key]["fully_achieved"] += 1
        weekly[week_key]["projects"].add(f.get("project", "unknown"))
    return [{"week": k, "count": v["count"],
             "success_rate": round(v["fully_achieved"] / v["count"] * 100),
             "active_projects": len(v["projects"])}
            for k, v in sorted(weekly.items())]
```

### Inject into report prompt input

Add `## TEMPORAL DATA\n```json\n{temporal_stats}\n```\n` alongside the existing
AGGREGATE STATS and ALL FACETS sections.

### Report prompt additions

```
### Temporal Trends Section
Pre-computed weekly data is provided in TEMPORAL DATA. Use it to generate:
- Weekly session count bar chart (CSS-only, div widths proportional to max count)
- Success rate trend (% fully_achieved per week, shown as colored bars or dots)
- Active projects per week
- If <2 weeks of data, label shows no temporal trends
- Use accent colors consistent with the rest of the report
```

---

## Step 4: CLAUDE.md improvement suggestions in Section 4

### Enhancement to report prompt

Add to Section 4 ("What to Change"):
```
- If patterns suggest workflow improvements, recommend specific CLAUDE.md additions
  - Suggest both global (~/.claude/CLAUDE.md) and per-project (.claude/CLAUDE.md) changes
  - e.g., "You encounter wrong_approach friction in feature_implementation sessions.
    Consider adding: 'Always describe existing architecture before requesting new features.'"
- Base suggestions on friction_detail (available in all facets) and improvement_opportunity
  (available in newer facets only — use when present, don't require it)
```

Note: `improvement_opportunity` field exists in 0 cached facets currently (added to prompt
after initial extraction). Suggestions will use `friction_detail` as primary source.
Running `--force` later will populate `improvement_opportunity` for richer critique.

---

## Step 5: Timestamped reports

### Output naming scheme

```
~/.claude/custom-insights/
├── facets/                        # Individual session facets (unchanged)
├── report_20260206_034800.html    # Timestamped report
├── report_dotfiles_20260206_035200.html  # Project-filtered report
└── report_latest.html → report_20260206_034800.html  # Symlink
```

- Every report run produces a new timestamped file
- `report_latest.html` symlink always points to most recent
- Old reports accumulate — user can see how insights change over time
- `open_report()` opens the symlink (always latest)

---

## Step 6: README.md (written AFTER code is finalized)

Written from actual `--help` output of completed CLI. Includes:
- Prerequisites (Python 3.9+, Gemini CLI)
- Quick start (clone + run)
- Full `--help` dump
- Screenshot of sample report
- "How It Works" section (3-phase pipeline)
- Output file locations

---

## Files to Create/Modify

| File | Action | Size |
|------|--------|------|
| **Dotfiles (quick fix)** | | |
| `scripts/insights/run_insights.py` | Fix `--report-only --project`, add timestamped output | ~20 lines |
| **New repo** | | |
| `claude_insights/__init__.py` | Version string | ~3 lines |
| `claude_insights/__main__.py` | Entry point | ~3 lines |
| `claude_insights/cli.py` | argparse + main() + open_report() | ~100 lines |
| `claude_insights/sessions.py` | Data layer: discover, clean, load, aggregate, temporal | ~250 lines |
| `claude_insights/gemini.py` | LLM layer: call, batch, parse, report gen | ~300 lines |
| `claude_insights/prompts/facet_prompt.txt` | Copy from dotfiles | — |
| `claude_insights/prompts/report_prompt.txt` | Enhanced with temporal + CLAUDE.md sections | ~100 lines |
| `README.md` | Written from actual --help output | ~100 lines |
| `pyproject.toml` | Metadata, no deps | ~25 lines |
| `LICENSE` | MIT | — |
| `.gitignore` | Standard Python | — |

## Implementation Order

### Phase A: Quick fix in dotfiles (sequential)
1. Fix `load_all_facets()` to accept `project_filter`
2. Wire `--project` to `--report-only` mode
3. Add timestamped report output + symlink
4. Commit to dotfiles

### Phase B: Create repo skeleton (sequential)
5. `mkdir -p ~/code/claude-code-insights/claude_insights/prompts`
6. Create `pyproject.toml`, `LICENSE`, `.gitignore`, `__init__.py`, `__main__.py`
7. `git init`

### Phase C: Modularize + content (subagents)
8. **Subagent 1**: Split `run_insights.py` → `cli.py`, `sessions.py`, `gemini.py`
   - Add `compute_temporal_stats()`, Gemini CLI check, `--list-projects`, configurable paths
   - Fix `/tmp/claude` → `tempfile.gettempdir()`
   - Source: read from `scripts/insights/run_insights.py`
9. **Subagent 2**: Enhance prompts + create sample report screenshot
   - Copy facet_prompt.txt, rewrite report_prompt.txt with temporal data + CLAUDE.md suggestions
   - Generate a report and take screenshot for README
10. After subagents: integrate

### Phase D: README + verify + push (sequential)
11. Write README from actual `--help` output
12. Test: `python -m claude_insights --report-only`
13. Test: `python -m claude_insights --project dotfiles --report-only`
14. Test: `python -m claude_insights --list-projects`
15. Verify timestamped output files + symlink
16. Commit, create GitHub repo, push

## Verification

1. `python -m claude_insights --report-only` — full report, check 4 sections + temporal charts
2. `python -m claude_insights --project dotfiles --report-only` — dotfiles-only, check tailored content
3. `python -m claude_insights --list-projects` — shows all projects with counts
4. `ls ~/.claude/custom-insights/report_*.html` — timestamped files accumulate
5. `readlink ~/.claude/custom-insights/report_latest.html` — points to newest
6. Without Gemini CLI: clear error message with install instructions
