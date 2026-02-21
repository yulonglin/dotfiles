# AI Safety Plugins Marketplace: Self-Containedness Audit & Migration Plan

## Context

The AI Safety Plugins repo (`~/code/ai-safety-plugins/`) is a Claude Code marketplace with 6 plugins. Audit revealed it's ~70% self-contained (lower than initially estimated). Three parallel critics (Codex plan-critic, Claude architect, Gemini sweeper) identified issues the initial audit missed.

## Critical Architectural Constraint

**`${CLAUDE_PLUGIN_ROOT}` does NOT work in markdown files.** It's only expanded in `plugin.json` hook `command` fields (shell execution). All existing plugin references use **relative paths** (`references/X.md`). Agent prompts that reference docs use absolute `~/.claude/docs/X` paths — the model reads these via the Read tool.

**Implication:** Bundled reference docs can use relative paths in skills (auto-loaded), but agent prompt references must use absolute paths the model can Read. Cross-plugin references are impossible with relative paths.

---

## Phase 1: Fix Broken References (CRITICAL — do now)

### 1A. Bundle 4 docs into plugin `references/` directories

| Doc | Target Location | Referenced By |
|-----|----------------|---------------|
| `ci-standards.md` | `research/agents/references/ci-standards.md` + duplicate to `writing/agents/references/ci-standards.md` | 5 research + 1 writing components |
| `anthroplot.md` | `research/agents/references/anthroplot.md` | data-analyst, paper-figures |
| `paper-writing-style-guide.md` | `writing/agents/references/paper-writing-style-guide.md` | paper-writer |
| `reproducibility-checklist.md` | `research/skills/reproducibility-report/references/neurips-paper-checklist.md` | paper-writer, reproducibility-report |

**Do NOT merge** `reproducibility-checklist.md` with existing `checklist.md` — they're completely different documents (NeurIPS submission checklist vs operational validation checklist).

**For ci-standards.md cross-plugin reference:** Duplicate into both `research/agents/references/` and `writing/agents/references/` with a header comment: `<!-- Canonical source: research/agents/references/ci-standards.md — keep in sync -->`.

**Path strategy for agent prompts:** Keep existing `~/.claude/docs/X` absolute paths (agents instruct the model to Read these). Also add bundled copies so the plugin is self-contained. Add a README section telling marketplace users to copy refs to `~/.claude/docs/` OR add a simple setup script.

