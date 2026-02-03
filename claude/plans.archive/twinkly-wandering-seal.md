# Plan: CLAUDE.md Tiered Restructuring

## Goal
Reduce CLAUDE.md from 868 lines to ~200 lines by extracting detailed content to ai_docs/, while keeping critical information prominent and easy to navigate.

## New Structure

### Tier 1: CLAUDE.md (~200 lines)
**Purpose**: Quick reference + critical warnings

```
1. Project Overview (5 lines) - unchanged
2. **NEW: Quick Navigation / TOC** (15 lines)
3. **NEW: Critical Warnings Box** (20 lines)
   - --multirun requirement
   - k-samples matching
   - Level 5 MATH only
   - .eval files: use read_eval_log
4. Quick Reference (50 lines) - condensed from 217
   - 1 example per workflow (trajectory, classifier, judge)
   - Link to CLI_REFERENCE.md for full commands
5. Architecture Overview (30 lines) - condensed from 93
   - Keep directory structure
   - Link to detailed patterns in ai_docs/
6. Detection Methods Summary (25 lines) - condensed from 49
   - 2-3 lines per method + link to methods/
   - Decision table: "Which method to use?"
7. Key References (15 lines)
   - Dataset counts table (condensed)
   - Links to detailed docs
8. Configuration Essentials (15 lines) - condensed from 44
9. Troubleshooting Quick Reference (15 lines) - condensed from 36
10. Links to Detailed Documentation (10 lines)
```

### Tier 2: New ai_docs/ Files

#### New Directory: `ai_docs/core/`
Create a `core/` subdirectory for essential reference documents that are:
- Frequently referenced during development
- Stable (not findings/explorations)
- Necessary for running experiments correctly

This distinguishes them from:
- `ai_docs/` root: Research findings, analyses, weekly updates
- `ai_docs/methods/`: Detection method deep-dives
- `ai_docs/archive/`: Outdated content

**Structure:**
```
ai_docs/
├── core/                    # NEW: Essential reference docs
│   ├── README.md           # Index with links
│   ├── CLI_REFERENCE.md    # Full command reference
│   └── STATISTICAL_ANALYSIS.md  # CV, reporting, hyperparameters
├── methods/                 # Detection method guides (existing)
├── archive/                 # Outdated content (existing)
└── [findings, analyses]     # Root level (existing)
```

#### 1. `ai_docs/core/CLI_REFERENCE.md` (~300 lines)
**Content extracted from CLAUDE.md:**
- Lines 84-127: Full classifier command examples
- Lines 129-201: Per-model-pair analysis examples
- Lines 235-263: Maintenance utilities, .eval file handling
- Add parameter reference tables for each classifier

**Structure:**
```markdown
# CLI Reference

## Trajectory Generation
[Full examples with all common overrides]

## Classifiers
### Lie Detector
[Full command + parameter table]

### Embedding Entropy
[Full command + parameter table]

### Behavioral Probes
[Full command + parameter table]

### Trusted Monitoring
[Full command + parameter table]

## Per-Model-Pair Analysis
[Full bootstrap CV examples with all modes]

## Maintenance
[Cleanup utilities, .eval file handling]
```

#### 2. `ai_docs/core/STATISTICAL_ANALYSIS.md` (~200 lines)
**Content extracted from:**
- Lines 463-473: Cross-validation modes
- Lines 687-716: Multi-sample classification (k-samples)
- Lines 718-764: Statistical analysis methodology
- Lines 768-831: Reporting requirements and hyperparameters

**Structure:**
```markdown
# Statistical Analysis Guide

## Cross-Validation Modes
[kfold, split, bootstrap explanations]

## Multi-Sample Classification
[What k means, constraints, recommendations]

## Development vs Paper Results
[Different error reporting for each stage]

## Reporting Requirements
[Hyperparameter matching table - the big one from lines 772-789]
```

#### 3. Expand existing `ai_docs/methods/README.md`
The current file has stub entries for Embedding Entropy and Lie Detection (lines 47-57).

**Expand with content from CLAUDE.md:**
- Lines 633-657: Lie detector variants ("which to report": 4.1-nano+5-nano, alternative, subsets_union)
- Lines 599-631: Embedding entropy static vs runtime details
- Lines 434-446: Vendi score / strategy diversity

**Specifically, expand these stubs:**

Current (line 47-51):
```markdown
### 3. Embedding Entropy (Paraphrase Variance)
**Type:** Statistical analysis
**Signal:** Variance in embeddings across paraphrased questions
**Documentation:** See existing scripts and configs
```

Expand to include:
- Static vs runtime paraphrasing trade-off
- Recommended strategies (5 diversity-optimized)
- Key flags (--message-selection 1, --allow-unknown-strategies)

Current (line 53-57):
```markdown
### 4. Lie Detection
**Type:** Follow-up interrogation
**Signal:** Detecting lies in responses to probe questions
**Documentation:** See existing lie detector configs
```

