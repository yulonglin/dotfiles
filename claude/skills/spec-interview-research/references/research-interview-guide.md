# Research Interview Guide

15 question categories for comprehensive research planning.

## 1. Research Question & Motivation
- What exactly are you investigating?
- Why does this matter?
- What gap in knowledge does this address?
- What are the practical implications if your hypothesis is correct/incorrect?

## 2. Hypotheses & Falsification
- What are your explicit hypotheses?
- What specific results would falsify each hypothesis?
- What results would support (but not prove) your hypothesis?
- Are your hypotheses testable with the available resources?

## 3. Independent Variables
- What are you manipulating or varying?
- What are the levels/values for each variable?
- Why these specific values?
- Which variables are most critical to test? (drill down on these)

## 4. Dependent Variables & Metrics
- What are you measuring?
- What exact metrics? (e.g., "exact_match on MMLU", not just "accuracy")
- How will you operationalize abstract concepts into measurable quantities?
- Are these metrics validated in prior work?

## 5. Control Variables
- What must stay constant across all conditions?
- Which variables could introduce noise if not controlled?
- How will you ensure consistency?

## 6. Confounding Variables
- What alternative explanations could account for your results?
- Which confounds are most plausible?
- How will you rule them out? (experimental controls, statistical methods, etc.)
- What assumptions are you making?

## 7. Models & Hyperparameters
- Which models are you using? Why?
- What hyperparameters? (learning rate, temperature, context length, etc.)
- Have you justified each hyperparameter choice?
- Are you using default values? If so, why are they appropriate?

## 8. Baselines & Comparisons
- What are you comparing against?
- Why are these baselines fair/strong?
- Are you including a naive baseline (random, majority class, etc.)?
- Are you comparing to state-of-the-art?

## 9. Datasets
- Which datasets? Versions?
- Train/val/test split sizes and selection method?
- Any preprocessing steps?
- Are datasets publicly available and reproducible?
- Potential data leakage or contamination concerns?

## 10. Graphs & Visualizations
- What plots will demonstrate the key findings?
- For each plot: X-axis? Y-axis? Grouping/colors? Error bars?
- What story does each visualization tell?
- Are these the minimal sufficient set of plots?

## 11. Resources & Validation
- CPU/GPU/memory requirements?
- Estimated API cost (if using LLM APIs)?
- Time estimate for full run?
- **[INLINE VALIDATION]**: Check system resources, warn if insufficient
  - Run: `sysctl hw.physicalcpu hw.memsize` (macOS) or `nproc && free -h` (Linux)
  - Compare to requirements, show mismatch clearly

## 12. Sample Size & Power
- How many samples/trials?
- What is the minimum detectable effect size?
- Statistical significance threshold (α, typically p<0.05)?
- Statistical power (1-β, typically >0.80)?
- Is the sample size sufficient to detect meaningful differences?

## 13. Performance & Caching Strategy
- What gets cached? (API responses, embeddings, intermediate results)
- Cache keys: How is uniqueness determined?
- What needs to rerun? (aggregation, plotting, stats)
- Concurrency level? (e.g., 100 concurrent API calls)
- Exponential backoff strategy for rate limits?

## 14. Error Handling & Retries
- Which errors are transient (429, 503) vs permanent (400, 401)?
- Retry logic for transient errors?
- How to handle rate limits? (exponential backoff, respect retry-after header)
- What happens when retries exhausted?

## 15. Reproducibility
- Random seeds? (e.g., seeds=[42,43,44,45,46] for 5 runs)
- Code version (git commit)?
- Data version (hash or version tag)?
- Logging plan: What gets logged and where?
- Output path: Exact directory structure?

---

## Interview Flow

1. **Start high-level**: Get the big picture first
2. **Drill down on critical decisions**: Spend time on variables that matter most
3. **Challenge assumptions**: "Why baseline X instead of Y?" "What if confound Z explains results?"
4. **Inline validation**: For resources, check system capabilities during interview
5. **Iterate until complete**: Don't rush; ask 2-4 focused questions per round
