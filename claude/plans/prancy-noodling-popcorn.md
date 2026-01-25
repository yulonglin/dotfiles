# Plan: Refactor Skills to Follow Best Practices

## Understanding (from official Claude Code docs)

**How skill loading works:**
- **Startup**: Only name + description loaded (minimal tokens)
- **Activation**: Full SKILL.md loaded when skill is invoked
- **Progressive disclosure**: Reference files loaded only when Claude follows links

**Official recommendation**: Keep SKILL.md **<500 lines**, link to detailed reference material.

## Goal
Refactor skills to follow progressive disclosure pattern:
1. Keep SKILL.md lean (<500 lines) with core workflow
2. Link to separate reference files for templates/examples/checklists
3. Claude loads reference files only when needed during execution

## Current State

| Skill | Current Lines | Target | What to Extract |
|-------|---------------|--------|-----------------|
| reproducibility-report | 430 | ~150 | Template, checklists, LLM-specific |
| research-presentation | 362 | ~150 | Templates, visualization guide, mistakes |
| read-paper | 163 | ~70 | Examples, response template |
| strategic-communication | 272 | ~120 | Common scenarios (already has references/) |

## Tasks

### 1. reproducibility-report
**Current**: 430 lines → **Target**: ~150 lines

**Keep in SKILL.md**:
- Frontmatter + when to use
- Fundamental principles (4 principles)
- Workflow overview (3 steps)
- Links to reference files

**Move to references/**:
- `template.md` - Full report template (~190 lines)
- `checklist.md` - Validation checklists (~50 lines)
- `llm-specific.md` - Provider metadata, caching (~40 lines)

### 2. research-presentation
**Current**: 362 lines → **Target**: ~150 lines

**Keep in SKILL.md**:
- Frontmatter + when to use
- Core principles (5 principles)
- Visualization decision framework

**Move to references/**:
- `templates.md` - Email + slide templates (~55 lines)
- `visualization-guide.md` - Experiment types, best practices (~50 lines)
- `common-mistakes.md` - Anti-patterns (~30 lines)

### 3. read-paper
**Current**: 163 lines → **Target**: ~70 lines

**Keep in SKILL.md**:
- Frontmatter + when to use
- Fundamental principles
- Brief framework overview

**Move to references/**:
- `analysis-framework.md` - Detailed examples for each framework section (~70 lines)
- `response-template.md` - Response structure template (~25 lines)

### 4. strategic-communication
**Current**: 272 lines (already has references/) → **Target**: ~120 lines

**Keep in SKILL.md**:
- Frontmatter + when to use
- Foundation (tactical empathy)
- Core workflow (5 steps)
- Tips

**Move to references/** (add to existing):
- `scenarios.md` - Common scenarios: rental, salary, work, backing out (~65 lines)

## Files to Modify

**reproducibility-report/**:
- Edit: `~/.claude/skills/reproducibility-report/SKILL.md`
- Create: `references/template.md`, `references/checklist.md`, `references/llm-specific.md`

**research-presentation/**:
- Edit: `~/.claude/skills/research-presentation/SKILL.md`
- Create: `references/templates.md`, `references/visualization-guide.md`, `references/common-mistakes.md`

**read-paper/**:
- Edit: `~/.claude/skills/read-paper/SKILL.md`
- Create: `references/analysis-framework.md`, `references/response-template.md`

**strategic-communication/**:
- Edit: `~/.claude/skills/strategic-communication/SKILL.md`
- Create: `references/scenarios.md`

## Execution Order
1. reproducibility-report (largest, most benefit)
2. research-presentation
3. read-paper
4. strategic-communication (smallest change, already has references/)
5. Verify all SKILL.md files are under 200 lines
