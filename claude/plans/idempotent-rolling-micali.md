# Plan: Make Pairwise KDE Plots the Standard

## Summary

Document `scripts/generate_pairwise_plots.py` as the canonical way to generate KDE comparison plots, ensuring plots always show paired comparisons (sandbagging vs benign) rather than individual distributions.

## Problem

Current classifier plotting assumes both classes exist within each `model_pair`, but experiments are often run separately (sandbagging runs vs benign runs), resulting in single-distribution plots that aren't informative.

## Changes

### 1. Create README for the script

**File**: `scripts/README_generate_pairwise_plots.md`

Contents:
- Purpose: Generate paired KDE comparisons from score CSVs
- Usage example with actual paths
- Output structure (same_model/ vs cross_model/)
- Model pair naming convention (`{base}_sandbag_{prompt}` vs `{base}_normal`)
- Statistics shown (mean, std, Cohen's d)

### 2. Update CLAUDE.md

**File**: `CLAUDE.md`

Add under "Extended Documentation" section:
```markdown
- `scripts/README_generate_pairwise_plots.md`: Pairwise KDE plot generation (sandbagging vs benign)
```

Add a note in the "Detection Methods Details" section or create a new "Visualization" section pointing to this as the standard KDE plotting approach.

### 3. Add classifier docstring hints (optional)

In classifier scripts that generate CSVs, add a brief comment noting that for paired KDE plots, use `generate_pairwise_plots.py` on the output CSVs.

## Files to Modify

1. `scripts/README_generate_pairwise_plots.md` (create)
2. `CLAUDE.md` (edit - add documentation reference)

## Verification

1. Run `generate_pairwise_plots.py` on existing score CSVs to confirm it works
2. Check README renders correctly
3. Verify CLAUDE.md reference is accurate
