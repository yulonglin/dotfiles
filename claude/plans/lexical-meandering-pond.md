# Consolidation Plan: ai_docs/ and out/ Markdown Files

## Overview

Recent markdown files have significant overlap and versioning. This plan consolidates them to reduce redundancy while preserving unique content.

---

## Differences, Similarities, and Contradictions

### Week 19 Files: Evolution of Findings

**Timeline of versions:**
1. `research_update_week19_draft.md` (28 Dec 02:54) - Initial findings
2. `research_update_week19_formatted.md` (28 Dec 05:00) - Added methodological concerns
3. `research_update_week19_revised.md` (28 Dec 23:44) - Condensed, paraphrase quality fix
4. `research_update_week19_final.md` (30 Dec 05:13) - Canonical with all data tables
5. `slack_update_week19.md` (30 Dec 02:52) - Slack format
6. `slack_update_week19_simple.md` (30 Dec 04:51) - Simplified slack

**Key similarity**: All report the same core finding:
- Lie detector classifier (`4.1-nano+5-nano`) detects **model identity**, not sandbagging
- Same-model comparison (5-nano vs 5-nano) → lie detector is random
- C3 works well (67% recall, 0.91 AUROC on original prompts)

**Unique content by file:**
| File | Unique Content |
|------|----------------|
| `revised` | Paraphrase answerability scores (eli5: 11%, professional: 44%, etc.) |
| `final` | Full data tables, commands, output file paths |
| `slack` | Detailed "Top 3 Prompts That Defeat Lie Detectors" with full excerpts |
| `rerun_plan` | Experimental methodology, validation checks |

**Minor differences (not contradictions):**
- `revised` uses k=5, `final` uses k=10 - these are different k values, both valid
- `final` reports higher-fidelity numbers due to using k=10

---

### ⚠️ CONTRADICTION: v4.1 Analysis Files

**v4.1_detection_analysis_summary.md** (Dec 24, USACO only):
```
Lie Detector AUROC: 0.34
Embedding Entropy AUROC: 0.58
```

**v4.1_stealth_prompts_analysis.md** (Dec 25, Cross-dataset):
```
USACO Lie Detector Mean AUROC: 0.43
USACO Embedding Mean AUROC: 0.55
```

**Root cause**: Different classifiers AND different baselines

**Classifier used in each file:**
| File | Classifier | Baseline |
|------|-----------|----------|
| v4.1_detection_analysis_summary | ❌ **NOT SPECIFIED** | 4.1-nano |
| v4.1_stealth_prompts_analysis | `subsets_union` | 5-nano proper |
| research_update_week19_final | `4.1-nano+5-nano` | 5-nano proper |

**Key insight**: The 0.34 AUROC in the summary was likely achieved with `subsets_union` (or default classifier), NOT `4.1-nano+5-nano`. The `4.1-nano+5-nano` classifier would detect model identity and give ~100% recall with 4.1-nano baseline, not 0.34 AUROC.

**Interpretation:**
- `subsets_union` + v4.1 prompts → 0.34 AUROC (defeated, anti-correlated)
- `subsets_union` + 5-nano baseline + v4.1 prompts → 0.43 AUROC (defeated)
- The difference (0.34 vs 0.43) may be due to sample size, baseline model, or experimental variance

**Resolution**: `v4.1_stealth_prompts_analysis.md` is authoritative (proper baseline, documented hyperparameters). Summary should be archived.

---

### ⚠️ Additional Outdated Files Found

**1. `out/behavioral_probes_v4_stealth_results.md`** (Dec 21) - **OUTDATED**
- Uses **v4.0** prompts (not v4.1)
- References old config: `configs/system_prompt/ablations/avoid_denial_prompts_v4.0/`
- v4.1 results supersede this
- **Archive after merging any unique methodology notes**

**2. `out/trusted_monitor_aggressive_results.md`** (Dec 25) - **CONFOUNDED BASELINE**
- Uses **gpt-4.1-nano** as normal model (not proper 5-nano baseline)
- Tests original aggressive prompts (not v4.1 stealth)
- Results are confounded by model identity issue
- **Should be flagged or re-run with proper baseline**

