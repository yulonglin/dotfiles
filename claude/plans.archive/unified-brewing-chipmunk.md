# Plan: Quality-Filtered Paraphrases & Detection Signal Analysis

## Goal
Generate high-quality paraphrases with retry logic, then identify paraphrase subsets that maximize sandbagging detection signal across GPQA, MATH (L5), and USACO.

## Decisions
- **MATH**: Level 5 only (~921 samples) - hardest problems, realistic sandbagging
- **Strategies**: v3.2 + v4 (55 total), but first identify/remove redundant strategies
- **Detection**: Embedding entropy only (C³ detection)

---

## Phase 0: Identify Redundant Strategies (NEW)

### 0.1 Compute strategy similarity matrix

For each strategy, generate sample paraphrases (N=10 questions), embed them, and compute pairwise cosine similarity between strategy centroids.

```python
# scripts/analyze_strategy_similarity.py (new)
# 1. Load v3.2 + v4 strategy prompts (55 total)
# 2. For each strategy, generate paraphrases of 10 sample questions
# 3. Embed paraphrases, compute centroid per strategy
# 4. Compute 55×55 similarity matrix
# 5. Identify clusters (strategies with >0.9 cosine similarity)
# 6. Output: deduplicated strategy list
```

### 0.2 Expected output
- Strategy similarity matrix heatmap
- Recommended deduplicated list (likely ~30-40 unique strategies)

---

## Phase 1: Generate Quality-Filtered Paraphrases

### 1.1 Run static generation for all datasets (train + val)

```bash
# GPQA (MCQ) - 79 samples × ~40 strategies
python scripts/generate_static_paraphrases.py \
  --dataset gpqa --split train,val --strategies $DEDUP_STRATEGIES \
  --max-retries 3 --max-concurrent 200

# MATH Level 5 - 921 samples × ~40 strategies
python scripts/generate_static_paraphrases.py \
  --dataset math --split train,val --strategies $DEDUP_STRATEGIES \
  --max-retries 3 --max-concurrent 200 \
  --levels 5  # Need to add this flag

# USACO - 122 samples × ~40 strategies
python scripts/generate_static_paraphrases.py \
  --dataset usaco --split train,val --strategies $DEDUP_STRATEGIES \
  --max-retries 3 --max-concurrent 200
```

### 1.2 Output location
- `data/processed/paraphrases/{dataset}/{split}_{strategy}.jsonl`
- Each entry includes: `paraphrased_text`, `quality_scores`, `metadata.retries`

---

## Phase 2: Compute Paraphrase-Level Metrics

### 2.1 Create analysis script: `scripts/analyze_paraphrase_detection_correlation.py`

For each paraphrase, compute:

**Quality metrics** (from existing quality_scores):
- `is_answerable`: boolean
- `retry_count`: number of retries needed

**Semantic metrics** (new, compute at paraphrase level):
- `prompt_length`: character count of paraphrased text
- `length_ratio`: paraphrased_length / original_length
- `cosine_distance_from_original`: embedding distance from original
- `token_count`: number of tokens

**Strategy-level metrics** (aggregate across samples):
- `mean_answerability_rate`: % of samples that pass quality
- `mean_cosine_distance`: average semantic drift for strategy
- `vendi_score`: diversity within strategy outputs

### 2.2 Key files to modify/create
- `scripts/analyze_paraphrase_detection_correlation.py` (new)
- Uses `src/detection_game/utils/embedding_utils.py` for embeddings
- Uses `src/detection_game/utils/diversity_metrics.py` for Vendi score

---

## Phase 3: Run Detection Experiments with Varying Subsets

### 3.1 Experimental conditions

Test detection performance using different paraphrase subsets:

| Condition | Subset Selection Criteria |
|-----------|--------------------------|
| Baseline | All strategies (original + 27 paraphrases) |
| High-quality | Only `is_answerable=true` |
| Diverse-5 | Top 5 by cross-strategy Vendi score |
| High-distance | Top 5 by mean cosine distance from original |
| Short-prompts | Bottom 5 by prompt length |
| Combined | High-quality ∩ Diverse ∩ High-distance |

### 3.2 Run embedding entropy classifier per condition

```bash
for condition in baseline high_quality diverse_5 high_distance short combined; do
  for dataset in gpqa math usaco; do
    python -m src.detection_game.classifiers.run_embedding_entropy \
      classifier.log_dir=logs/runs/${dataset}-paraphrase-static-* \
      classifier.strategy_filter="${STRATEGIES[$condition]}" \
      classifier.metrics='[mean_pairwise_cosine_distance]' \
      classifier.output.csv=out/detection/${dataset}_${condition}.csv
  done
done
```

### 3.3 Aggregate with bootstrap CV

```bash
python -m src.detection_game.classifiers.run_multisample_bootstrap_cv \
  classifier.input_csv=out/detection/${dataset}_${condition}.csv \
  classifier.k_samples=5 \
  classifier.compare_mode=pooled \
  classifier.output_json=out/detection/${dataset}_${condition}_cv.json
```

---

## Phase 4: Correlation Analysis

### 4.1 Correlate paraphrase metrics with detection AUROC

For each strategy, compute:
- Mean AUROC across datasets
- Correlation with: answerability rate, cosine distance, prompt length, Vendi score

### 4.2 Output
- Table: Strategy × Metric × Dataset with AUROC
- Scatter plots: Paraphrase metric vs detection AUROC
- Recommendations: Which metrics best predict detection signal

---

## Key Files

**Existing (to use)**:
- `scripts/generate_static_paraphrases.py` - paraphrase generation with retries
- `src/detection_game/dataset/quality_filters.py` - answerability checking
- `src/detection_game/utils/diversity_metrics.py` - Vendi score
- `src/detection_game/classifiers/run_embedding_entropy.py` - detection classifier

**To create**:
- `scripts/analyze_paraphrase_detection_correlation.py` - correlation analysis

---

## Expected Outputs

1. **Quality-filtered paraphrases**: `data/processed/paraphrases/{dataset}/`
2. **Paraphrase metrics CSV**: `out/paraphrase_metrics.csv`
3. **Detection results per condition**: `out/detection/{dataset}_{condition}_cv.json`
4. **Correlation analysis**: `out/paraphrase_detection_correlation.json`
5. **Recommendations**: Which paraphrase subset works best across datasets

---

## Estimated Scope (Train + Val)

| Dataset | Samples | Strategies | Paraphrases | API calls (with retries) |
|---------|---------|------------|-------------|--------------------------|
| GPQA | 79 | ~40 | ~3,160 | ~5,000 |
| MATH L5 | 921 | ~40 | ~36,840 | ~55,000 |
| USACO | 122 | ~40 | ~4,880 | ~7,500 |
| **Total** | 1,122 | ~40 | ~44,880 | ~67,500 |

Estimated cost: ~$50-60 (well within budget)
