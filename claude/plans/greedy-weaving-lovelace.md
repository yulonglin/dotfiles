# Plan: Diversity Measurement for Brainstorming Pipeline

## Summary

Add optional Vendi Score-based diversity analysis to measure whether the multi-model, multi-technique divergence phase actually produces diverse ideas—and to identify which (model, technique) pairs contribute most unique ideas.

## Key Insight

**Vendi Score is the right fit; G-Vendi (Prismatic Synthesis) is not.**

| Metric | What It Measures | Applicability |
|--------|------------------|---------------|
| **Vendi Score** | Sample diversity via similarity matrix eigenvalue entropy | ✅ Perfect for comparing brainstorming outputs |
| **G-Vendi** | Gradient-space diversity for training data | ❌ Requires model training; not applicable to output analysis |

## Recommendation: Staged Empirical Approach

**Why staged:**
1. We don't know if diversity metrics correlate with idea quality yet
2. Jumping straight to "diversity-informed synthesis" risks adding noise without evidence
3. Proper empirical research requires observational baseline before intervention

**Phase A: Observational Baseline (First 3-5 sessions)**
- Run diversity analysis automatically after divergence
- Collect metrics but DON'T feed into red-teaming/synthesis
- After synthesis, retroactively check:
  - Did high-Vendi sessions produce better ideas? (human judgment)
  - Did convergence signals predict which ideas made final cut?
  - Which (model, technique) pairs contributed most unique ideas?

**Phase B: Experimental (If Phase A shows signal)**
- A/B test: Some sessions with diversity context in synthesis prompt, some without
- Compare final idea quality across conditions
- Only make permanent if measurable improvement

**What diversity measurement CAN do (once validated):**
- Detect unexpectedly homogeneous sessions → trigger re-run with different techniques
- Identify which (model, technique) pairs contribute most unique ideas → optimize resource allocation
- Find convergence signals (many models → same idea) → higher confidence in those ideas
- Track diversity across sessions → see if you're getting stale

## Implementation Plan

### Phase 1: Core Diversity Analysis (~2 hours)

**File: `src/diversity.py`**

```python
# Core components:
1. compute_embeddings(ideas: list[str]) -> np.ndarray
   - Use OpenAI text-embedding-3-small (cheap, fast)
   - Cache embeddings to .cache/embeddings/

2. compute_similarity_matrix(embeddings: np.ndarray) -> np.ndarray
   - Cosine similarity between all pairs

3. vendi_score(similarity_matrix: np.ndarray) -> float
   - Use `vendi` pip package OR implement directly:
   - eigenvalues = np.linalg.eigvalsh(similarity_matrix)
   - p = eigenvalues / eigenvalues.sum()
   - entropy = -sum(p * log(p)) for p > 0
   - return exp(entropy)

4. cluster_ideas(embeddings, n_clusters=5) -> list[int]
   - K-means or hierarchical clustering
   - Identify which ideas are near-duplicates

5. per_source_contribution(ideas, sources, embeddings) -> dict
   - For each (model, technique): what % of unique ideas?
   - "Unique" = distance > threshold from all others
```

**Key files to modify:**
- `src/brainstorm.py`: Add diversity analysis after divergence phase
- `src/config.py`: Add embedding model config
- `main.py`: Add `--analyze-diversity` flag or `diversity` subcommand

### Phase 2: Integration Points

**A. Post-Divergence Analysis** (implement first - observational baseline)
```
After run_divergence() completes:
1. Extract all ideas from scratchpad/*.md files
2. Compute embeddings via text-embedding-3-small (cached)
3. Compute Vendi score + identify clusters
4. Calculate per-(model, technique) contribution
5. Save to scratchpad/diversity-analysis-<timestamp>.json
6. Generate markdown summary for human review
7. Log to ideas/<dir>/diversity-log.jsonl (append-only for cross-session analysis)
```

