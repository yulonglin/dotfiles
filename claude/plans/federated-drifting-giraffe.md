# Plan: Context-Aware Plugin Organization

## Context

**Problem:** ~100+ skills, agents, and MCP servers load globally, consuming ~9.9k tokens (5% context) in skill descriptions alone. No way to selectively load based on project type. Many official plugins are implicitly enabled (not listed in `enabledPlugins` = defaults to on), which is a major hidden source of bloat.

**Mechanism:** Per-project `.claude/settings.json` → `enabledPlugins` is the only lever. Disabling a plugin prevents its skills, agents, and MCP servers from entering context.

**Key findings:**
- 6 official plugins are "always on" (superpowers, hookify, plugin-dev, commit-commands, claude-md-management, context7)
- ~10 official plugins are implicitly enabled and loading silently (document-skills, figma, HF-skills, Notion, vercel, stripe, etc.)
- 86 skill symlinks cause every plugin skill to appear twice in slash picker
- 4 different code-reviewer agents, stale cache versions, cache-source divergence
- `humanize-draft` planned for merge into `review-draft`; `brand-guidelines` is exact dupe of `anthropic-style`

---

## Part 1: Consolidate Local Plugins (4 + Core)

### Plugin Structure

```
claude/local-marketplace/plugins/
├── research-toolkit/     # Experiments, papers, evals
├── writing-toolkit/      # Papers, drafts, presentations, review
├── code-toolkit/         # Dev workflow, debugging, delegation, code review
├── workflow-toolkit/     # NEW: Agent teams, handover, insights
└── viz-toolkit/          # NEW: Matplotlib plotting, TikZ diagrams, Anthropic style
```

### Skill Migrations

**research-toolkit** (no changes):
- KEEP ALL: api-experiments, experiment-setup, generate-research-spec, mats-slurm, read-paper, reproducibility-report, run-experiment, spec-interview-research
- Agents: KEEP ALL (data-analyst, experiment-designer, literature-scout, research-advisor, research-engineer, research-skeptic)

**writing-toolkit** (existing + merge):
- KEEP: clear-writing, fix-slide, research-presentation, review-draft, review-paper, slidev
- MERGE: `humanize-draft` → fold LLM-ism detection into `review-draft`'s clarity critic (already planned per v0.1 notes)
- ADD: `strategic-communication` (currently user skill)
- Agents: KEEP ALL

**code-toolkit** (no skill changes, fix agents):
- KEEP ALL: bulk-edit, claude-code, codex-cli, deslop, fix-merge-conflict
- FIX: Copy `codex.md` and `claude.md` agents from cache back to source (cache divergence)
- Agents: code-reviewer, debugger, performance-optimizer, tooling-engineer, codex, claude

**viz-toolkit** (NEW — plotting, diagrams, figures):
- `tikz-diagrams` (NEW — from `/Users/yulong/Downloads/anthropic-tikz-kit/`, Anthropic-style TikZ for ML papers)
  - references/: `diagram-pattern-catalog.md` (17 patterns), `anthropic-tikz.sty`, `anthropic-tikz-v3.tex` examples
  - reference-images/: 16 real Anthropic/OAI blog figures as visual targets
  - Known issues: Examples 2 and 4 in PDF have rendering issues (noted in README)
- References to `lib/plotting/petriplot.py`, `lib/plotting/anthro_colors.py`, matplotlib .mplstyle files

**workflow-toolkit** (NEW — absorbs insights-toolkit):
- `agent-teams` (team coordination)
- `externalise-handover` (handover documentation)
- `custom-compact` (conversation management)
- `insights` (usage analytics — from insights-toolkit)

### Core User Skills (always loaded, never in a plugin)