Create `research/agents/references/` directory (doesn't exist yet — only `code` has `agents/references/`).

### 1B. Inline CLAUDE.md-specific methodology references (correctness bug, not polish)

3 agents reference YOUR specific CLAUDE.md content that marketplace users won't have:

| Agent | Current Reference | Inline Replacement |
|-------|------------------|-------------------|
| `research/agents/experiment-designer.md` | "CLAUDE.md methodology (de-risking, confound checking, predict-before-running)" | "De-risk experiments incrementally, check for confounds systematically, predict results before running, minimize variables changed per experiment" |
| `research/agents/research-skeptic.md` | "Embodies CLAUDE.md lines 55-59 skepticism principles" | "Question convenient results, identify confounds, resist confirmation bias. Surprisingly good or bad results warrant investigation before concluding" |
| `research/agents/research-engineer.md` | "CLAUDE.md-compliant research code" | "Research code: CLI args (not hardcoded), JSONL output, proper logging, random seeds, checkpointing" |

Keep generic "CLAUDE.md compliance" references (30+ occurrences) — those correctly refer to the user's own CLAUDE.md.

### 1C. Remove personal dotfiles references

- **Remove** `core/skills/fast-cli/SKILL.md` lines 205-221 ("Custom Utilities (dotfiles)" section)
- **Fix** `writing/skills/research-presentation/references/paper-figures.md` line 10: change `/path/to/dotfiles/config/matplotlib/anthropic.mplstyle` → `plt.style.use('anthropic')` with note about stylelib installation
- **Fix** hardcoded `/Users/yulong/code/myproject` examples in `code/agents/references/plan-implementation.md`, `core/agents/claude.md`, `core/agents/codex.md` → generic path

### 1D. Fix README inaccuracies

| Issue | Fix |
|-------|-----|
| Core agents table lists 4, but 5 exist | Add `claude` agent |
| Code agents lists `claude` | Remove (it's in core) |
| Code skills lists `/codex-cli`, `/claude-code` | Remove (don't exist) |
| Research skills lists 8, but 11 exist | Add `audit-docs`, `new-experiment`, `reflect` |
| Workflow skills lists `/insights` | Change to `/custom-insights` |

---

## Phase 2: Fix Additional Broken Paths (IMPORTANT — do next)

Found by Gemini sweep — these are broken for marketplace users:

### 2A. Fix `~/.claude/skills/` self-references (5+ skills)

These skills reference their own files via absolute `~/.claude/skills/` paths instead of relative:

| Skill | Broken Reference | Fix |
|-------|-----------------|-----|
| `writing/skills/research-presentation/SKILL.md:24` | `~/.claude/skills/research-presentation/GUIDE.md` | `references/GUIDE.md` (relative) |
| `research/skills/experiment-setup/SKILL.md:22` | `~/.claude/skills/experiment-setup/GUIDE.md` | `references/GUIDE.md` (relative) |
| `research/skills/new-experiment/SKILL.md:31` | `~/.claude/skills/new-experiment/references/template.md` | `references/template.md` (relative) |
| `research/skills/mats-slurm/SKILL.md:19,23` | `~/.claude/skills/mats-slurm/templates/...` and `REFERENCE.md` | `templates/...` and `REFERENCE.md` (relative) |

Skills DO support relative path resolution (confirmed by existing `viz/skills/tikz-diagrams` using `references/diagram-pattern-catalog.md`).

### 2B. Bundle missing referenced files

| File | Referenced By | Action |
|------|--------------|--------|
| `~/.claude/templates/research-spec.md` | `research/skills/generate-research-spec/SKILL.md:12` | Copy into `research/skills/generate-research-spec/references/research-spec-template.md` |
| `~/.claude/skills/gemini-cli/references/gemini-syntax.md` | `core/agents/gemini-cli.md:51` | Check if this file exists anywhere; if not, create it or remove the reference |

### 2C. Fix cross-plugin dependency leaks

Core hooks referencing research-only skills:

| File | Reference | Fix |
|------|-----------|-----|
| `core/hooks/experiment_prime.sh:50` | "Consider running `/reflect`" | Guard with "if research plugin installed" check, or remove |
| `core/hooks/experiment_prime.sh:77` | "Consider running `/audit-docs`" | Same |

### 2D. Document undocumented external dependencies

- `workflow/skills/custom-insights/SKILL.md` requires `~/code/claude-code-insights` repo — add to README dependency matrix or note in skill

---

## Phase 3: Defer (no immediate action needed)

| Item | Reason to Defer |
|------|----------------|
| `anthropic-style` skill migration | Available from Anthropic's own skills repo; placement debatable (core vs viz) |
| `llm-billing` skill migration | Zero marketplace demand; portability work is real; better as standalone mini-plugin if ever |
| `anthropic.mplstyle` bundling | Enhancement, not broken |
| `CONTRIBUTING.md` | Cosmetic |
| Shared `core/references/` architecture | Solve if cross-plugin refs become more common; for now, 1 duplicated file (ci-standards) is fine |
| `docs-search` skill update | It searches `~/.claude/docs/` which works for dotfiles users; marketplace users without docs get empty results (graceful degradation) |

---

## Files to Modify (Phase 1)

**In ai-safety-plugins repo (`~/code/ai-safety-plugins/`):**

New files to create:
- `plugins/research/agents/references/ci-standards.md` (copy from `dotfiles/claude/docs/`)
- `plugins/research/agents/references/anthroplot.md` (copy from `dotfiles/claude/docs/`)
- `plugins/research/skills/reproducibility-report/references/neurips-paper-checklist.md` (copy from `dotfiles/claude/docs/reproducibility-checklist.md`)
- `plugins/writing/agents/references/paper-writing-style-guide.md` (copy from `dotfiles/claude/docs/`)
- `plugins/writing/agents/references/ci-standards.md` (duplicate with sync comment)

Files to edit:
- `plugins/research/agents/experiment-designer.md` (inline CLAUDE.md methodology)
- `plugins/research/agents/research-skeptic.md` (inline CLAUDE.md principles)
- `plugins/research/agents/research-engineer.md` (inline CLAUDE.md code standards)
- `plugins/core/skills/fast-cli/SKILL.md` (remove personal utils section)
- `plugins/writing/skills/research-presentation/references/paper-figures.md` (fix matplotlib path)
- `plugins/core/agents/claude.md` (fix example path)
- `plugins/core/agents/codex.md` (fix example path)
- `plugins/code/agents/references/plan-implementation.md` (fix example path)
- `README.md` (fix 5 inaccuracies + add "Optional Docs" section)

## Verification

### Phase 1
```bash
# No more broken doc references
grep -r '~/.claude/docs/' plugins/ | grep -v '# Optional' | grep -v 'docs-search'  # should be 0

# No hardcoded personal paths
grep -r '/Users/yulong' plugins/  # should be 0

# No personal dotfiles sections
grep -r 'Custom Utilities (dotfiles)' plugins/  # should be 0

# README accuracy: manually verify agent/skill counts match filesystem
```

### Phase 2
```bash
# No absolute skill self-references
grep -r '~/.claude/skills/' plugins/ | grep -v '# legacy'  # should be 0

# No missing template references
grep -r '~/.claude/templates/' plugins/  # should be 0
```

### Smoke Tests
- Spawn `data-analyst` agent → verify it can find and read `ci-standards.md` from plugin references
- Run `docs-search ci-standards` → verify it finds the file
- Invoke `/anthropic-style` → verify it loads (stays in dotfiles for now)

### Post-Migration
- Run `claude-context --sync` to update plugin cache (Claude Code runs from cache, not source)
- Verify cache reflects new files: `ls ~/.claude/plugins/cache/ai-safety-plugins/research/*/agents/references/`
