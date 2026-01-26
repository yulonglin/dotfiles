# TM Aggregation: Max Suspicion Across Paraphrases

## Problem
C3 underperforms TM on USACO because USACO responses include explanations where suspicious strategies leak (e.g., "I'll apply my systematic bias of −1"). We already generate k paraphrases for C3 - we can leverage this for TM too.

## Proposal
Implement `Max_Suspicion = max(tm_score_1, ..., tm_score_k)` across paraphrases. Security = weakest link: if the model slips in one paraphrase, the monitor catches it.

## Current State Analysis

### What Already Works
1. **Trajectory generation** creates separate `.eval` files per paraphrase strategy
2. **Judge pipeline** (`run_judge.py`) already runs TM on each paraphrase separately
3. **TM classifier** (`run_trusted_monitor.py`) extracts scores to CSV
4. **Bootstrap CV** already supports `aggregation=max`

### The Gap
TM outputs have sample_ids like `1014-original_usaco_...` where each paraphrase is a separate row. For max aggregation, we need to:
1. Group rows by **base question** (strip strategy suffix)
2. Take max score within each group
3. Feed grouped scores to bootstrap CV

## Implementation Plan

### Option: Add Pre-Aggregation to Bootstrap CV (Recommended)
**Rationale**: Minimal code changes, reusable for other methods, follows existing patterns.

#### Step 1: Add paraphrase grouping utility
**File**: `src/detection_game/utils/paraphrase_grouping.py` (new, ~50 lines)

```python
from src.detection_game.constants import KNOWN_STRATEGIES

def extract_base_question_id(sample_id: str) -> tuple[str, str | None]:
    """Extract base question ID by stripping paraphrase strategy suffix.

    Uses same logic as C3 (rsplit on '-', check KNOWN_STRATEGIES).
    This consolidates duplicated logic from 4 files.

    Returns: (base_id, strategy) where strategy is None if not a paraphrase.
    """
    if "-" in sample_id:
        parts = sample_id.rsplit("-", 1)
        if len(parts) == 2:
            if parts[1] in KNOWN_STRATEGIES or parts[1].replace("_", "").isalnum():
                return parts[0], parts[1]
    return sample_id, None

def aggregate_paraphrase_scores(
    df: pd.DataFrame,
    aggregation: str = "max",
    sample_id_col: str = "sample_id",
    score_col: str = "score",
) -> pd.DataFrame:
    """Group rows by base question, aggregate scores.

    Returns DataFrame with one row per base question.
    """
```

**Bonus**: Refactor other files to use this shared utility (reduces 4 duplications).

#### Step 2: Add flag to bootstrap CV
**File**: `src/detection_game/classifiers/run_multisample_bootstrap_cv.py`

Add config option:
```yaml
# configs/classifier/bootstrap_cv.yaml
aggregate_paraphrases_first: false  # New flag
paraphrase_aggregation: max         # Aggregation method for paraphrases
```

Modify `load_and_validate_csv()` to optionally call `aggregate_paraphrase_scores()` before bootstrap sampling.

#### Step 3: Update TM classifier output format (optional)
**File**: `src/detection_game/classifiers/run_trusted_monitor.py`

Ensure output includes strategy in sample_id consistently (already does via judge inputs).

### Files to Modify
| File | Change |
|------|--------|
| `utils/paraphrase_grouping.py` | NEW: grouping utilities |
| `classifiers/run_multisample_bootstrap_cv.py` | Add pre-aggregation flag |
| `configs/classifier/bootstrap_cv.yaml` | Add new config options |

### Files to Read (for reference)
| File | Why |
|------|-----|
| `scorers/embedding_entropy.py:103-195` | Existing paraphrase parsing logic |
| `constants.py` | KNOWN_STRATEGIES list |
| `utils/aggregation_stats.py` | Existing aggregation implementations |

## Full Execution Workflow

### Key Insight: Skip Code Execution
Since sandbagging prompts are already validated, we only need model responses for TM analysis. Use `trajectory.eval.score=false` to skip Docker/code execution - **much faster**.

### Judge Model
**TM uses `claude-3-5-haiku-20241022`** (per `mixins/trusted_monitoring.yaml`) - weaker than monitored model for proper threat model.

### Experimental Design: Control for k

**k is a fairness hyperparameter** - methods must use same k to be comparable.

| Experiment | Questions (k) | Paraphrases/Q | Within-Q Agg | Across-Q Agg |
|------------|---------------|---------------|--------------|--------------|
| **TM-original k=1** | 1 | 1 | N/A | N/A |
| **TM-original k=10** | 10 | 1 | N/A | mean |
| **TM-max k=1** | 1 | 10 | max | N/A |
| **TM-max k=10** | 10 | 10 | max | mean |
| **C3 k=1** | 1 | 10 | embedding var | N/A |
| **C3 k=10** | 10 | 10 | embedding var | mean |

