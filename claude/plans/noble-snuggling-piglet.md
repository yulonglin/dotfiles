# Static Paraphrase Pipeline Implementation Plan

## Goal
Replace runtime paraphrasing with pre-computed static paraphrases that have quality filtering (answerability) with dataset-specific strategies.

---

## Spec File Update (specs/TODO-improve-paraphrase-pipeline.md)

After exiting plan mode, update the spec with these **requirements** (not implementation):

### Problem Statement
Current runtime paraphrasing has quality issues:
1. Some paraphrases are not answerable (missing key info)
2. No quality control before experiments run
3. Paraphrasing happens at runtime, wasting compute on bad paraphrases
4. No dataset-specific optimization of strategies

### Requirements
1. **Pre-computed paraphrases**: Generate and validate paraphrases before experiments
2. **Answerability filtering**: LLM judge rates whether each paraphrase is answerable; retry up to 3x if not
3. **Dataset-specific strategies**: Different datasets may need different paraphrase strategies
4. **Few contexts approach**: Explore using 2-3 distinct contexts instead of many strategies (sample efficiency)
5. **Static loading**: Load pre-computed paraphrases from disk at runtime (no API calls)

### Quality Criteria
- **Primary**: `is_answerable` = true (LLM judge)
- **Optional**: `is_substantively_different` = true (ensure meaningful variation)
- **NOT used**: `preserves_all_details` (too strict for creative reframing)

### Success Metrics
- Reduced failed paraphrases in downstream experiments
- Consistent paraphrase quality across runs
- Faster experiment iteration (no runtime paraphrasing)

---

## User Requirements
- **Scope**: All datasets (GPQA, MATH, USACO)
- **Filtering**: Answerability-only filtering (preservation check too strict), with 3 retries
- **Dataset-specific strategies**: Different strategies may work best for different datasets
- **Storage**: `data/processed/paraphrases/`
- **Replace runtime entirely**: No more API calls during `run_sweep.py`

## Key Design Insight: Two Approaches to Explore

**Approach A: Few Contexts (sample-efficient)**
- Just 2-3 distinct contexts (e.g., "train context" vs "eval context")
- More sample-efficient, easier to interpret
- Manual selection of meaningfully different framings

**Approach B: Many Strategies + Diversity Filtering (automated)**
- Generate many paraphrase strategies
- Filter by `is_substantively_different` to ensure meaningful variation
- More automated, scales better across datasets
- Current infrastructure already supports this

**Recommendation**: Try both. Approach B is more automated and makes sense as the default. Approach A is worth exploring for interpretability.

**Related work**:
- Another agent is adding paraphrasing caching to `paraphraser.py` - coordinate with that work
- **Vendi score diversification** (`specs/TODO-diversify-paraphrases.md`): Uses eigenvalue entropy of similarity matrix to measure "effective number of unique items". Can replace/augment `is_substantively_different` for diversity measurement. Consider integrating at a later stage for more principled diversity selection.

---

## Data Flow

```
PRE-COMPUTATION (offline):
  Original Dataset → Paraphrase Generator → Quality Filters → Retry Loop (3x) → JSONL files

RUNTIME (run_sweep.py):
  Task → Static Loader (from disk) → Paraphrased Task → Inspect Eval → .eval files
```

---

## Implementation Steps

### Step 1: Quality Filtering Module
**Create**: `src/detection_game/dataset/quality_filters.py`

Refactor quality checks from `scripts/identify_problematic_paraphrases.py` into reusable module:

```python
@dataclass
class QualityScore:
    is_answerable: bool
    is_substantively_different: bool | None = None  # Optional diversity check
    retry_feedback: str | None = None  # For retry guidance if not answerable

class ParaphraseQualityFilter:
    async def check_answerability(self, text: str) -> tuple[bool, str | None]  # (passes, feedback)
    async def check_diversity(self, original: str, paraphrased: str) -> bool  # Optional
    async def evaluate_quality(self, original: str, paraphrased: str) -> QualityScore
```

Key features:
- Reuse existing LLM prompts from `identify_problematic_paraphrases.py`
- JSONL caching (existing pattern)
- Async with semaphore (200+ concurrent)
- Return feedback for retry mechanism

### Step 2: Pre-computation Script
**Create**: `scripts/generate_static_paraphrases.py`

Main orchestrator:

```bash
# Generate for all datasets
python scripts/generate_static_paraphrases.py --dataset all

# Dataset-specific with strategy filter
python scripts/generate_static_paraphrases.py \
    --dataset gpqa \
    --strategies casual,technical,frustrated,eli5,original \
    --max-retries 3

# Regenerate failed only
python scripts/generate_static_paraphrases.py --dataset math --regenerate-failed
```

Key functions:
- `generate_paraphrase_with_retry()`: Generate + quality check + retry with feedback
- `generate_dataset_paraphrases()`: Batch process all samples for a dataset
- Uses iterative refinement pattern from literature (Self-Refine)

### Step 3: Static Loader
**Create**: `src/detection_game/dataset/static_paraphraser.py`

```python
class StaticParaphraseLoader:
    def load(self) -> None  # Load JSONL into memory cache
    def get_paraphrase(self, sample_id: str, strategy: str) -> str | None
    def create_paraphrased_samples(self, samples: list[Sample], strategies: list[str]) -> list[Sample]

async def create_static_paraphrased_dataset_from_task(
    task: Task, config: StaticParaphraseConfig, limit: int | None = None
) -> Task
```

