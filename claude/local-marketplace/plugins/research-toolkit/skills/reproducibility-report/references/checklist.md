# Reproducibility Checklist

## Critical (Must Have)

**Model & API:**
- [ ] Exact model ID with version/date suffix
- [ ] All sampling parameters
- [ ] API endpoint and base URL
- [ ] Seed for reproducibility (if stochastic)

**Prompts:**
- [ ] Full system prompt (verbatim)
- [ ] User prompt template with variable placeholders
- [ ] Any assistant prefills
- [ ] Few-shot examples (if used)

**Data:**
- [ ] Dataset source and version
- [ ] Sample sizes (total, per split)
- [ ] Filtering/exclusion criteria
- [ ] Preprocessing steps

**Execution:**
- [ ] Exact command to run
- [ ] All config file paths
- [ ] All CLI overrides
- [ ] Environment variables needed

## Important (Should Have)

**Statistics:** (see `~/.claude/docs/ci-standards.md`)
- [ ] 95% CI with n = questions (not seeds)
- [ ] Number of runs/seeds
- [ ] Paired comparisons for same-question tests
- [ ] Statistical significance tests

**Compute:**
- [ ] Hardware description
- [ ] Runtime
- [ ] API costs
- [ ] Concurrency settings

**Caching:**
- [ ] Cache strategy
- [ ] Cache hit/miss rates
- [ ] How to clear cache

## Helpful (Nice to Have)

- [ ] Known variance sources
- [ ] Sensitivity analysis
- [ ] Comparison with alternative approaches
- [ ] Hyperparameter search details

## Common Gaps to Ask About

When auto-extraction can't find information, ask:

1. **Model changes**: "Did you use the same model throughout, or did the API model change during the experiment?"

2. **Prompt iteration**: "Is this the final prompt, or were there iterations? Should we document prompt evolution?"

3. **Data filtering rationale**: "Why were these N samples excluded? Is this documented?"

4. **Assumptions**: "What assumptions does this experiment make that might not hold in other contexts?"

5. **Negative results**: "Were there failed runs or approaches? Should they be documented?"

6. **Cost tracking**: "Do you have API cost logs? Approximate total spend?"
