# Experiment Registry Conventions

Convention for tracking research experiments across projects. Markdown-first, git-friendly, agent-readable.

## Directory Structure

```
docs/
├── experiments/                    # Experiment registry
│   ├── _template.md                # Template for new records
│   ├── README.md                   # Auto-generated index
│   └── YYYY-MM-DD_short-name.md   # Individual experiment records
├── journal/                        # Research journal
│   ├── PATTERNS.md                 # Meta-observations (4-week staleness review)
│   ├── DECISIONS.md                # Research decision log (ADR-lite)
│   └── OPEN_QUESTIONS.md          # Unresolved questions
```

## Naming Convention

Experiment records: `YYYY-MM-DD_short-descriptive-name.md`

Examples:
- `2026-01-15_c3_gpqa_icml.md`
- `2026-02-20_honest_wrong_control.md`

## Template Fields

### Required Frontmatter

```yaml
---
title: "[Short Title]"
status: planned  # planned | active | completed | abandoned
started: YYYY-MM-DD
completed: null  # YYYY-MM-DD when done
priority: P0     # P0 | P1 | P2 | P3
dataset: gpqa    # gpqa | math | usaco | (project-specific)
method: c3       # (project-specific method names)
tags: []
---
```

### Required Sections

1. **Hypothesis** — What we expect and why. Include a specific, falsifiable prediction.
2. **Setup** — Config file, models, key params, dataset, research question.
3. **Results** — Table with metrics + CI. Observations tagged as `[result]`, `[finding]`, `[surprise]`.
4. **Interpretation** — Does this support/refute the hypothesis?
5. **Artifacts** — Paths to configs, trajectories, scores, metrics.
6. **Relations** — Links to related experiments and specs.
7. **Log** — Timestamped activity log.

### Optional Section

- **Commands (non-standard)** — Only when commands deviate significantly from documented patterns.

## Workflow

```
User writes spec (specs/)
  → Agent reads spec + creates experiment record (docs/experiments/)
    → Agent runs experiment, fills in results
      → Agent updates record with artifacts and interpretation
```

## Relationship: specs/ vs docs/experiments/

- `specs/` = **intent documents** — human-written specifications (what to do and why)
- `docs/experiments/` = **execution records** — what was run, with what params, what happened
- Experiment records reference their spec: `migrated_from specs/...`
- Both coexist — different roles

## Relation Types

| Type | Meaning |
|------|---------|
| `migrated_from` | Backfilled from an existing spec |
| `discovered_from` | New experiment inspired by results of another |
| `compares_to` | Direct comparison with another experiment |
| `supersedes` | Replaces an older experiment |

## Index Maintenance

Run `python scripts/update_experiment_index.py` to regenerate `docs/experiments/README.md` from frontmatter. Can be run manually or as pre-commit hook.

## Journal Files

- **PATTERNS.md**: Timestamped meta-observations. Review every 4 weeks. Entries graduate when no longer active.
- **DECISIONS.md**: ADR-lite. Date + context + decision + rationale.
- **OPEN_QUESTIONS.md**: Parking lot. Link to experiment records when addressed.

## Keeping The Registry Current Is Manual Now

The three slash commands that used to drive this (`/new-experiment`, `/reflect`, `/audit-docs`) were dropped rather than migrated. The practices they automated still hold, and each is a few minutes by hand:

- **A new record** starts as a copy of `docs/experiments/_template.md`, renamed to `YYYY-MM-DD_short-name.md`, with the frontmatter filled in before the run rather than after it. Writing the prediction down first is what makes it an experiment — see `~/.claude/checklists/experiments.md`.
- **PATTERNS.md** gets reviewed on its four-week cycle: read the records written since the last pass, promote what recurs into a pattern, and retire entries that are no longer active.
- **Stale docs** are found by reading the docs next to the code they describe whenever that code changes, not by a periodic sweep — a sweep finds them long after they have misled someone.