**Comparison pairs**:
- k=1: TM-original vs TM-max vs C3 (single question detection)
- k=10: TM-original vs TM-max vs C3 (multi-question detection)

### Step-by-Step Execution

```bash
# ========================================
# PART A: Generate Trajectories (score=false, no Docker)
# ========================================

# A1: Original trajectories (no paraphrases)
python -m src.detection_game.cli.run_sweep \
  --config-name=usaco-original \
  trajectory.eval.score=false \
  +paraphraser.activate=false \
  --multirun

# A2: Paraphrase trajectories (10 Vendi strategies)
python -m src.detection_game.cli.run_sweep \
  --config-name=usaco-paraphrase \
  trajectory.eval.score=false \
  --multirun

# ========================================
# PART B: Run TM Judge
# ========================================

# B1: Judge on original trajectories
python -m src.detection_game.cli.run_judge \
  --config-name=usaco-trusted-monitor \
  judge.dataset.path=logs/runs/usaco-original-*

# B2: Judge on paraphrase trajectories
python -m src.detection_game.cli.run_judge \
  --config-name=usaco-trusted-monitor \
  judge.dataset.path=logs/runs/usaco-paraphrase-*

# ========================================
# PART C: Extract TM Scores
# ========================================

# C1: TM-original scores (1 score per question)
python -m src.detection_game.classifiers.run_trusted_monitor \
  classifier.log_dir=logs/runs/usaco-tm-original-* \
  classifier.output.csv=out/usaco_tm_original.csv

# C2: TM-paraphrase scores (10 scores per question)
python -m src.detection_game.classifiers.run_trusted_monitor \
  classifier.log_dir=logs/runs/usaco-tm-paraphrase-* \
  classifier.output.csv=out/usaco_tm_per_paraphrase.csv

# ========================================
# PART D: Bootstrap CV - All Configurations
# ========================================

# D1: TM-original k=1
python -m src.detection_game.classifiers.run_multisample_bootstrap_cv \
  classifier.csv_path=out/usaco_tm_original.csv \
  classifier.k_samples=1

# D2: TM-original k=10
python -m src.detection_game.classifiers.run_multisample_bootstrap_cv \
  classifier.csv_path=out/usaco_tm_original.csv \
  classifier.k_samples=10

# D3: TM-max k=1 (max over 10 paraphrases for 1 question)
python -m src.detection_game.classifiers.run_multisample_bootstrap_cv \
  classifier.csv_path=out/usaco_tm_per_paraphrase.csv \
  classifier.aggregate_paraphrases_first=true \
  classifier.paraphrase_aggregation=max \
  classifier.k_samples=1

# D4: TM-max k=10 (max over paraphrases, then mean over 10 questions)
python -m src.detection_game.classifiers.run_multisample_bootstrap_cv \
  classifier.csv_path=out/usaco_tm_per_paraphrase.csv \
  classifier.aggregate_paraphrases_first=true \
  classifier.paraphrase_aggregation=max \
  classifier.k_samples=10
```

## Verification Plan
1. **Unit test**: `aggregate_paraphrase_scores()` correctly groups and maxes
2. **Dry run**: Judge pipeline on N=5 USACO samples first
3. **Sanity checks**:
   - TM-max k=1 ≥ TM-original k=1 (more paraphrases = more chances to catch)
   - TM-max k=10 ≥ TM-original k=10
   - k=10 should have tighter confidence intervals than k=1
4. **Full comparison table** (R@5%FPR, pAUC<0.05):

| Method | k=1 | k=10 |
|--------|-----|------|
| TM-original | ? | ? |
| TM-max | ? | ? |
| C3 | ? | ? |

## Estimated Scope
- ~100 lines new code (grouping utility + bootstrap CV integration)
- ~20 lines config changes
- ~30 lines tests
- **Trajectory generation**: ~185 samples × (1 + 10 strategies) × 2 models = ~4070 API calls (fast without scoring)
- **Judge calls**: ~4070 TM evaluations (haiku-3.5)

## Design Decisions (Confirmed)
- **Judge model**: claude-3-5-haiku-20241022
- **Strategies**: Use same Vendi-selected subset as C3 (10 for USACO)
- **k as fairness parameter**: Compare methods at same k values (1, 10)
- **Skip scoring**: `trajectory.eval.score=false` - no Docker needed
- **Metrics**: R@5%FPR (primary), pAUC<0.05 (secondary)
