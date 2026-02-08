# Plan: Split Global CLAUDE.md into Modular Rules + Optimize Context Budget

## Context

The global CLAUDE.md (~1034 lines, 12.6k tokens) has grown into a monolithic file mixing safety rules, Python conventions, tmux workflows, research methodology, and agent strategies. Combined with bloated skills (~9.9k tokens), Serena MCP (~6k tokens), and unused plugins, the total overhead before any conversation is **~48k tokens (24% of context)**.

**Goal**: Reduce always-loaded overhead by ~30%, improve maintainability via modular rules, and reorganize knowledge docs.

**Estimated savings**: ~14-16k tokens (from 48k → 32-34k)

**Critique rounds**: 2 (Plan agent, Claude Code guide, Explore audit). Fixes incorporated below.

---

## Rollback Strategy (CRITICAL — added by critique)

**Before starting ANY changes:**
```bash
cd ~/code/dotfiles
git tag pre-restructure  # Rollback anchor
```

**If rules don't load:** `git checkout pre-restructure -- claude/CLAUDE.md`
**If skills break:** `git checkout pre-restructure -- claude/skills/ claude/settings.json`
**Nuclear rollback:** `git checkout pre-restructure` (entire reset)

**Backwards-compat symlink**: `claude/ai_docs -> claude/docs` kept **permanently** (zero cost, protects other repos that reference `~/.claude/ai_docs/`).

---

## Commit Strategy (added by critique)

| Commit | Steps | What | Why Atomic |
|--------|-------|------|------------|
| **C1** | 1-2 | Migrate ai_docs → docs + update all references | Rename + refs must be consistent |
| **C2** | 3-5 | Create rules/ + create docs/ + slim CLAUDE.md | Content must exist in new AND be removed from old simultaneously |
| **C3** | 6 | Optimize gemini-cli/llm-billing | Independent from restructuring |
| **C4** | 7 | Disable plugins (settings.json) | Independent behavioral change |
| **C5** | 8-9 | Wire skills to load docs + update project CLAUDE.md | Integration work |

Each commit leaves the system in a working state. C1 is safe because symlink provides backwards-compat. C2 is atomic so there's never a state where content is missing from both CLAUDE.md and rules/.

---

## Phase 1: Restructure CLAUDE.md + Rules + Docs

### Architecture

```
~/.claude/                          # Global (symlinked from dotfiles/claude/)
├── CLAUDE.md                       # Slim core (~120 lines, ~1.5k tokens)
├── rules/                          # Always-loaded behavioral rules (~350 lines, ~4.5k tokens)
│   ├── safety-and-git.md          # Zero tolerance table + git safety
│   ├── workflow-defaults.md       # Task/agent org, file creation, output strategy
│   ├── context-management.md      # PDF/large file rules, bulk edit constraint
│   ├── agents-and-delegation.md   # Subagent strategy, delegation decision tree
│   └── coding-conventions.md      # Python/shell basics, date formatting
├── docs/                           # On-demand knowledge (custom convention, NOT auto-loaded)
│   ├── research-methodology.md    # Full research workflow, experiment running, correctness
│   ├── async-and-performance.md   # Async patterns, batch APIs, caching, memory mgmt
│   ├── tmux-reference.md          # Full tmux setup, workflow, naming conventions
│   ├── agent-teams-guide.md       # Team composition, communication, known limitations
│   ├── documentation-lookup.md    # Context7, GitHub CLI, verified repos, decision tree
│   ├── environment-setup.md       # Agent spawning fix, machine setup, package managers
│   ├── ci-standards.md            # (migrated from ai_docs/)
│   └── ...                        # Other migrated ai_docs content
├── ai_docs -> docs                 # Permanent symlink (backwards-compat for other repos)
├── agents/                         # (unchanged)
├── skills/                         # (optimized, see Phase 2)
└── settings.json                   # (updated, see Phase 3)

<repo>/.claude/
├── CLAUDE.md                       # Project-specific instructions (unchanged)
├── docs/                           # Per-project knowledge (custom convention, NOT auto-loaded by Claude Code)
│   └── ...                        # Project-specific reference material
├── plans/                          # (unchanged)
└── tasks/                          # (unchanged)
```

