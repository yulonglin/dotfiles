# Research Memory System — Plan

*Created: 17-02-2026 | Updated with findings from official docs + community research*

## Context

**Problem**: New coding sessions lose volatile research context — which experiments ran recently, what failed, which hyperparameters are validated. Stable knowledge is well-encoded in CLAUDE.md + docs/, but experiment-level results are scattered across `out/*.md` files with no single entry point.

**Key discovery from official Claude Code docs**: Claude Code *already has* a built-in auto memory system at `~/.claude/projects/<project>/memory/MEMORY.md`. The first 200 lines are automatically loaded into every session. This project's auto memory (`~/.claude/projects/-home-yulong-code-sandbagging-detection-dev/memory/MEMORY.md`) is currently **empty** — that's the primary gap to fill, not a missing hook or external tool.

**Key discovery for worktrees**: Git worktrees get **separate** auto memory directories (by design — each worktree's learnings stay isolated). For cross-worktree context sharing, files inside the git repo are the right mechanism.

**What the community does (from research)**:
- Structured artifacts (task lists, progress files, experiment logs) survive context compaction better than freeform conversation history
- "claude-progress.txt" or NOTES.md patterns for multi-session continuity
- Git commits as experiment metadata (the `logis` pattern — hyperparams in commit messages)
- CLAUDE.md is infrastructure: treat it like production prompts, iterate on it
- Context sharing across worktrees is an **unsolved problem** in the ecosystem — worktrees are good for isolation, not for shared memory
- The simplest working approach: a curated file in the repo + instructions to update it = 80% of the value

**NOTES.md origin**: Specified in your own `~/.claude/CLAUDE.md` at line 679: *"Notes: `NOTES.md` (single file, chronological) | Paper content: `paper/`"*

---

## Architecture

Two built-in layers + one addition:

```
~/.claude/projects/.../memory/MEMORY.md   ← BUILT-IN: auto memory (stable patterns, per-worktree)
                                           Already loaded at every session start (first 200 lines)
                                           Currently EMPTY — needs populating

dev/NOTES.md                              ← NEW: experiment log (volatile results, repo-tracked)
                                           Shared across all worktrees via git
                                           Needs a mechanism to inject recent entries at session start

dev/CLAUDE.md                             ← EDIT: add instructions to maintain NOTES.md
```

**For worktrees**: NOTES.md is in the repo → all worktrees share it automatically. Auto memory is correctly per-worktree.

---

## What We're Building

### 1. Populate `~/.claude/projects/-home-yulong-code-sandbagging-detection-dev/memory/MEMORY.md`

This is the auto memory entrypoint. Claude reads it at session start automatically. Populate with current project state (stable facts, not experiment results). Claude will update it going forward.

**Content to add**:
- Current research phase: ICML 2026 baseline experiments
- Validated hyperparameters (k=10 primary, reasoning_effort: low for gpt-5-*)
- Key gotchas already learned (Hydra sweep.datasets, batch mode, --multirun)
- Pointer to NOTES.md for experiment results
- Active models: gpt-4.1-nano, gpt-5-nano
- Primary metrics: recall@5%FPR, pAUC<0.05

**Keep under 200 lines** (beyond 200 is not loaded automatically).

### 2. Create `dev/NOTES.md` — Experiment Log

Append-only, experiment-triggered. Seeded with current results from `out/` files.

**Entry format**:
```markdown
## DD-MM-YYYY — [short descriptor]

**Config**: `configs/[name].yaml`
**Dataset / Model**: usaco / 4.1-nano | **Method**: behavioral_probes
**Status**: ✅ Complete | ⚠️ Incomplete (reason) | ❌ Failed (reason) | 🔜 Pending

**Results** (k=10, split mode, test set):
- recall@5%FPR: 0.XX ± 0.XX | pAUC: 0.XX ± 0.XX | AUROC: 0.XX

**Gotchas**:  [anything to avoid repeating]
**Next**: [ ] [concrete action]
```

**Seeding from current result files**:
- `out/GPQA_DETECTION_RESULTS_20260128.md` → GPQA summary
- `out/MATH_RESULTS_20260128.md` + `out/MATH_EXPERIMENTS_STATUS_20260128.md` → MATH summary
- `out/usaco-all-results-split.md` + `out/usaco-results-incomplete.md` → USACO summary
- 3 new untracked configs as 🔜 Pending entries:
  - `usaco-behavioral-probes-4.1nano.yaml` — BP for USACO / 4.1-nano / test set / 5 prompts
  - `usaco-behavioral-probes-5nano.yaml` — BP for USACO / 5-nano / test set / 5 prompts
  - `usaco-ld-5nano-anti-pattern.yaml` — LD for USACO / 5-nano / anti_pattern_solver only / epochs=5

### 3. Inject Recent NOTES.md at Session Start

The problem: NOTES.md grows over time and can't be fully imported. Need to inject only recent entries.

**Mechanism**: SessionStart hook using `tail -120 NOTES.md` (better than full import which grows unbounded).

**Script**: `~/.claude/hooks/session_start_notes.sh`

```bash
#!/usr/bin/env bash
# Injects recent experiment log at session start.
# Only runs if NOTES.md exists in pwd (project-local, doesn't fire in other projects).

PROJECT_NOTES="$(pwd)/NOTES.md"
[ -f "$PROJECT_NOTES" ] || exit 0

RECENT=$(tail -120 "$PROJECT_NOTES")

python3 - <<EOF
import sys, json
content = """=== RECENT EXPERIMENT LOG (last entries from NOTES.md) ===
${RECENT}
=== END LOG ==="""
output = {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": content}}
print(json.dumps(output))
EOF
```

**Wire up in `~/.claude/settings.json`** — add to hooks array:
```json
{
  "matcher": ".*",
  "hooks": [{"type": "command", "command": "~/.claude/hooks/session_start_notes.sh"}],
  "event": "SessionStart"
}
```

### 4. Update `dev/CLAUDE.md` — Add Logbook Section

Insert a brief section (after Critical Warnings):

```markdown
## Experiment Logbook

After every experiment run or important finding, append an entry to `NOTES.md`:
- Date, config, dataset, method, model
- Metrics: recall@5%FPR ± SE, pAUC ± SE, k
- Status (Complete / Incomplete / Failed) and reason
- Gotchas discovered — any implementation detail that could trip up next session
- Concrete next steps as checkboxes

After any mistake discovered (wrong hyperparam, failed sweep, etc.): append a `⚠️ GOTCHA` entry.

See NOTES.md top for format example.
```

---

## Files to Create / Modify

| File | Action | Notes |
|------|--------|-------|
| `~/.claude/projects/.../memory/MEMORY.md` | **Populate** | Stable project facts; auto-loaded at session start |
| `dev/NOTES.md` | **Create** | Seeded from out/ result files; append-only |
| `~/.claude/hooks/session_start_notes.sh` | **Create** | Injects tail of NOTES.md at session start |
| `~/.claude/settings.json` | **Edit** | Register SessionStart hook |
| `dev/CLAUDE.md` | **Edit** | Add Experiment Logbook section |

---

## Worktree Considerations

- **NOTES.md** is in the git repo → all worktrees access it → shared experiment log ✅
- **Auto memory** is per-worktree by design — each worktree's learnings stay isolated (this is correct behavior)
- **SessionStart hook** reads NOTES.md from `$(pwd)` → works correctly in any worktree
- **CLAUDE.md** is shared via git → all worktrees get the logbook instructions ✅
- For personal per-worktree settings: use `dev/CLAUDE.local.md` with `@~/.claude/my-settings.md` import pattern (per official docs recommendation)

---

## Implementation Order

1. Read `out/` result files to synthesize current state
2. Populate `~/.claude/projects/-home-yulong-code-sandbagging-detection-dev/memory/MEMORY.md`
3. Create `dev/NOTES.md` with seeded content + 3 pending experiment entries
4. Create `~/.claude/hooks/session_start_notes.sh`
5. Edit `~/.claude/settings.json` to register hook
6. Edit `dev/CLAUDE.md` to add Experiment Logbook section

---

## Verification

1. Open fresh Claude Code session in `dev/` — Claude should immediately acknowledge recent experiment context from NOTES.md without being prompted
2. Run an experiment → end of session, Claude appends a NOTES.md entry
3. Next session → that entry appears in context automatically

---

## Tool Comparison (Full Landscape)

Based on research across official docs, community, and specific tools mentioned:

| Tool | Overhead | Works w/ Worktrees | Auto-capture | Privacy | Best For |
|------|----------|-------------------|--------------|---------|----------|
| **Built-in auto memory** | Zero | Per-worktree (by design) | Yes (Claude writes) | Local | Stable patterns Claude discovers |
| **NOTES.md + hook** ← recommended | Very low | Yes (via git) | No (Claude appends) | Local | Curated experiment journal |
| **Beads** | Low-med (needs Go) | Yes (SQLite+JSONL in git) | No | Local | Task queues, long-running campaigns |
| **claude-mem** | Med (Bun + ChromaDB worker) | No (per-machine SQLite) | Yes (captures everything) | Local | Zero-discipline auto-capture |
| **SuperMemory** | Low (managed) | N/A (cloud) | Yes | Cloud ❌ | Cross-project knowledge |
| **mem0 / OpenMemory MCP** | Med (MCP server) | Yes (if configured) | Partial | Configurable | Semantic search over past facts |
| **OneContext** | Unknown | Unclear | Unclear | Cloud ❌ | Multi-agent teams |

### Beads — Key Details

[Beads](https://github.com/steveyegge/beads) (by Steve Yegge) is a git-backed issue tracker designed for the "50 First Dates" problem (agents waking up with no memory). It stores issues as JSONL in `.beads/beads.jsonl` (versioned in git) with a local SQLite cache.

**What it is**: A structured task tracker. Epics + tasks with priorities, dependencies, and status. Query: `bd ready` → shows what to work on next. Claude can mark things in-progress and done.

**What it's NOT**: An experiment journal or results log. Good for "what experiments are queued" but not "what were the recall@5%FPR numbers."

**Setup**:
```bash
# Requires Go
git clone https://github.com/sourcegraph/beads.git
go install ./cmd/bd
bd init && bd setup claude
```

**Verdict for this project**: Complementary to NOTES.md, not a replacement. Use Beads for experiment queue management (what's pending/in-progress/done), NOTES.md for results and gotchas.

### Why NOTES.md + hook is recommended over Beads (for now)

1. Zero new dependencies (no Go install required)
2. NOTES.md already specified in your `~/.claude/CLAUDE.md` conventions
3. Free-form text is better for capturing "what went wrong and why" vs structured issues
4. Beads is more useful when you have 20+ queued experiments with dependencies

### Rejected outright

| Tool | Reason |
|------|--------|
| SuperMemory / OneContext | Cloud services, privacy concerns for AI safety research |
| claude-mem | Bun + ChromaDB dependency; captures everything including noise |
| Daily/weekly cadence | Research doesn't fit calendar cycles; experiment-triggered is correct |
| Full NOTES.md import in CLAUDE.local.md | File grows unbounded; tail hook approach is better |