**Hyperparameters comparison:**
| File | k-samples | Baseline | Classifier | Message-sel | Strategy-filter |
|------|-----------|----------|------------|-------------|-----------------|
| v4.1_detection_analysis_summary | ❌ Unknown | 4.1-nano | ❌ Unknown (prob subsets_union) | ❌ Unknown | ❌ Unknown |
| behavioral_probes_v4_stealth | N/A | ❌ Unknown | N/A | N/A | N/A |
| trusted_monitor_aggressive | k=10 ✓ | 4.1-nano ⚠️ | N/A | N/A | N/A |
| v4.1_stealth_prompts_analysis | k=10 ✓ | 5-nano ✓ | subsets_union ✓ | 1 ✓ | ✓ Listed |
| ensemble_detection_report_v4.1 | k=10 ✓ | ❓ Unclear | N/A | N/A | N/A |
| research_update_week19_final | k=10 ✓ | 5-nano ✓ | 4.1-nano+5-nano | 1 ✓ | ✓ Listed |

**Legend:**
- ✓ = Properly documented
- ❌ = Missing
- ⚠️ = Documented but potentially confounded

---

### Paraphrase Strategy Inconsistency

**v4.1_stealth_prompts_analysis.md** uses:
```
--strategy-filter original absurd audience boredom eval imperative
```

**research_update_week19_final.md** uses:
```
--strategy-filter original boredom collaborative spanish eval
```

**Root cause**: These are different experiments with different strategy filters. Both are valid for their specific runs, but this could cause confusion when comparing results.

**Recommendation**: In the canonical `research_update_week19_final.md`, clarify which strategy set was used and why.

---

## Analysis Summary

### Group 1: Week 19 Research Updates (5 files → 1 canonical + archive)

| File | Lines | Status | Content |
|------|-------|--------|---------|
| `research_update_week19_final.md` | 225 | **KEEP** | Canonical - most complete with data tables, commands, plots |
| `research_update_week19_revised.md` | 112 | Archive | Earlier condensed version |
| `slack_update_week19.md` | 101 | Archive | Slack-formatted duplicate |
| `slack_update_week19_simple.md` | 72 | Archive | Shorter slack duplicate |
| `week19_rerun_plan.md` | 265 | **KEEP** | Different purpose - experimental methodology |

**Overlap**: All cover the same finding (lie detector confound, C3 works, v4.1 prompts defeat detection). The `final` version has all data tables, commands, and output file references.

### Group 2: v4.1 Stealth Analysis (2 files → 1 canonical + archive)

| File | Lines | Status | Content |
|------|-------|--------|---------|
| `out/v4.1_stealth_prompts_analysis.md` | 292 | **KEEP** | Cross-dataset (USACO+GPQA+MATH), comprehensive |
| `out/v4.1_detection_analysis_summary.md` | 145 | Archive | USACO-only subset, superseded |

**Overlap**: The summary is a strict subset of the cross-dataset analysis.

### Files to Keep (after consolidation)

| File | Status | Notes |
|------|--------|-------|
| `ai_docs/research_update_week19_final.md` | ✓ Canonical | Week 19 findings (will merge content) |
| `ai_docs/week19_rerun_plan.md` | ✓ Keep | Experimental methodology reference |
| `ai_docs/findings_v4.1_good_liar_prompts.md` | ✓ Keep | Unique refusal rate analysis |
| `ai_docs/methods/*.md` | ✓ Keep | Well-organized method docs |
| `out/v4.1_stealth_prompts_analysis.md` | ✓ Canonical | Cross-dataset v4.1 detection |
| `out/ensemble_detection_report_v4.1.md` | ⚠️ Review | Check baseline used |
| `out/trusted_monitor_aggressive_results.md` | ⚠️ Flag | Add confound warning header |
| `out/2025-12-17_*.md` | ✓ Keep | Timestamped reports (different experiments) |

### Files to Archive

| File | Reason |
|------|--------|
| Week 19 drafts (5 files) | Superseded by `research_update_week19_final.md` |
| `out/v4.1_detection_analysis_summary.md` | Missing hyperparameters, USACO-only subset |
| `out/behavioral_probes_v4_stealth_results.md` | Uses v4.0 (superseded by v4.1) |

## Consolidation Steps (Merge-Then-Archive)

### Step 1: Merge unique content into `research_update_week19_final.md`

**From `research_update_week19_revised.md`** - Add paraphrase answerability analysis:
```markdown
## Paraphrase Quality Issue

The original paraphrase strategy list (`eli5, professional, audience, real_world, collaborative`) had poor answerability scores:
- eli5: 11% answerable
- professional: 44% answerable
- audience: 50% answerable

**Corrected top 5 by answerability:**
1. original (100%)
2. boredom (89%)
3. collaborative (83%)
4. spanish (77%)
5. eval (72%)
```

