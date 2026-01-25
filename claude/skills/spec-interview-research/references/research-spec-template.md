# Research Interview Spec: [Topic]

## Overview
**Created**: DD-MM-YYYY
**Status**: Draft Interview Spec

[1-2 sentence summary]

## Research Question
[Specific, measurable question]

## Hypotheses
- **H1**: [Hypothesis] → Prediction: [Specific outcome] → Falsification: [What would disprove]
- **H2**: ...

## Variables
### Independent (What We Manipulate)
- [Variable 1]: [Values/levels, e.g., model size: [1B, 7B, 13B]]
- [Variable 2]: ...

### Dependent (What We Measure)
- [Metric 1]: [Exact definition, e.g., "exact_match accuracy on MMLU"]
- [Metric 2]: ...

### Control (Held Constant)
- [Constant 1]: ...

### Confounds & Controls
| Confound | How Controlled |
|----------|----------------|
| [Alternative explanation] | [Method to rule out] |

## Models & Hyperparameters
| Component | Choice | Justification |
|-----------|--------|---------------|
| Model | [e.g., Claude Sonnet 4.5] | [Why this model] |
| Hyperparameter | [e.g., temperature=0.7] | [Why this value] |

## Baselines
- **Baseline 1**: [Description, why fair/strong]
- **Baseline 2**: ...

## Datasets
- **Dataset**: [Name, version, source]
- **Splits**: [Train/val/test sizes and selection]
- **Preprocessing**: [Steps taken]

## Metrics & Visualizations
### Metrics to Track
- [Metric 1, Metric 2, ...]

### Planned Graphs
- **Figure 1**: [X-axis: ..., Y-axis: ..., Grouping: ..., Purpose: ...]
- **Figure 2**: ...

## Resources & Constraints
**Validated Against System**:
- **Compute**: [Needs X cores, system has Y] ✓/⚠
- **Memory**: [Needs X GB, system has Y] ✓/⚠
- **Budget**: [Estimated API cost: $X, available: $Y] ✓/⚠
- **Timeline**: [Estimated duration]

## Sample Size & Statistics
- **N**: [Number of samples, justification]
- **Significance**: [α threshold, e.g., p<0.05]
- **Power**: [If calculated]

## Performance & Caching Strategy
### Caching
- **What Gets Cached**: [e.g., API responses, model outputs, embeddings]
- **Cache Keys**: [How uniqueness determined, e.g., `hash(model_name + prompt + temperature)`]
- **Cache Location**: [e.g., `.cache/api_responses/`, per CLAUDE.md]
- **Cache Invalidation**: [When to clear, e.g., `--clear-cache` flag]
- **What Must Rerun**: [e.g., final aggregation, plotting, statistical tests]

### Concurrency & Rate Limiting
- **Concurrency Level**: [e.g., 100 concurrent API calls via `asyncio.Semaphore(100)`]
- **Rate Limits**: [Known limits, e.g., "Anthropic: 50 req/min"]
- **Backoff Strategy**:
  - **Transient errors** (429, 503): Exponential backoff (1s, 2s, 4s, 8s, 16s max)
  - **Permanent errors** (400, 401, 404): No retry, log and fail
- **Retry Logic**: [e.g., `tenacity` library with max 5 retries]

### Error Handling
| Error Type | Retry? | Strategy |
|------------|--------|----------|
| 429 Rate Limit | Yes | Exponential backoff, respect retry-after header |
| 503 Service Unavailable | Yes | Exponential backoff (max 3 retries) |
| 500 Server Error | Yes | Exponential backoff (max 3 retries) |
| 400 Bad Request | No | Log, skip sample, continue |
| 401 Unauthorized | No | Fail immediately (check API key) |
| Timeout | Yes | Retry with longer timeout (max 3 retries) |

## Reproducibility Plan
- **Random Seeds**: [Strategy, e.g., seeds=[42, 43, 44, 45, 46] for 5 runs]
- **Code Version**: [Git commit or tag]
- **Data Version**: [Hash or version number]
- **Logging**: [What gets logged, where]
- **Output Path**: [Exact directory, e.g., out/DD-MM-YYYY_HH-MM-SS_experiment_name/]

## Validation Checklist (Pre-Run Gate)
### BLOCKING (Must Pass)
- [ ] Hyperparameters documented
- [ ] Output path specified
- [ ] Hypothesis with falsification criteria
- [ ] Metrics defined
- [ ] Datasets specified
- [ ] Graphs planned
- [ ] Caching strategy defined (what cached, what rerun)
- [ ] Concurrency level specified
- [ ] Error handling & retry logic documented

### WARNING (Should Pass)
- [ ] Random seeds set
- [ ] Resources available
- [ ] Baseline comparison defined

## Open Questions
- [ ] [Unresolved question 1]
- [ ] [Unresolved question 2]
