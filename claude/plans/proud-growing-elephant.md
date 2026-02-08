# Plan: Research Config — Mechanisms Over Documentation

## Context

Grading criteria: Experimental Velocity (25%), Conceptual Understanding (25%), Correctness/Validity (25%), Reasoning Transparency (25%).

The existing infrastructure is already strong — 3,700+ lines across docs, rules, and agents covering CI standards, pre-run validation (in `research-engineer.md:99-167`), de-risking ladder, and research-skeptic red-teaming. Three independent critics (research-advisor, codex, gemini) agreed the original plan was ~70% documentation theater.

**Diagnosis**: The grading criteria reward OUTPUTS (experiments run, understanding communicated, correct results, transparent reasoning). The fix is output format constraints and behavioral enforcement, not more methodology prose.

**Reasoning Transparency insight** (from [Coefficient Giving article](https://coefficientgiving.org/research/reasoning-transparency/)): RT ≠ "showing your work" (transparent methodology). RT = transparent *epistemology* — what do you actually know, how confident, what's the evidence type, what would change your mind? This concept is genuinely absent from the config.

## Changes (3 files, ~60 lines net)

### 1. Complete TODO in `claude/rules/workflow-defaults.md` (lines 62-69 → ~12 lines)

**Why**: Only incomplete item in an auto-loaded rule file. Actually changes behavior since rules are in every session's context.

Replace the TODO block with:
```
**Checkpoint format** (inline, not a separate document):
1. **Current state**: What the code does now (1-2 sentences)
2. **Goal mapping**: How planned changes achieve the objective
3. **Risky assumptions**: What I'm assuming that could be wrong (explicit list)
4. **Scope**: Files that will be touched

**Skip when**: Single-file change, code already read this session, or user says "just do it"
```

### 2. Add mandatory Trust Calibration output to `claude/local-marketplace/plugins/research-toolkit/agents/data-analyst.md` (~25 lines)

**Why**: This is a behavioral constraint, not documentation. Every analysis output must include this section — it cannot be omitted. This structurally enforces reasoning transparency at the point of output.

**a)** Add to OUTPUT FORMAT (after "Recommendations"), a new mandatory section:

```
**Trust Calibration** (MANDATORY — never omit)
- Confidence: [high/medium/low] — because [specific reason]
- Load-bearing evidence: Which findings most critically support the conclusion?
- Limitations: What this analysis cannot show
- Uncontrolled confounds: [list, with why each is acceptable or not]
- Fragility: Would the conclusion change if [outliers removed / different aggregation / subset dropped]?
- What would change the conclusion: [specific result or evidence]
```

**b)** Make existing step 8 "Check Robustness" concrete. Replace the vague bullet with:

```
8. **Sensitivity Check** (MANDATORY for every main finding): Run at least one:
   (a) Drop top/bottom 5% outliers — does conclusion hold?
   (b) Alternative aggregation (median vs mean, or different grouping) — same direction?
   (c) Subset analysis — consistent across subgroups (models, datasets, time periods)?
   If conclusion changes under any check, flag as FRAGILE in Trust Calibration.
```

**c)** Add to BEHAVIORAL TRAITS:
```
- Epistemically transparent: Reports what kind of evidence supports each claim (empirical, inference, assumption) and how much effort went into the analysis
```

**d)** Extend `ci-standards.md` Section 5 "Small-n Groups" with a brief negative results note (~8 lines):

```
## 7. Sensitivity & Robustness

After computing main results, check at least one:
- Drop outliers (top/bottom 5%): same conclusion?
- Alternative aggregation (median, trimmed mean): same direction?
- Subset analysis: consistent across subgroups?

If conclusion changes → report as fragile. Always state which checks were run.

## 8. Reporting Null Results

Non-significant ≠ no effect. When reporting null findings:
- Report the CI of the difference (not just "p > 0.05")
- State the detectable effect size at your N (power analysis)
- Example: "No significant difference (Δ = 1.2pp, 95% CI: [-2.1, 4.5], N=200, powered to detect ≥6pp)"
```

### 3. Add reasoning transparency concept to `claude/docs/research-methodology.md` (~15 lines)

**Why**: This is genuinely new knowledge from the [Coefficient Giving article](https://coefficientgiving.org/research/reasoning-transparency/). The concept of epistemological transparency (vs methodological transparency) doesn't exist anywhere in the config. This is a reference doc read by agents, not aspirational prose.

Add after "Correctness & Truth-Seeking" section:

```
## Reasoning Transparency

Transparent methodology (showing methods) ≠ transparent epistemology (showing what you know and don't know).

For every claim in a writeup, be clear about:
- **Evidence type**: Empirical result, inference from data, assumption, or intuition?
- **Confidence**: How certain, and why? ("70% confident because N is small" not just "plausible")
- **Load-bearing vs peripheral**: Which findings actually drive the conclusion?
- **What would change your mind**: What result or evidence would flip the conclusion?
- **Process disclosure**: How much effort went into this? ("Spent 2 hours on 3 experiments" vs "3-month study")

Anti-patterns: Presenting all evidence as equally important. Burying key limitations. Stating conclusions without confidence calibration. Citing without specifying which claim the citation supports.

Reference: https://coefficientgiving.org/research/reasoning-transparency/
```

## What this does NOT touch (and why)

| Proposed in v1 | Why killed |
|----------------|-----------|
| `pre-run-validation.md` (new file) | Already exists as 70-line checklist in `research-engineer.md:99-167` |
| `experiment-designer.md` extensions | Already has confound/control/baseline guidance; additions would restate existing capabilities |
| `research-skeptic.md` extensions | Already checks CIs, confounds, cherry-picking, selective reporting — adding "Reasoning Transparency Audit" duplicates existing step 5 (Statistical Skepticism) |
| Velocity docs | Velocity comes from tooling (caching, templates, de-risk ladder) not prose about "target speed" |
| Pre-registration protocol | Operationalize via git timestamps, not a methodology doc |

## Files to modify

| File | Action | Lines |
|------|--------|-------|
| `claude/rules/workflow-defaults.md` | EDIT lines 62-69 | ~12 |
| `claude/local-marketplace/.../data-analyst.md` | EXTEND output format + step 8 | ~25 |
| `claude/docs/ci-standards.md` | ADD sections 7-8 | ~15 |
| `claude/docs/research-methodology.md` | ADD section after line 18 | ~15 |
| **Total** | | **~67 lines** |

## Verification

1. Read each modified file end-to-end — check coherence with surrounding content
2. Grep for "Trust Calibration" in data-analyst.md — confirm it's in OUTPUT FORMAT (behavioral, not aspirational)
3. Grep for "sensitivity" in ci-standards.md — confirm it's actionable (run X, check Y) not educational
4. Verify workflow-defaults.md no longer has TODO(human) — clean resolution
5. Check no duplication with existing content in research-engineer.md, research-skeptic.md

## How this addresses each criterion

| Criterion | Mechanism (not documentation) |
|-----------|------------------------------|
| **Experimental Velocity** | No change needed — existing de-risk ladder + tmux + caching already strong. Velocity is tooling, not docs. |
| **Conceptual Understanding** | Mid-checkpoint format forces Claude to demonstrate understanding before writing code (rule change, always in context) |
| **Correctness/Validity** | Mandatory sensitivity check in data-analyst ensures robustness is tested, not assumed. Null results guidance prevents "p > 0.05 → no effect" fallacy |
| **Reasoning Transparency** | Mandatory Trust Calibration output section + RT concept in methodology. Every analysis output must state confidence, evidence type, limitations, and what would change the conclusion |