Expand to include:
- Which variants to report (4.1-nano+5-nano as default)
- Why subsets_union doesn't work (~0% detection)
- Invalid response handling

### Tier 3: Archive Old Content
Move to `ai_docs/archive/`:
- Nothing to archive - content is being reorganized, not deleted

## Content Migration Map

| CLAUDE.md Lines | Destination | Notes |
|-----------------|-------------|-------|
| 1-34 | Keep | Overview, goals, slide guidelines |
| 36-82 | **Condense** → 30 lines | Keep 1 example each, link to CLI_REFERENCE |
| 84-201 | **Move** → CLI_REFERENCE.md | Full classifier commands |
| 203-233 | **Condense** → 10 lines | Testing, code quality (just commands) |
| 235-263 | **Move** → CLI_REFERENCE.md | Maintenance, .eval handling |
| 265-357 | **Keep** (condensed) | Architecture stays but trimmed |
| 359-402 | **Condense** → 15 lines | Config essentials only |
| 404-411 | Keep | Caching (already short) |
| 413-461 | **Condense** → 25 lines | Method summaries + links |
| 463-473 | **Move** → STATISTICAL_ANALYSIS.md | CV modes |
| 475-514 | **Condense** → table | Dataset counts (keep table) |
| 516-544 | Keep | Data flow, notes, research context |
| 546-586 | **Condense** → links | Workflows, docs (just references) |
| 588-831 | **Move** → methods/README.md + STATISTICAL_ANALYSIS.md | Critical experiment notes |
| 833-868 | **Condense** → 15 lines | Quick troubleshooting |

## Critical Information to Promote

These must appear in first 50 lines of new CLAUDE.md:

1. **--multirun flag**: Currently line 365, move to Critical Warnings box
2. **k-samples matching**: Currently line 770, move to Critical Warnings box
3. **Level 5 MATH only**: Currently line 489, move to Critical Warnings box
4. **read_eval_log requirement**: Currently lines 261, 530, consolidate in Critical Warnings

## New CLAUDE.md Outline

```markdown
# CLAUDE.md

## Project Overview
[5 lines - unchanged]

## Quick Navigation
- [Quick Reference](#quick-reference) - Common commands
- [Detection Methods](#detection-methods) - Method selection
- [Troubleshooting](#troubleshooting) - Common issues

**Core Reference Docs:**
- `ai_docs/core/CLI_REFERENCE.md` - Full command reference
- `ai_docs/core/STATISTICAL_ANALYSIS.md` - CV, reporting, hyperparameters
- `ai_docs/methods/` - Detection method deep-dives

## Critical Warnings

> **--multirun flag**: REQUIRED when config has `sweep.*` parameters
>
> **k-samples matching**: All methods in a comparison must use same k
>
> **Dataset**: Use MATH Level 5 only (not L4+5)
>
> **.eval files**: Use `read_eval_log()`, never cat/head/tail

## Quick Reference
### Run Trajectory Generation
[single example + link]

### Run Classifier
[single example + link]

### Run Judge
[single example + link]

## Detection Methods
| Method | Use When | Cost | Link |
|--------|----------|------|------|
| Embedding Entropy | ... | Low | [details](ai_docs/methods/README.md#embedding-entropy) |
| Lie Detector | ... | Medium | [details](ai_docs/methods/README.md#lie-detector) |
| Behavioral Probes | ... | Low | [details](ai_docs/methods/README.md#behavioral-probes) |
| Trusted Monitoring | ... | High | [details](ai_docs/methods/README.md#trusted-monitoring) |

[Rest of condensed content...]
```

## Files to Create/Modify

1. **Create**: `ai_docs/core/README.md` (~30 lines) - Index for core docs
2. **Create**: `ai_docs/core/CLI_REFERENCE.md` (~300 lines)
3. **Create**: `ai_docs/core/STATISTICAL_ANALYSIS.md` (~200 lines)
4. **Modify**: `ai_docs/methods/README.md` - expand Embedding Entropy & Lie Detector stubs
5. **Rewrite**: `CLAUDE.md` - new streamlined structure (~200 lines)

## Verification

1. All commands from old CLAUDE.md still findable (via search or navigation)
2. Critical warnings visible in first 50 lines
3. No broken links
4. Total ai_docs/ additions: ~500 lines
5. CLAUDE.md reduction: 868 → ~200 lines (77% reduction)

## Implementation Order

1. Create `ai_docs/core/` directory
2. Create `ai_docs/core/README.md` (index)
3. Create `ai_docs/core/CLI_REFERENCE.md` with extracted commands
4. Create `ai_docs/core/STATISTICAL_ANALYSIS.md` with extracted methodology
5. Update `ai_docs/methods/README.md` with expanded method details
6. Rewrite CLAUDE.md with new streamlined structure
7. Verify all cross-references work
