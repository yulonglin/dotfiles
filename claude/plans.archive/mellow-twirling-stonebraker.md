# Prompt Selection Pipeline Implementation Plan

## Goal
Implement full evaluation integration for the prompt selection pipeline by implementing `_run_evaluation()` in `runner.py`, then run it for GPQA and MATH datasets.

## Overview

The pipeline currently runs in `dry_run` mode with mock data. We need to implement real evaluation by:
1. Running sandbagging and benign conditions via Inspect AI's evaluation function
2. Extracting accuracy from `.eval` files
3. Computing refusal rate (model refusing sandbagging instructions)
4. Computing leakage rate (model revealing strategy)

## Implementation Steps

### Step 1: Add Required Imports to `runner.py`

```python
import asyncio
import shutil
import tempfile
from concurrent.futures import ThreadPoolExecutor

from hydra.utils import instantiate
from inspect_ai import eval as inspect_eval  # Inspect AI's eval function
from inspect_ai.log import read_eval_log
from inspect_ai.model import GenerateConfig, get_model
from omegaconf import OmegaConf

from src.detection_game.scorers.embedding_entropy import extract_assistant_text
from src.detection_game.utils.sandbag_refusal_detector import detect_sandbag_refusal
from src.detection_game.utils.strategy_leakage_detector import calculate_leakage_rate
```

### Step 2: Add Helper Methods to `PromptSelectionRunner`

| Method | Purpose |
|--------|---------|
| `_create_task()` | Create Inspect Task for the dataset |
| `_create_models()` | Create model instances with/without system prompt |
| `_extract_accuracies()` | Extract accuracy from .eval files |
| `_get_score_keys_for_dataset()` | Return appropriate score column names |
| `_extract_response_texts()` | Extract assistant responses for refusal/leakage analysis |

### Step 3: Implement `_run_evaluation()`

**Flow:**
1. Create temp directories for sandbagging and benign logs
2. Create task for dataset (gpqa/math/usaco)
3. Create models with sandbagging prompt (candidate.content) and without (benign)
4. Run Inspect AI evaluation for both conditions in parallel using ThreadPoolExecutor
5. Extract accuracies from both log directories
6. Extract response texts from sandbagging logs
7. Compute refusal rate using `detect_sandbag_refusal()`
8. Compute leakage rate using `calculate_leakage_rate()`
9. Return `PromptMeasurement` with all metrics
10. Clean up temp directories

**Key Design Decisions:**
- Use `ThreadPoolExecutor` since Inspect's evaluation is sync but `_run_evaluation` is async
- Run sandbagging and benign evaluations in parallel for efficiency
- Use temporary directories to isolate each prompt's evaluation
- Extract first assistant response (message_selection=0) for analysis

### Step 4: Run for GPQA and MATH

```bash
# GPQA
python -m src.detection_game.cli.run_prompt_selection \
  --config-name=prompt_selection/gpqa \
  execution.dry_run=false

# MATH
python -m src.detection_game.cli.run_prompt_selection \
  --config-name=prompt_selection/math \
  execution.dry_run=false
```

## Files to Modify

| File | Changes |
|------|---------|
| `src/detection_game/prompt_selection/runner.py` | Add imports, helper methods, implement `_run_evaluation()` |

## Critical Reference Files

| File | Reference For |
|------|---------------|
| `src/detection_game/cli/run_sweep.py:205-301` | Model creation patterns |
| `src/detection_game/cli/run_sweep.py:718-733` | Inspect AI evaluation call signature |
| `src/detection_game/scorers/embedding_entropy.py:232-277` | `extract_assistant_text()` |
| `src/detection_game/utils/sandbag_refusal_detector.py` | `detect_sandbag_refusal()` |
| `src/detection_game/utils/strategy_leakage_detector.py` | `calculate_leakage_rate()` |

## Score Keys by Dataset

| Dataset | Score Keys (priority order) |
|---------|----------------------------|
| GPQA | `choice` |
| MATH | `expression_equivalance`, `expression_exact_match` |
| USACO | `accuracy`, `pass` |

## Verification

1. **Unit test**: Run with small limit (N=5) to verify extraction works
2. **Dry run comparison**: Compare mock vs real measurements for sanity check
3. **Full run**: Execute for GPQA and MATH with full sample sizes

```bash
# Quick verification (small N)
python -m src.detection_game.cli.run_prompt_selection \
  --config-name=prompt_selection/gpqa \
  execution.dry_run=false \
  pipeline.n_samples_stage1=5
```

## Post-Implementation

Use Ralph Wiggum Loop:
- **Code Simplifier agent**: Clean up implementation
- **Code Reviewer agent**: Review against CLAUDE.md standards