| Skill | Why always-on |
|---|---|
| `efficient-explorer` | Referenced in rules, universally needed |
| `context-summariser` | Conversation management |
| `docs-search` | Documentation lookup |
| `gemini-cli` | Large context delegation (papers, codebases, logs) |
| `spec-interview` | General interview utility (domain-specific variants in plugins) |
| `commit` | Git commit across all projects |
| `commit-push-sync` | Commit + push across all projects |
| `task-management` | UTC-timestamped task/plan naming conventions |
| `fast-cli` | Modern CLI tool mappings (eza, fd, rg, bat, etc.) |
| `anthropic-style` | Plotting defaults (cross-domain, tiny footprint) |
| `llm-billing` | Quick utility |
| `.system/skill-creator` | Meta: creating skills |
| `.system/skill-installer` | Meta: installing skills |

---

## Part 2: Slim Skill Token Footprint

Skills have 3 layers with different context cost:

```
description (frontmatter)  → ALWAYS in context. Minimize ruthlessly.
SKILL.md body              → Loaded on /skill invocation. Keep as slim routing guide.
references/*.md            → Loaded only when body says "Read references/X.md". All detail here.
```

### Step 2a: Slim frontmatter descriptions

**Problem:** Several skills have bloated descriptions with examples that waste always-on tokens.

| Skill | Current | Target | Savings |
|---|---|---|---|
| `gemini-cli` | 8 bullets + 8 examples (~1.1k tokens) | 1-2 lines, no examples | ~900 |
| `llm-billing` | 3 lines + 3 examples (~254 tokens) | 1 line, no examples | ~200 |
| `fast-cli` | Long trigger list (~77 tokens) | Slim | ~30 |
| All local-marketplace skills | Audit each | 1-2 lines max | TBD |

**Target pattern** (efficient-explorer, docs-search):
```yaml
description: One-line summary. When to use it.
```

### Step 2b: Move heavy body content to references/

For skills with large SKILL.md bodies, extract detailed content into `references/`:

**Example — gemini-cli:**
- Body: Slim usage guide (sync/async modes, model selection, session naming)
- `references/examples.md`: All 8 use-case examples (currently bloating frontmatter)
- `references/prompt-construction.md`: Prompt templates

**Example — codex-cli** (already does this well):
- Body: Core workflow
- `references/model-selection.md`: Model listing/configuration

**Pattern already used by:** spec-interview, strategic-communication, review-paper, research-presentation, reproducibility-report, read-paper, commit-push-sync.

**Apply to ALL skills** that have >50 lines in body without using references.

---

## Part 3: Deduplication