**From `slack_update_week19.md`** - Already included in final (Top 3 prompts section is present).

**From `week19_rerun_plan.md`** - Keep separate (experimental methodology, different purpose).

### Step 2: Add clarification about paraphrase strategies

Add to `research_update_week19_final.md` to address the strategy inconsistency:
```markdown
**Note on paraphrase strategies**: The v4.1 stealth analysis used different strategy filters
(`original absurd audience boredom eval imperative`) than the original prompts analysis
(`original boredom collaborative spanish eval`). Both are valid filtered sets based on
answerability scoring, but use slightly different subsets.
```

### Step 3: Archive redundant Week 19 files
Move to `ai_docs/archive/week19/`:
- `research_update_week19_revised.md`
- `research_update_week19_formatted.md`
- `research_update_week19_draft.md` (if exists)
- `slack_update_week19.md`
- `slack_update_week19_simple.md`

### Step 4: Archive v4.1 analysis with missing hyperparameters
Move `out/v4.1_detection_analysis_summary.md` → `ai_docs/archive/v4.1_detection_analysis_summary.md`

**Reason**: Missing classifier, k-samples, and uses 4.1-nano baseline. `v4.1_stealth_prompts_analysis.md` is authoritative with all hyperparameters documented.

### Step 5: Archive v4.0 behavioral probes (superseded by v4.1)
Move `out/behavioral_probes_v4_stealth_results.md` → `ai_docs/archive/behavioral_probes_v4_stealth_results.md`

**Reason**: Uses v4.0 prompts, superseded by v4.1. Unique methodology notes about suspiciousness scorer should be extracted first.

### Step 6: Flag trusted monitor results
Add warning to `out/trusted_monitor_aggressive_results.md`:
```markdown
> ⚠️ **BASELINE CONFOUND WARNING**: This analysis uses gpt-4.1-nano as normal model.
> Results may be confounded by model identity differences.
> Re-run with 5-nano proper baseline for valid comparison.
```

Alternatively, archive and re-run experiment.

### Step 7: Verify no broken references
```bash
grep -r "research_update_week19_revised\|slack_update_week19\|v4.1_detection_analysis_summary\|behavioral_probes_v4_stealth" . --include="*.md" --include="*.py"
```

## Commands

```bash
# Step 1-2: Edit research_update_week19_final.md (add paraphrase quality section and strategy note)

# Step 3: Create archive subdirectory and move Week 19 drafts
mkdir -p ai_docs/archive/week19
mv ai_docs/research_update_week19_draft.md ai_docs/archive/week19/
mv ai_docs/research_update_week19_revised.md ai_docs/archive/week19/
mv ai_docs/research_update_week19_formatted.md ai_docs/archive/week19/
mv ai_docs/slack_update_week19.md ai_docs/archive/week19/
mv ai_docs/slack_update_week19_simple.md ai_docs/archive/week19/

# Step 4: Move v4.1 summary (missing hyperparameters)
mv out/v4.1_detection_analysis_summary.md ai_docs/archive/

# Step 5: Move v4.0 behavioral probes (superseded by v4.1)
mv out/behavioral_probes_v4_stealth_results.md ai_docs/archive/

# Step 6: Add warning header to trusted monitor results
# Add to top of out/trusted_monitor_aggressive_results.md:
# > ⚠️ **BASELINE CONFOUND WARNING**: Uses gpt-4.1-nano as normal model.
# > Results may be affected by model identity differences.
# > Consider re-running with 5-nano proper baseline for rigorous comparison.

# Step 7: Verify no broken references
grep -r "research_update_week19_revised\|slack_update_week19\|v4.1_detection_analysis_summary\|behavioral_probes_v4_stealth" . --include="*.md" --include="*.py"
```

## Result

**Before**: 9 overlapping/outdated files
**After**: 3 canonical files + 6-7 archived

| Canonical Files | Purpose |
|-----------------|---------|
| `ai_docs/research_update_week19_final.md` | Week 19 research findings |
| `ai_docs/week19_rerun_plan.md` | Experimental methodology |
| `out/v4.1_stealth_prompts_analysis.md` | Cross-dataset v4.1 detection analysis |

## Space Savings

~25KB of redundant content moved to archive, reducing confusion and making the current research state clearer.