**Important**: `.claude/docs/` is a **custom convention** we are establishing, NOT an official Claude Code feature. Claude Code does not auto-load or specially handle this directory. Skills and agents must explicitly read from it. This is intentional — docs are on-demand, not always-loaded.

### 1a. Slim `claude/CLAUDE.md` to ~120 lines (~1.5k tokens)

**Design principle**: CLAUDE.md = identity + pointers. Rules = behavioral details. No duplication.

**Keep in CLAUDE.md** (with NO duplication in rules/):
- AI Safety Research Context (5 lines — sets the high-level context)
- Default Behaviors (16-line bullet checklist — quick-scan reference)
- Communication Style (14 lines — personality/tone)
- Per-Project Learnings convention (15 lines — new section added 2026-02-05)
- Global vs repo-level convention table (15 lines — Phase 1f)
- Pointers to rules/ and docs/ (10 lines)
- Header/structure (~10 lines)

**Move to `rules/` entirely** (NOT duplicated in CLAUDE.md):
- Zero Tolerance Rules table → `rules/safety-and-git.md` (the ONLY location)
- File Creation Policy → `rules/workflow-defaults.md`
- Task and Agent Organization (90 lines!) → `rules/workflow-defaults.md`
- Shell Commands → `rules/coding-conventions.md`
- Git Commands → `rules/safety-and-git.md`
- Date & Timestamp Formatting → `rules/coding-conventions.md`
- Output Strategy → `rules/workflow-defaults.md`
- Context Management → `rules/context-management.md`
- Subagent Strategy → `rules/agents-and-delegation.md`
- Task Delegation Strategy → `rules/agents-and-delegation.md`

**Move to `docs/` entirely** (on-demand, not always loaded):
- Agent Spawning Fix → `docs/environment-setup.md`
- Machine-Specific Setup → `docs/environment-setup.md`
- Agent Team Strategy → `docs/agent-teams-guide.md`
- Documentation Lookup → `docs/documentation-lookup.md`
- Research Methodology → `docs/research-methodology.md`
- Python Guidelines → `docs/research-methodology.md` (or `rules/coding-conventions.md` for basics)
- Performance (Experiment Code) → `docs/async-and-performance.md`
- File Organization → `docs/research-methodology.md`
- Tools & Environment → `docs/environment-setup.md` + `docs/tmux-reference.md`

**Fix**: Remove duplicate "For work taking >30 minutes" paragraph (lines ~188-198 are verbatim copy of ~178-188)

**Why ~120 lines works now**: Previous estimate kept Task/Agent Organization (90 lines) in CLAUDE.md. Moving it to `rules/workflow-defaults.md` drops CLAUDE.md to ~120 lines. Rules are auto-loaded with same priority, so nothing is lost.

### 1b. Create `claude/rules/` — always-loaded behavioral rules (~350 lines)

**Design principle**: Rules = things Claude MUST follow in every session. No code examples, no verbose how-tos. No overlap with CLAUDE.md.

| Rule File | What Goes In | Est. Lines |
|-----------|-------------|------------|
| `safety-and-git.md` | Zero tolerance table (the 8-row table), git workflow (rebase, readable refs, pull behavior), destructive command warnings, race condition handling | ~80 |
| `workflow-defaults.md` | Task/agent organization (per-project plans/tasks, naming conventions), file creation policy, output strategy (non-destructive, programmatic), agent tracking format, shell command tips, **standard paths** (global: `~/.claude/{docs,plans,tasks}`, repo: `.claude/{docs,plans,tasks}`) | ~110 |
| `context-management.md` | Large file rules (PDF → subagent, >500 lines → offset/limit), verbose output handling (tmux-cli > background > redirect), bulk edit constraint (one editor per file), slide/presentation delegation | ~60 |
| `agents-and-delegation.md` | Subagent strategy table, task delegation decision tree (gemini vs codex vs claude), concurrent edit constraint, agent team escalation criteria (brief — full guide in docs/) | ~60 |
| `coding-conventions.md` | Python basics (uv, type hints, pytest, .env loading, sys.path safe pattern), shell basics (shellcheck), date/timestamp helpers, general programming rules, package managers | ~50 |

