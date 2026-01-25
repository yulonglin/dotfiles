# Paraphrasing Strategy Selection Pipeline

## Goal
Select top-10 most diverse paraphrasing strategies from `strategies_v5_context.yaml` (27 strategies) for each dataset (GPQA, MATH, USACO), ensuring answerability.

## Design Decisions

| Question | Decision | Rationale |
|----------|----------|-----------|
| What to embed? | Paraphrased question outputs | Strategy prompts are templates; outputs capture actual transformation style |
| How to aggregate? | Strategy centroid (mean embedding) | Captures "average transformation style" per strategy |
| **Primary filter?** | **Answerability rate ≥80%**, try 90% if possible | Only use strategies that reliably produce answerable paraphrases |
| **Tiebreaker?** | **Vendi score (diversity)** | Among high-answerability strategies, pick most diverse |
| Output format? | JSON + Markdown report per dataset | Matches existing prompt_selection pipeline |

## Selection Logic (Revised)

```
1. Compute answerability rate for each of 27 strategies
2. Filter: Keep strategies with answerability ≥ 80% (minimum)
3. If ≥10 pass at 80%: Try stricter 90% threshold
4. If ≥10 pass at 90%: Use 90% filtered set
5. Else: Use 80% filtered set
6. If >10 pass final threshold: Use Vendi to select 10 most diverse
7. If ≤10 pass: Take all passing strategies
```

## Pipeline Stages

```
Stage 1: Load dev set samples (n≤100)
    ↓
Stage 2: Generate paraphrases (100 samples × 27 strategies = 2700)
    ↓
Stage 3: Check answerability for each paraphrase
    ↓
Stage 4: Compute answerability RATE per strategy (answerable/total)
    ↓
Stage 5: Filter strategies by answerability threshold (≥80%)
    ↓
Stage 6: Compute embeddings for passing strategies (centroid per strategy)
    ↓
Stage 7: If >10 pass, use Vendi to select 10 most diverse; else take all
    ↓
Stage 8: Generate report
```

## File Structure

```
src/detection_game/strategy_selection/
├── __init__.py
├── config.py      # StrategySelectionConfig, StrategyMetrics, SelectionResult
├── pipeline.py    # StrategySelectionPipeline class + CLI
├── metrics.py     # Answerability aggregation
└── report.py      # Markdown/JSON report generation

scripts/
└── select_paraphrasing_strategies.py  # Convenience wrapper (optional)
```

## Key Implementation Details

### config.py
```python
@dataclass
class StrategySelectionConfig:
    dataset: str  # gpqa, math, usaco
    version: str = "v5_context"
    n_samples: int = 100
    min_answerable: int = 5  # Min samples to include strategy
    top_k: int = 10
    embedding_model: str = "text-embedding-3-small"
    paraphrase_model: str = "openai/gpt-4.1-nano"
    cache_dir: Path = Path(".cache/strategy_selection")
    output_dir: Path = Path("out/strategy_selection")
```

### pipeline.py (core logic)
```python
class StrategySelectionPipeline:
    async def run(self) -> StrategySelectionReport:
        # Stage 1: Load samples
        samples = self._load_samples()  # dev set, n≤100

        # Stage 2: Generate paraphrases
        paraphrases = await self._generate_paraphrases(samples)  # uses paraphraser.py

        # Stage 3: Check answerability
        await self._check_answerability(paraphrases)  # uses quality_filters.py

        # Stage 4: Compute answerability rate per strategy
        rates = self._compute_answerability_rates(paraphrases)

        # Stage 5: Filter by answerability threshold
        # Start with 80% minimum, try 90% if enough pass
        passing_80 = [s for s, rate in rates.items() if rate >= 0.80]
        passing_90 = [s for s, rate in rates.items() if rate >= 0.90]

        # Use stricter threshold if enough strategies qualify
        if len(passing_90) >= 10:
            passing = passing_90
            threshold_used = 0.90
        else:
            passing = passing_80
            threshold_used = 0.80

        # Stage 6: Compute embeddings for passing strategies
        centroids = await self._compute_centroids(paraphrases, passing)

        # Stage 7: Select top-10 (Vendi as tiebreaker if >10 pass)
        if len(passing) > 10:
            selected = self._select_diverse(centroids, max_k=10)
        else:
            selected = passing  # Take all

        # Stage 8: Report
        return self._generate_report(selected, rates)
```

### CLI Interface
```bash
# Single dataset
python -m src.detection_game.strategy_selection.pipeline \
    --dataset gpqa --n-samples 100 --top-k 10

# All datasets
python -m src.detection_game.strategy_selection.pipeline \
    --dataset all --n-samples 100 --top-k 10
```

## Output Files

**Per-dataset:**
- `out/strategy_selection/{dataset}/selected_strategies.json` - strategy list + metrics
- `out/strategy_selection/{dataset}/report.md` - human-readable report

**Cache:**
- `.cache/strategy_selection/{dataset}/paraphrases.jsonl`
- `.cache/strategy_selection/{dataset}/embeddings.npz`

## Existing Code to Reuse

| Component | Location | Function |
|-----------|----------|----------|
| Paraphrasing | `dataset/paraphraser.py` | `paraphrase_prompt()` |
| Answerability | `dataset/quality_filters.py` | `ParaphraseQualityFilter` |
| Embeddings | `prompt_selection/embeddings.py` | `compute_embeddings_async()` |
| Vendi selection | `prompt_selection/embeddings.py` | `greedy_vendi_selection()` |
| Dataset loading | `tasks/gpqa.py`, `mathematics.py`, `usaco.py` | Task loaders |

## Estimated Cost

| Stage | Calls | Cost |
|-------|-------|------|
| Paraphrasing | 2700/dataset | ~$0.50 |
| Answerability | 2700/dataset | ~$0.10 |
| Embeddings | ~2700/dataset | ~$0.05 |
| **Total (3 datasets)** | | **~$2.00** |

## Verification

1. Run for GPQA first (smallest dev set = 79 samples):
   ```bash
   python -m src.detection_game.strategy_selection.pipeline --dataset gpqa
   ```

2. Check output:
   - `out/strategy_selection/gpqa/report.md` exists
   - 10 strategies selected
   - All have answerability_rate > 0

3. Compare selected strategies across datasets to see if they differ

4. Spot-check a few paraphrases manually to verify quality