| Issue | Action |
|---|---|
| `humanize-draft` overlaps `review-draft` | MERGE: fold phrase detection into review-draft's clarity critic |
| `brand-guidelines` = `anthropic-style` | DROP: brand-guidelines (100% identical, can't remove from official plugin but user skill takes precedence) |
| `frontend-design` (2 copies) | Can't remove from official plugins; per-project disabling handles this |
| 4 `code-reviewer` agents | KEEP code-toolkit's + coderabbit's; official ones can't be removed but plugin disabling reduces noise |
| Stale plugin cache (4x context7, serena, etc.) | NEW: `claude-cache-clean` custom binary |
| code-toolkit cache ≠ source | FIX: sync `codex.md` and `claude.md` agents |
| 86 skill symlinks (known bug) | EXISTING: `clean-skill-dupes` alias handles this |

---

## Part 4: Context Profiles

### Official Plugin Classification

**Always-on** (enabled in all contexts):
```
superpowers, hookify, plugin-dev, commit-commands, claude-md-management, context7
```

**Context-specific** (toggled per profile):
```
viz-toolkit        → research, writing, design
document-skills    → writing, design
figma              → design
ui-ux-pro-max      → design
frontend-design    → design
huggingface-skills → research
Notion             → research, writing
vercel             → code, design
coderabbit         → code
code-simplifier    → code
security-guidance  → code
pyright-lsp        → code
```

**Always-off** (explicitly disabled globally):
```
ralph-loop, serena, feature-dev, example-plugin,
slack, github, greptile, swift-lsp, supabase, playwright
```
NOTE: Verify actual plugin IDs with `claude /plugin` before writing templates. Keys like `document-skills@anthropic-agent-skills` may use different format internally.

### Context Templates

Each template sets `enabledPlugins` for ALL plugins (explicit is better than implicit defaults).

**`writing`** — papers, blog posts, documentation:
```json
{
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "hookify@claude-plugins-official": true,
    "plugin-dev@claude-plugins-official": true,
    "commit-commands@claude-plugins-official": true,
    "claude-md-management@claude-plugins-official": true,
    "context7@claude-plugins-official": true,
    "writing-toolkit@local-marketplace": true,
    "viz-toolkit@local-marketplace": true,
    "document-skills@anthropic-agent-skills": true,
    "Notion@claude-plugins-official": true,
    "research-toolkit@local-marketplace": false,
    "code-toolkit@local-marketplace": false,
    "workflow-toolkit@local-marketplace": false,
    "figma@claude-plugins-official": false,
    "ui-ux-pro-max@ui-ux-pro-max-skill": false,
    "huggingface-skills@claude-plugins-official": false,
    "vercel@claude-plugins-official": false,
    "coderabbit@claude-plugins-official": false,
    "code-simplifier@claude-plugins-official": false,
    "security-guidance@claude-plugins-official": false,
    "ralph-loop@claude-plugins-official": false,
    "pyright-lsp@claude-plugins-official": false,
    "serena@claude-plugins-official": false,
    "feature-dev@claude-plugins-official": false,
    "stripe@claude-plugins-official": false,
    "insights-toolkit@local-marketplace": false
  }
}
```

**`research`** — experiments, evals, analysis:
```json
Same always-on block, plus:
    "research-toolkit@local-marketplace": true,
    "writing-toolkit@local-marketplace": true,
    "workflow-toolkit@local-marketplace": true,
    "viz-toolkit@local-marketplace": true,
    "Notion@claude-plugins-official": true,
    // everything else false (add `ml` sub-profile for HF)
```

**`code`** — software projects:
```json
Same always-on block, plus:
    "code-toolkit@local-marketplace": true,
    "workflow-toolkit@local-marketplace": true,
    "coderabbit@claude-plugins-official": true,
    "code-simplifier@claude-plugins-official": true,
    "security-guidance@claude-plugins-official": true,
    // everything else false (add `web` for vercel/stripe, `python` for pyright)
```

**`design`** — frontend, visualizations, web:
```json
Same always-on block, plus:
    "document-skills@anthropic-agent-skills": true,
    "figma@claude-plugins-official": true,
    "ui-ux-pro-max@ui-ux-pro-max-skill": true,
    "frontend-design@claude-plugins-official": true,
    "code-toolkit@local-marketplace": true,
    "vercel@claude-plugins-official": true,
    "viz-toolkit@local-marketplace": true,
    // everything else false
```

**`full`** — dotfiles, meta-work:
```json
Everything true except always-off list.
```

### Language/Framework Sub-Profiles

Composable with domain profiles via union merging. Each only sets 1-3 plugins.

| Template | Enables | Typical combos |
|----------|---------|----------------|
| `python` | pyright-lsp | `code python`, `research python` |
| `web` | vercel, stripe, typescript-lsp (verify plugin ID) | `code web`, `design web` |
| `ml` | huggingface-skills | `research ml`, `code ml` |

**Domain profiles adjusted** — framework-specific plugins moved to sub-profiles:
- `code` no longer includes vercel/stripe (use `code web`)
- `research` no longer includes huggingface-skills (use `research ml`)
- `design` keeps vercel (web is inherent to design work)

For one-off plugins (e.g., stripe without the rest of `web`) — add directly to project `.claude/settings.json`.

### `claude-context` CLI Tool

Custom binary in `custom_bins/`:

```bash
claude-context                   # Show current profile(s)
claude-context writing           # Apply writing profile
claude-context code              # Apply code profile
claude-context code python       # Code + Python (pyright-lsp)
claude-context code web          # Code + web (vercel, stripe, TS LSP)
claude-context research ml       # Research + ML (huggingface)
claude-context code web python   # Code + web + python (union of all three)
claude-context full              # Enable all
```

**Multi-profile merging:** Any plugin `true` in any specified profile → `true`. Only `false` if `false` in ALL specified profiles. Always-on plugins are always `true`.

**How it works:**
1. Templates stored in `~/.claude/templates/contexts/*.json`
2. Merges `enabledPlugins` into `.claude/settings.local.json` in current repo (auto-gitignored)
3. Preserves existing non-plugin settings in `.local.json`
4. Creates `.claude/` dir if needed

**Recommended workflow:**
- Commit `.claude/settings.json` for permanent project defaults
- Use `claude-context` for ad-hoc overrides (`.local.json` takes precedence)

**Setting up a new repo:**
```bash
cd new-project
claude-context code       # One command. Creates .claude/settings.local.json
# Start using Claude Code — only code plugins load
```

**Making it permanent for a repo:**
```bash
cd my-website
claude-context writing    # Creates .local.json (temporary/personal)
# If you want this for all machines:
cp .claude/settings.local.json .claude/settings.json
git add .claude/settings.json && git commit -m "chore: set claude context to writing"
```

**Switching context in an existing repo:**
```bash
claude-context research   # Overwrites enabledPlugins in .local.json
# Restart Claude Code to pick up changes
```

---

## Part 5: Global Settings Cleanup (Aggressive Defaults)

**Principle:** Global default = everything OFF except 6 always-on plugins. Projects opt-in via `claude-context` or per-project `.claude/settings.json`. This is the most aggressive approach — zero surprise context loading.

**Before:** Many plugins not listed → implicitly enabled → silently loading docx, pptx, xlsx, figma, HF, Notion, vercel, stripe, etc.
**After:** Every known plugin explicitly listed as `false` globally. Only always-on plugins (`superpowers`, `hookify`, `plugin-dev`, `commit-commands`, `claude-md-management`, `context7`) and local-marketplace plugins needed for the current context are `true`.

**Plugins to explicitly disable globally** (currently loading silently):
- `document-skills@anthropic-agent-skills` (docx, pptx, xlsx, pdf, canvas-design, frontend-design, algorithmic-art, etc.)
- `figma@claude-plugins-official` (implement-design, create-design-system-rules, code-connect-components)
- `huggingface-skills@claude-plugins-official` (9 HF skills)
- `Notion@claude-plugins-official` (knowledge-capture, meeting-intelligence, research-documentation, spec-to-implementation)
- `vercel@claude-plugins-official` (deploy, setup, logs)
- `stripe@claude-plugins-official` (stripe-best-practices)
- `ui-ux-pro-max@ui-ux-pro-max-skill` (ui-ux-pro-max)
- `claude-code-setup@claude-plugins-official` (claude-automation-recommender)
- `example-plugin@claude-plugins-official` (example-skill)
- `coderabbit@claude-plugins-official` (code-review)

**Candidates for full uninstall** (remove from cache entirely):
- `ralph-loop` — never used
- `example-plugin` — template/demo only

**Keep installed but disabled globally** (used occasionally, enable per-project):
- `code-simplifier` — used, enable in code context when needed
- `security-guidance` — used, enable in code context when needed
- `pyright-lsp` — enable for Python type-checking projects

Uninstall with `claude /plugin` → uninstall. Saves disk and prevents any accidental loading.

---

## Implementation Steps (Phased)

### Phase 0: Backup
0a. **Commit current state** — `git add` all uncommitted changes (settings.json, voiceink config, plan file) and commit as a snapshot before restructuring. Gives a clean `git revert` rollback point.
0b. **Backup non-git-tracked plugin state** — `tar czf /tmp/claude/claude-plugins-backup.tar.gz claude/plugins/installed_plugins.json claude/plugins/known_marketplaces.json claude/plugins/cache/`. The cache (~30MB) saves re-download time; `installed_plugins.json` and `known_marketplaces.json` are the critical configs. Skip `marketplaces/` (185MB, auto-clones on sync) and `projects/`/`debug/`/`file-history/` (ephemeral, machine-specific).

### Phase 1: Plugin scaffolding + reorganization
1. **Verify plugin IDs** — run `claude /plugin` to get exact enabledPlugins keys for all installed plugins
2. **Create `workflow-toolkit` plugin** — scaffold plugin.json, move skills (agent-teams, externalise-handover, custom-compact, insights)
3. **Create `viz-toolkit` plugin** — scaffold plugin.json, create tikz-diagrams skill from Downloads kit
4. **Update `marketplace.json`** — register workflow-toolkit and viz-toolkit
5. **Test new plugins load** — install via `/plugin`, verify in `/context`

### Phase 2: Skill migration + deduplication
6. **Migrate user skills** — strategic-communication → writing-toolkit
7. **Merge `humanize-draft` into `review-draft`** — fold phrase detection into clarity critic. Leave stub skill that delegates with deprecation notice.
8. **Sync code-toolkit agents** — copy codex.md/claude.md from cache to source
9. **Delete `insights-toolkit`** — absorbed into workflow-toolkit
10. **Clean up `claude/skills/`** — remove migrated skills, keep 12 core

### Phase 3: Slim descriptions
11. **Audit ALL skill descriptions** — user skills + local-marketplace skills. Move examples from frontmatter to body.
12. **Extract heavy body content to references/** — for skills with >50 body lines without references

### Phase 4: Context system
13. **Create 8 context templates** — in `claude/templates/contexts/`: 5 domain (writing, research, code, design, full) + 3 framework (python, web, ml). Verify typescript-lsp plugin ID exists.
14. **Create `claude-context` CLI** — custom binary. Writes to `.local.json` (REPLACES, not merges). Creates `.claude/` + `.gitignore` if needed. Warns: "Restart Claude Code to apply."
15. **Update global `settings.json`** — explicitly disable ALL non-essential plugins (including silently-loaded ones)
16. **Set dotfiles project settings** — `.claude/settings.json` with full context
17. **Add to `deploy.sh`** — deploy context templates to `~/.claude/templates/contexts/`
18. **Update both CLAUDE.md files** — global + project: document organization, profiles, `claude-context` usage

### Phase 5: Cleanup utilities
19. **Create `claude-cache-clean` CLI** — removes non-current plugin cache versions
20. **Verification testing** — run `/context` in each profile, compare token counts before/after

## Files Modified

- `claude/local-marketplace/.claude-plugin/marketplace.json`
- `claude/local-marketplace/plugins/workflow-toolkit/` (NEW)
- `claude/local-marketplace/plugins/writing-toolkit/skills/` (add strategic-communication, merge humanize-draft into review-draft)
- `claude/local-marketplace/plugins/code-toolkit/agents/` (add codex.md, claude.md from cache)
- `claude/local-marketplace/plugins/insights-toolkit/` (DELETE)
- `claude/skills/` (remove ~2 migrated skills, keep 13 core)
- `claude/settings.json` (explicit enabledPlugins for all known plugins)
- `claude/templates/contexts/` (NEW — 8 templates: writing, research, code, design, full, python, web, ml)
- `custom_bins/claude-context` (NEW)
- `custom_bins/claude-cache-clean` (NEW)
- `deploy.sh` (context template deployment)
- `.claude/settings.json` (dotfiles project: full context)
- `CLAUDE.md` (architecture + context profiles docs)

## Verification

1. Run `/context` in dotfiles repo → all local-marketplace + always-on official plugins loaded
2. `claude-context writing` in a writing project → restart → `/context` shows only writing-toolkit + document-skills + always-on
3. `claude-context code` in a code project → verify code-toolkit + coderabbit + vercel + always-on
4. Core user skills always appear regardless of profile
5. Skill token count should drop from ~9.9k to ~3-5k in focused profiles
6. `clean-skill-dupes` → no duplicates in slash picker
7. `claude-cache-clean` → stale cache versions removed