**Total**: ~350 lines, ~4.5k tokens

**Double-loading prevention** (critique finding #5): Each piece of content appears in EXACTLY ONE location. CLAUDE.md has zero overlap with rules/. If CLAUDE.md says "Default Behaviors", that checklist is only in CLAUDE.md. If rules/ has "Zero Tolerance", that table is only in rules/.

### 1c. Create `claude/docs/` — on-demand knowledge (rename from ai_docs/)

**Design principle**: Reference material loaded by skills when relevant. NOT always in context. Skills must explicitly link to these files — they are NOT auto-loaded.

| Doc File | Content | Est. Lines |
|----------|---------|------------|
| `research-methodology.md` | Core principles, correctness rules, workflow (interview→spec→plan→implement), running experiments (use existing code), common failure modes, incomplete data warnings, file organization, Hydra usage, data contamination prevention, Python guidelines | ~200 |
| `async-and-performance.md` | Async patterns (semaphore, gather, tenacity), batch API guide (Anthropic/OpenAI), caching patterns (3 reference implementations), memory management scripts, decision tree (I/O vs CPU vs GPU) | ~130 |
| `tmux-reference.md` | tmux-cli + native tmux hybrid, naming conventions, setup scripts, running experiments, inside/outside tmux, quick-reference copy-paste blocks | ~90 |
| `agent-teams-guide.md` | When to escalate, subagents vs teams comparison, team composition patterns (research/implementation/debugging/review), communication/coordination, best practices, anti-patterns, known limitations | ~75 |
| `documentation-lookup.md` | Priority order, Context7 workflow, GitHub CLI for specific files, verified repositories list, decision tree | ~60 |
| `environment-setup.md` | Agent spawning fix, machine-specific setup, package managers, CLI tools list | ~50 |

**Migrate existing `claude/ai_docs/` content** to `claude/docs/`:
- `anthroplot.md` → `claude/docs/anthroplot.md`
- `ci-standards.md` → `claude/docs/ci-standards.md`
- `experiment-memory-optimization.md` → `claude/docs/experiment-memory-optimization.md`
- `humanizer-patterns.md` → `claude/docs/humanizer-patterns.md`
- `paper-writing-style-guide.md` → `claude/docs/paper-writing-style-guide.md`
- `petri-plotting.md` → `claude/docs/petri-plotting.md`
- `plugin-configuration.md` → `claude/docs/plugin-configuration.md`
- `plugin-maintenance.md` → `claude/docs/plugin-maintenance.md`
- `reproducibility-checklist.md` → `claude/docs/reproducibility-checklist.md`
- `tool-installation.md` → `claude/docs/tool-installation.md`

Then create **permanent** symlink: `claude/ai_docs -> claude/docs` (not temporary — protects other repos).

**Total new + migrated docs**: ~605 new lines + 10 migrated files (NOT always loaded)

### 1d. Per-project docs convention: `<repo>/.claude/docs/`

**Note**: `.claude/docs/` is NOT an official Claude Code convention. We are establishing it as a custom convention. Claude Code will not auto-load or specially handle files in `.claude/docs/`. Skills and agents must explicitly read from it.

**Convention**:
- Global knowledge: `~/.claude/docs/` (renamed from `ai_docs/`, permanent symlink for compat)
- Per-project knowledge: `<repo>/.claude/docs/`
- Project-root `docs/` continues to be for user-facing documentation

---

## Phase 1e: Rename all `ai_docs` references → `docs` (CRITICAL)

**Scope**: The audit found **321 total references** to `ai_docs` across the repo. Most are in historical plan files and plugin cache (safe to ignore). The critical ones are in active code/config.

**Create permanent symlink FIRST:**
```
claude/ai_docs -> claude/docs   (permanent — protects other repos)
```

**Files with `ai_docs` references to update:**

| File | References | Priority |
|------|-----------|----------|
| **Marketplace plugins (CRITICAL):** | | |
| `claude/local-marketplace/plugins/writing-toolkit/agents/paper-writer.md` | Lines 93-95, 101 | **CRITICAL** |
| `claude/local-marketplace/plugins/research-toolkit/agents/research-skeptic.md` | Line 44 | **CRITICAL** |
| `claude/local-marketplace/plugins/research-toolkit/agents/experiment-designer.md` | Lines 52-53 | **CRITICAL** |
| `claude/local-marketplace/plugins/research-toolkit/agents/data-analyst.md` | Lines 31, 225 | **CRITICAL** |
| `claude/local-marketplace/plugins/research-toolkit/skills/api-experiments/SKILL.md` | Lines 10, 159 | **CRITICAL** |
| `claude/local-marketplace/plugins/research-toolkit/skills/reproducibility-report/SKILL.md` | Lines 11-12 | **CRITICAL** |
| `claude/local-marketplace/plugins/research-toolkit/skills/reproducibility-report/references/checklist.md` | Line 31 | MEDIUM |
| `claude/local-marketplace/plugins/writing-toolkit/skills/research-presentation/references/paper-figures.md` | Line 21 | MEDIUM |
| `claude/local-marketplace/plugins/writing-toolkit/README.md` | Lines 203, 271 | MEDIUM |
| **Migrated files with self-references (found by critique):** | | |
| `claude/ai_docs/reproducibility-checklist.md` (→ `claude/docs/`) | Lines 121, 337: `~/.claude/ai_docs/ci-standards.md` | **HIGH** |
| **Gemini CLI:** | | |
| `gemini/GEMINI.md` | Lines 64, 86, 118, 133 | **HIGH** |
| **Core config:** | | |
| `claude/CLAUDE.md` (global) | Lines 531, 856, 1030 | HIGH |
| `CLAUDE.md` (project) | Line 110 | HIGH |
| `claude/skills/docs-search.md` | Lines 22, 24 + implementation script | HIGH |
| **Historical/reference docs:** | | |
| `IMPLEMENTATION_GUIDE.md` | ~20 references | MEDIUM |
| `IMPLEMENTATION_SUMMARY.md` | Line 203 | LOW |
| `HUMANIZER_IMPLEMENTATION.md` | Lines 52, 241 | LOW |
| `specs/claude-memory.md` | Lines 4, 20 (update to note resolution) | LOW |

**Explicitly NOT updated** (historical artifacts, safe to leave):
- `claude/plans/*.md` — historical plans, read-only context
- `claude/plans.archive/*.md` — archived plans
- `claude/plugins/cache/` — auto-generated cache files

**Disposition of `scripts/rename_ai_docs.sh`** (found by critique): Delete after migration — its purpose is fulfilled. Or keep as documentation artifact with a note.

**Verification after all renames:**
```bash
# Comprehensive verification (expanded scope per critique)
rg 'ai_docs' --type md --type json --type sh --type yml \
  --glob '!claude/plans/*' \
  --glob '!claude/plans.archive/*' \
  --glob '!claude/plugins/cache/*' \
  .
# Should return 0 results (excluding historical artifacts)
```

## Phase 1f: Document global vs repo-level convention

Add clear convention to slim CLAUDE.md:

```
## Claude Code Directory Convention

| Artifact     | Global (~/.claude/)          | Per-project (<repo>/.claude/) |
|-------------|-------------------------------|-------------------------------|
| Instructions | CLAUDE.md                    | CLAUDE.md                     |
| Rules        | rules/*.md (auto-loaded)     | rules/*.md (auto-loaded)      |
| Knowledge    | docs/ (on-demand, custom)    | docs/ (on-demand, custom)     |
| Plans        | — (never global)             | plans/                        |
| Tasks        | — (never global)             | tasks/                        |
| Agents       | agents/*.md                  | agents/*.md                   |
| Skills       | skills/                      | (via plugins)                 |

Global = applies to ALL projects. Per-project = repo-specific, version-controlled.
Plans and tasks are ALWAYS per-project (never global).
docs/ is a custom convention (not auto-loaded by Claude Code) — skills read from it on demand.

Standard paths:
  Global:  ~/.claude/docs/  ~/.claude/rules/  (no plans/tasks globally)
  Repo:    .claude/docs/    .claude/rules/    .claude/plans/    .claude/tasks/
```

---

## Phase 2: Clean Up Skills

### ~~2a. Remove redundant user skills~~ REMOVED (critique: directories don't exist)

**Audit confirmed**: `claude/skills/codex-cli/` and `claude/skills/claude-code/` do NOT exist on disk. The deprecated skills are only in the plugin (`code-toolkit`). No deletion needed.

### 2b. Optimize gemini-cli skill + agent

**Current**: SKILL.md symlinks to agent definition (**402 lines** — corrected from ~250 per audit). Agent: `claude/agents/gemini-cli.md`.

**After**:
- `claude/agents/gemini-cli.md` — Slim to ~80 lines: trigger description, decision table, key examples. Remove CLI syntax details.
- `claude/skills/gemini-cli/references/gemini-syntax.md` — NEW: Full CLI syntax, command options, path rules, workflow steps (~320 lines, loaded only when skill invoked)

**Important**: Skill `references/` files are NOT auto-loaded by Claude Code. The slimmed SKILL.md (symlinked to agent) must include explicit markdown links like `For CLI syntax details, see [gemini-syntax.md](references/gemini-syntax.md)` so Claude can read them when needed.

**Tokens saved**: ~1.2k (corrected estimate based on 402 actual lines)

### 2c. Optimize llm-billing skill + agent

**Current**: SKILL.md symlinks to `claude/agents/llm-billing.md` (57 lines). Note: `llm-billing.py` (355 lines) is the implementation script, not the agent definition.

**After**:
- `claude/agents/llm-billing.md` — Slim to ~20 lines: trigger description + what it checks
- `claude/skills/llm-billing/references/billing-process.md` — NEW: Process details, environment variables, script instructions (~35 lines)

**Important**: Same as 2b — SKILL.md must explicitly link to reference doc.

**Tokens saved**: ~200

### 2d. Total skill savings: ~1.4k tokens

---

## Phase 3: Plugin & MCP Pruning

**Note**: This is a SEPARATE commit from the restructuring (critique: don't conflate behavioral changes with documentation restructuring).

### 3a. Disable Serena

Set `"serena@claude-plugins-official": false` in `claude/settings.json`

**Saves**: ~6k tokens (35+ MCP tools)
**Rationale**: Overlap with built-in Read/Write/Grep/Glob/Edit. Unique LSP features (rename_symbol, find_referencing_symbols) rarely used. Can re-enable per-project via `.claude/settings.json`.

### 3b. Disable rarely-used plugins

| Plugin | Disable | Rationale |
|--------|---------|-----------|
| `feature-dev@claude-plugins-official` | Yes | Recently added, not established |
| `ralph-loop@claude-plugins-official` | Yes | Niche, re-enable when needed |
| `pyright-lsp@claude-plugins-official` | Yes | LSP overlap, rarely triggered |

**Saves**: ~500-1k tokens

### 3c. Remaining enabled plugins (16 → 12 after pruning)

context7, superpowers, hookify, learning-output-style, plugin-dev, commit-commands, code-review, security-guidance, code-simplifier, research-toolkit, writing-toolkit, code-toolkit

---

## Phase 4: Wire Skills to Load Docs

**Important**: `.claude/docs/` files are NOT auto-loaded. Each skill/agent that needs them must include explicit `Read` instructions or markdown links.

Update skill/agent definitions to reference `~/.claude/docs/` when invoked:

| Skill/Agent | Loads | How |
|-------------|-------|-----|
| `/run-experiment` | `docs/async-and-performance.md`, `docs/research-methodology.md` | SKILL.md instruction: "Read ~/.claude/docs/research-methodology.md before running" |
| `/spec-interview-research` | `docs/research-methodology.md` | SKILL.md instruction |
| `/agent-teams` | `docs/agent-teams-guide.md` | SKILL.md instruction |
| `gemini-cli` (agent) | `skills/gemini-cli/references/gemini-syntax.md` | Markdown link in agent definition |
| `llm-billing` (agent) | `skills/llm-billing/references/billing-process.md` | Markdown link in agent definition |
| **Marketplace plugins:** | | |
| `paper-writer` (writing-toolkit) | `docs/paper-writing-style-guide.md`, `docs/ci-standards.md` | Agent definition instruction |
| `research-skeptic` (research-toolkit) | `docs/ci-standards.md` | Agent definition instruction |
| `experiment-designer` (research-toolkit) | `docs/ci-standards.md` | Agent definition instruction |
| `data-analyst` (research-toolkit) | `docs/anthroplot.md`, `docs/ci-standards.md` | Agent definition instruction |
| `reproducibility-report` (research-toolkit) | `docs/reproducibility-checklist.md` | SKILL.md instruction |
| `api-experiments` (research-toolkit) | `docs/experiment-memory-optimization.md` | SKILL.md instruction |
| `/docs-search` skill | Update implementation to search `~/.claude/docs/` | Update `fd` + `rg` pattern in embedded script |

**`/docs-search` implementation fix** (critique finding #10):
The embedded script in `claude/skills/docs-search.md` (~line 97-106) uses:
```bash
fd -e md ... | grep -E "(docs/|specs/|CLAUDE\.md|README\.md)"
```
This already searches project `docs/` but the global `~/.claude/docs/` may not be in scope. Add a second search pass targeting `~/.claude/docs/` explicitly.

---

## Token Budget Summary (corrected per critique)

| Category | Before | After | Saved |
|----------|--------|-------|-------|
| CLAUDE.md (slim, ~120 lines) | 12.6k | ~1.5k | — |
| Rules (new, always-loaded, ~350 lines) | 0 | ~4.5k | — |
| **Subtotal always-loaded memory** | **12.6k** | **~6k** | **~6.6k** |
| Skills (gemini-cli/llm-billing optimized) | 9.9k | ~8.7k | ~1.2k |
| MCP tools (Serena removed) | 17.5k | ~11.5k | ~6k |
| Plugin overhead (3 disabled) | (in skills) | (reduced) | ~0.5k |
| **Total overhead** | **~48k** | **~33k** | **~15k (31%)** |

Free space increases from **~95k → ~110k tokens**.

---

## Files to Modify

**Create** (11 files):
- `claude/rules/safety-and-git.md`
- `claude/rules/workflow-defaults.md`
- `claude/rules/context-management.md`
- `claude/rules/agents-and-delegation.md`
- `claude/rules/coding-conventions.md`
- `claude/docs/research-methodology.md`
- `claude/docs/async-and-performance.md`
- `claude/docs/tmux-reference.md`
- `claude/docs/agent-teams-guide.md`
- `claude/docs/documentation-lookup.md`
- `claude/docs/environment-setup.md`

**Create** (2 reference docs for skills):
- `claude/skills/gemini-cli/references/gemini-syntax.md`
- `claude/skills/llm-billing/references/billing-process.md`

**Edit** (~20 files):
- `claude/CLAUDE.md` — slim to ~120 lines
- `claude/agents/gemini-cli.md` — slim 402 → ~80 lines, add link to references/
- `claude/agents/llm-billing.md` — slim 57 → ~20 lines, add link to references/
- `claude/settings.json` — disable 4 plugins
- `CLAUDE.md` (project) — update docs path references + convention table
- `gemini/GEMINI.md` — update 4 `ai_docs/` references
- `claude/skills/docs-search.md` — update paths + implementation script
- `claude/docs/reproducibility-checklist.md` — fix self-references (lines 121, 337)
- `specs/claude-memory.md` — note resolution of docs convention
- **8 marketplace plugin files** (ai_docs → docs path update):
  - `claude/local-marketplace/plugins/writing-toolkit/agents/paper-writer.md`
  - `claude/local-marketplace/plugins/research-toolkit/agents/research-skeptic.md`
  - `claude/local-marketplace/plugins/research-toolkit/agents/experiment-designer.md`
  - `claude/local-marketplace/plugins/research-toolkit/agents/data-analyst.md`
  - `claude/local-marketplace/plugins/research-toolkit/skills/api-experiments/SKILL.md`
  - `claude/local-marketplace/plugins/research-toolkit/skills/reproducibility-report/SKILL.md`
  - `claude/local-marketplace/plugins/research-toolkit/skills/reproducibility-report/references/checklist.md`
  - `claude/local-marketplace/plugins/writing-toolkit/skills/research-presentation/references/paper-figures.md`
- `IMPLEMENTATION_GUIDE.md`, `IMPLEMENTATION_SUMMARY.md`, `HUMANIZER_IMPLEMENTATION.md` — update references

**Delete/archive** (1 file):
- `scripts/rename_ai_docs.sh` — purpose fulfilled by this migration

**Migrate** (10 files from ai_docs/ → docs/):
- Move all 10 files from `claude/ai_docs/` to `claude/docs/`
- Create **permanent** symlink: `claude/ai_docs -> claude/docs`

---

## Execution Order (mapped to commits)

### Commit 1: Migrate ai_docs → docs + update references
1. `git tag pre-restructure` — rollback anchor
2. **Create `claude/docs/` directory**
3. **Move all 10 files** from `claude/ai_docs/` to `claude/docs/`
4. **Create permanent symlink**: `claude/ai_docs -> claude/docs`
5. **Fix self-references** in `claude/docs/reproducibility-checklist.md` (lines 121, 337)
6. **Update all `ai_docs` references** — ~20 files (Phase 1e table)
7. **Delete `scripts/rename_ai_docs.sh`** (migration complete)
8. **Verify**: `rg 'ai_docs' --type md --type json --type sh --glob '!claude/plans/*' --glob '!claude/plugins/cache/*' .` → 0 results

### Commit 2: Create rules + docs + slim CLAUDE.md (ATOMIC)
9. **Create `claude/rules/`** — write all 5 rule files by extracting from CLAUDE.md
10. **Create 6 new knowledge docs** in `claude/docs/`
11. **Slim `claude/CLAUDE.md`** — reduce to ~120 lines (do AFTER rules/docs exist)
12. **Verify**: Start new session, confirm rules load, safety rules active

### Commit 3: Optimize skills
13. **Slim `claude/agents/gemini-cli.md`** (402 → ~80 lines)
14. **Create `claude/skills/gemini-cli/references/gemini-syntax.md`** (~320 lines)
15. **Slim `claude/agents/llm-billing.md`** (57 → ~20 lines)
16. **Create `claude/skills/llm-billing/references/billing-process.md`** (~35 lines)

### Commit 4: Disable plugins (separate behavioral change)
17. **Update `claude/settings.json`** — disable Serena + 3 plugins

### Commit 5: Wire skills + update project docs
18. **Wire skills to load docs** — update marketplace plugins + /docs-search (Phase 4)
19. **Update `CLAUDE.md` (project)** — new convention table + docs path
20. **Update `specs/claude-memory.md`** — note resolution

---

## Verification

1. **Token count**: `/context` should show ~33k total overhead (down from 48k)
2. **Rules load**: New session shows safety rules active (test: violate a zero-tolerance rule, confirm Claude flags it)
3. **No duplication**: `rg 'Zero Tolerance' claude/CLAUDE.md claude/rules/` — appears in exactly ONE file
4. **Skills work**: `/run-experiment` loads research-methodology.md correctly
5. **Agents work**: `gemini-cli` and `llm-billing` still function
6. **No Serena**: MCP tools section reduced
7. **Docs accessible**: Subagents can read from `claude/docs/` path
8. **Symlink works**: `ls -la claude/ai_docs` → points to `docs`
9. **ai_docs clean**: `rg 'ai_docs' --type md --type sh --glob '!claude/plans/*' --glob '!claude/plugins/cache/*' .` → 0 results
10. **No broken refs**: Test each marketplace plugin agent can find its docs
