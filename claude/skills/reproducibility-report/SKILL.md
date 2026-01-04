---
name: reproducibility-report
description: Generate reproducibility reports for LLM/ML experiments. Use when (1) completing an experiment, (2) sharing results with collaborators, (3) preparing for publication, (4) archiving experiment runs, or (5) user asks for reproducibility documentation. Auto-extracts from code/configs/Hydra, asks for gaps.
---

# Reproducibility Report Generator

Generate comprehensive reproducibility reports for ML/LLM experiments. Based on requirements from [NeurIPS Paper Checklist](https://neurips.cc/public/guides/PaperChecklist), [ACL Responsible NLP Research](http://aclrollingreview.org/responsibleNLPresearch/), and [ML Reproducibility Checklist](https://www.cs.mcgill.ca/~jpineau/ReproducibilityChecklist.pdf).

## When to Use This Skill

Trigger after:
- Completing an experiment or series of related experiments
- Before sharing results with collaborators
- Before writing up findings for publication
- When archiving experiment runs

## Fundamental Principles

**Completeness Over Convenience**: A reproducibility report should contain everything needed to replicate results, even if some information seems obvious. Future you (or a collaborator) will thank present you.

**Extract, Don't Fabricate**: Auto-extract from code, configs, and logs. For anything missing, ask explicitly rather than assuming or inventing values. Leave `{placeholder}` markers for unknown items.

**Prioritize Critical Information**: Not all reproducibility concerns are equal. Model identity and prompts are critical; compute costs are helpful but not essential. Focus effort on what would block replication.

**Document the Delta**: If this experiment differs from a baseline or prior run, explicitly note what changed and why.

## Workflow

### 1. Auto-Extract Information

Automatically gather reproducibility information from:

**Code & Configs:**
- `src/configs/` - Hydra config files (model, task, prompts)
- `src/configs/prompts/` - Full prompt templates
- `.hydra/config.yaml` and `.hydra/overrides.yaml` in output dirs
- Python files for sampling parameters, API calls, caching logic

**Experiment Outputs:**
- `out/*/` directories - Hydra logs, results.jsonl
- `.cache/` directory structure - Caching strategy evidence

**Environment:**
- `pyproject.toml` or `requirements.txt` - Dependencies
- Git commit hash and dirty state

### 2. Ask Targeted Questions for Gaps

For any missing critical information, ask the user directly. See `references/checklist.md` for common gaps to ask about.

### 3. Generate Report

Write to: `out/{experiment_dir}/reproducibility.md`

Use the template in `references/template.md`.

## Reference Files

- **`references/template.md`** - Full report template with all sections
- **`references/checklist.md`** - Validation checklists (Critical/Important/Helpful) and common gaps
- **`references/llm-specific.md`** - LLM reproducibility concerns, provider metadata tables

## Quick Reference

When generating a report, prioritize:

1. **Model identity** - Exact ID with version suffix, not aliases like "gpt-4" or "claude-3-sonnet"
2. **Full prompts** - Verbatim, including whitespace and special characters
3. **Data paths and versions** - Exact file paths, dataset versions, commit hashes
4. **Exact reproduction command** - Copy-pasteable, including all flags and overrides
5. **Known limitations** - What assumptions might not hold in practice?

**Always ask for:**
- API costs (approximate is fine)
- Unstated assumptions
- Failed approaches that were tried
- Prompt iteration history (if relevant)