Key features:
- Memory-cached lookup by (sample_id, strategy)
- Quality filtering on load (`require_quality: true`)
- Same interface as existing `create_paraphrased_dataset_from_task()`

### Step 4: Hydra Configs
**Create**: `src/detection_game/configs/paraphraser/static.yaml`

```yaml
activate: true
mode: static
static_dir: data/processed/paraphrases
require_quality: true
strategies: all
strategies_version: v3.2
```

**Create dataset-specific configs**:
- `static_gpqa.yaml`: strategies = [original, casual, technical, frustrated, eli5, professional]
- `static_math.yaml`: strategies = [original, eli5, confused_student, teacher_explanation]
- `static_usaco.yaml`: strategies = [original, debugging_context, code_review, collaborative]

### Step 5: CLI Integration
**Modify**: `src/detection_game/cli/run_sweep.py` (lines ~470-524)

Add static mode detection:

```python
if cfg.paraphraser.activate:
    paraphrase_mode = getattr(cfg.paraphraser, "mode", "runtime")

    if paraphrase_mode == "static":
        from src.detection_game.dataset.static_paraphraser import (
            StaticParaphraseConfig, create_static_paraphrased_dataset_from_task
        )
        static_config = StaticParaphraseConfig(
            paraphrase_dir=Path(cfg.paraphraser.static_dir),
            dataset=cfg.trajectory.dataset.name,
            strategies=resolve_strategies(...),
            require_quality=cfg.paraphraser.require_quality,
        )
        tasks = [create_static_paraphrased_dataset_from_task(task, static_config) for task in tasks]
    else:
        # Existing runtime logic (eventually remove)
```

### Step 6: Generate Static Paraphrases
Run pre-computation for all datasets:

```bash
python scripts/generate_static_paraphrases.py --dataset gpqa --strategies all
python scripts/generate_static_paraphrases.py --dataset math --strategies all
python scripts/generate_static_paraphrases.py --dataset usaco --strategies all
```

---

## Storage Format

```
data/processed/paraphrases/
├── gpqa/
│   ├── train_casual.jsonl
│   ├── train_technical.jsonl
│   └── ...
├── math/
│   └── ...
├── usaco/
│   └── ...
└── quality_reports/
    ├── gpqa_strategy_summary.json
    └── ...
```

**JSONL format**:
```json
{"sample_id": "001", "strategy": "casual", "original_text": "...", "paraphrased_text": "...", "quality_scores": {"is_answerable": true, "preserves_all_details": true, "is_substantively_different": true}, "metadata": {"attempt": 0, "model": "gpt-4.1-nano"}}
```

---

## Quality Filtering Pipeline

**Primary gate: Answerability only.** The `preserves_all_details` check is too strict - many good paraphrases get flagged even when substance is preserved but framing differs significantly.

| Stage | Metric | Threshold | Action on Fail |
|-------|--------|-----------|----------------|
| 1. Answerability | LLM judge | is_answerable=true | Retry with feedback (up to 3x) |
| 2. Diversity (optional) | LLM judge | is_substantively_different=true | Flag as low-diversity |

After 3 retries: Keep best attempt with quality flags in metadata.

**Note**: `preserves_all_details` is intentionally omitted. We want the *substance* to be the same even with very different framing.

---

## Literature-Informed Improvements to Paraphrase Prompts

1. **Add few-shot examples** (1-2 per strategy) - POSIX research shows this significantly improves quality
2. **Structured output format** - JSON with explicit preserved_elements list
3. **Self-verification step** - "Before outputting, verify ALL of these are unchanged: [checklist]"
4. **Content extraction** - Pre-extract critical elements (numbers, formulas, code) for post-verification

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `src/detection_game/dataset/quality_filters.py` | Create |
| `src/detection_game/dataset/static_paraphraser.py` | Create |
| `scripts/generate_static_paraphrases.py` | Create |
| `src/detection_game/configs/paraphraser/static.yaml` | Create |
| `src/detection_game/configs/paraphraser/static_gpqa.yaml` | Create |
| `src/detection_game/configs/paraphraser/static_math.yaml` | Create |
| `src/detection_game/configs/paraphraser/static_usaco.yaml` | Create |
| `src/detection_game/cli/run_sweep.py` | Modify (lines ~470-524) |
| `scripts/identify_problematic_paraphrases.py` | Refactor (extract to quality_filters.py) |

---

## Testing Strategy

1. **Unit tests**: Quality filters, static loader, JSONL parsing
2. **Integration tests**: End-to-end pre-computation for limit=5 samples
3. **Regression tests**: Compare detection results with static vs runtime paraphrases

---

## Implementation Order

1. Create `quality_filters.py` (refactor from identify_problematic_paraphrases.py)
2. Create `static_paraphraser.py` (loader + create_static_paraphrased_dataset_from_task)
3. Create Hydra configs (static.yaml + dataset-specific)
4. Modify `run_sweep.py` for static mode
5. Create `generate_static_paraphrases.py` (pre-computation script)
6. Generate static paraphrases for all datasets
7. Add tests and update CLAUDE.md documentation
