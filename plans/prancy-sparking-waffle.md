# Plan: Claude Code Memory + Research State Strategy

## Context

Researched 5 approaches to persistent memory/task management for Claude Code. Got 9 independent agent reviews across 3 rounds. All converge on the same recommendations.

**Two problems identified:**
1. **Session memory** — Claude forgets small discoveries between sessions
2. **Research state** — Methodology, hyperparameters, experiment status scattered across code/configs/specs, going stale at different rates

---

## Decision 1: Session Memory — Learnings in CLAUDE.md (DONE)

Add `## Learnings` section to per-project CLAUDE.md for small discoveries.

**Status**: Already implemented.

---

## Decision 2: Research State — Markdown with YAML Frontmatter

**Format**: `research_state.md` — YAML frontmatter for structured data, markdown body for prose decisions.

**Why this format** (unanimous across 3 blind evaluators, 22/25 score):
- Frontmatter edits are pure YAML → Claude's Edit tool handles reliably
- Prose in markdown body → natural to read and write
- Single file → no sync drift (fatal flaw of two-file approach)
- GitHub renders frontmatter as table + body as markdown → best display

### Template: `claude/templates/research_state.md`

```markdown
---
# research_state.md — Source of truth for experiment methodology and status
# Claude Code: read at session start. Update when state changes.
# Authority: this file > config files > CLAUDE.md > code defaults

methodology:
  seeds: 5
  ci_method: bootstrap
  ci_level: 0.95
  min_samples: 100
  metrics: [accuracy, f1]
  plotting_style: anthropic
  notes: ""

experiments: {}
  # template:
  #   experiment_name:
  #     status: planned  # planned | running | done | failed | blocked
  #     config: configs/experiment.yaml
  #     result: ""
  #     notes: ""
---

## Decisions

<!-- Log methodology changes with date and rationale. Most recent first. -->
```

### Global CLAUDE.md instruction (~10 lines)

```markdown
## Research State (Per-Project)

Research projects should have a `research_state.md` at repo root.
Read it at session start — it is AUTHORITATIVE over config files and code defaults.
Update it when experiments complete or methodology decisions change.

Authority hierarchy for research projects:
research_state.md > Hydra config files > CLAUDE.md > code defaults

If sources conflict, flag the inconsistency to the user.
```

### Files to modify

1. **`claude/CLAUDE.md`** — Add ~10 lines: research state convention + authority hierarchy
2. **`claude/templates/research_state.md`** — Create template (~25 lines)

---

## Decision 3: Beads — Not Now

Deferred. Revisit when coordinating multiple researchers or if research_state.md proves insufficient.

## Decision 4: Context Optimization — Separate Effort

The `abstract-cuddling-cat.md` plan (modular CLAUDE.md) frees ~14.5k tokens. Execute separately.

---

## Summary

| Problem | Solution | Status |
|---------|----------|--------|
| Session memory | `## Learnings` in project CLAUDE.md | Done |
| Research state | `research_state.md` (frontmatter + markdown) | This plan |
| Task management | Existing `.claude/tasks/` | No change |
| Context budget | `abstract-cuddling-cat.md` | Future |
| Claude-mem | Dropped | Decided |
| Beads | Deferred | Decided |

---

## Verification

1. Template exists at `claude/templates/research_state.md`
2. Global CLAUDE.md has research state instructions
3. In a research project: create `research_state.md` from template, start new session, verify Claude reads it
4. Run experiment → verify Claude updates the frontmatter status + adds decision entry