**B. Enhance Red-Teaming Prompt** (Phase B only - after baseline shows signal)
Add to RED_TEAM_CRITIQUE_PROMPT:
```
Based on diversity analysis:
- Vendi Score: {score} (higher = more diverse)
- Near-duplicate clusters: {clusters}
- Highest-contributing sources: {top_sources}

Pay special attention to ideas that appear across multiple models (convergence signal).
```

**C. Pre-Synthesis Context** (Phase B only - after baseline shows signal)
Include diversity summary in synthesis prompt so Claude Opus knows which ideas are genuinely novel vs. variations.

**D. Cross-Session Tracking** (implement in Phase 1)
```
After each session, append to ideas/diversity-history.jsonl:
{
  "session": "<idea_dir>",
  "timestamp": "...",
  "vendi_score": 12.4,
  "n_ideas": 64,
  "top_sources": [...],
  "synthesis_quality": null  # Fill in manually after human review
}
```
This enables correlation analysis: does Vendi score predict synthesis quality?

### Phase 3: CLI Integration

```bash
# Run divergence with diversity analysis
python main.py brainstorm <idea_dir> --phase divergence --analyze-diversity

# Standalone diversity analysis on existing outputs
python main.py diversity <idea_dir>

# Full run with diversity
python main.py full <idea_dir> --analyze-diversity
```

### Phase 4: Output Format

**File: `scratchpad/diversity-analysis-<timestamp>.json`**
```json
{
  "timestamp": "2025-01-02T...",
  "vendi_score": 12.4,
  "interpretation": "High diversity (12.4 effective distinct ideas from 64 outputs)",
  "n_outputs": 64,
  "n_clusters": 8,
  "near_duplicates": [
    {"ideas": [0, 15, 32], "theme": "persona resistance"},
    ...
  ],
  "source_contributions": {
    "deepseek-r1:ASSUMPTION_INVERSION": {"unique_ideas": 3, "contribution": 0.12},
    ...
  },
  "low_diversity_warning": false
}
```

**File: `scratchpad/diversity-analysis-<timestamp>.md`**
```markdown
# Diversity Analysis

**Vendi Score: 12.4** (High - 12.4 effective distinct ideas from 64 outputs)

## Source Contributions
| Model | Technique | Unique Ideas | Contribution |
|-------|-----------|--------------|--------------|
| deepseek-r1 | ASSUMPTION_INVERSION | 3 | 12% |
| ... | ... | ... | ... |

## Near-Duplicate Clusters
1. **Persona Resistance** (3 outputs): #0, #15, #32
2. ...

## Recommendations
- Consider re-running with CONCEPTUAL_BLENDING (underperforming)
- Convergence detected on "persona resistance" - high confidence direction
```

## Dependencies

```bash
uv add vendi-score  # or implement manually (10 lines)
uv add openai       # for embeddings (likely already have)
uv add scikit-learn # for clustering
```

## Decisions Made

1. **Embedding model**: OpenAI text-embedding-3-small ✓
2. **Integration**: Auto-run after divergence (Phase A), feed into synthesis later (Phase B, if baseline shows signal)
3. **Threshold for warnings**: Calibrate after 3-5 sessions (need baseline data)

## What This Does NOT Do

- **Does not filter ideas** - human judgment required
- **Does not rank by quality** - diversity ≠ quality
- **Does not replace synthesis** - just informs it
- **Does not measure "weirdness"** - semantic diversity only

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Embeddings miss research-relevant diversity | Use as diagnostic, not filter; validate on real sessions |
| API cost for embeddings | Use cheapest model; cache aggressively |
| Over-optimization for diversity metric | Remember: diversity is necessary but not sufficient |
| Slows down pipeline | Make analysis optional; run in background |

## Success Criteria

After 3-5 brainstorming sessions:
1. Can identify which (model, technique) pairs are most/least effective
2. Vendi score correlates with human perception of session quality
3. Near-duplicate detection catches obvious redundancy
4. Convergence signals match ideas that make it to SYNTHESIS.md
