---
name: reproducibility-report
description: Generate reproducibility reports for LLM/ML experiments. Use when (1) completing an experiment, (2) sharing results with collaborators, (3) preparing for publication, (4) archiving experiment runs, or (5) user asks for reproducibility documentation. Auto-extracts from code/configs/Hydra, asks for gaps.
---

# Reproducibility Report Generator

Generate comprehensive reproducibility reports for ML/LLM experiments. Based on requirements from [NeurIPS Paper Checklist](https://neurips.cc/public/guides/PaperChecklist), [ACL Responsible NLP Research](http://aclrollingreview.org/responsibleNLPresearch/), and [ML Reproducibility Checklist](https://www.cs.mcgill.ca/~jpineau/ReproducibilityChecklist.pdf).

## When to Use This Skill

Trigger after:
- Completing an experiment or series of related experiments
- Before sharing results with collaborators
- Before writing up findings for publication
- When archiving experiment runs

## Fundamental Principles

**Completeness Over Convenience**: A reproducibility report should contain everything needed to replicate results, even if some information seems obvious. Future you (or a collaborator) will thank present you.

**Extract, Don't Fabricate**: Auto-extract from code, configs, and logs. For anything missing, ask explicitly rather than assuming or inventing values. Leave `{placeholder}` markers for unknown items.

**Prioritize Critical Information**: Not all reproducibility concerns are equal. Model identity and prompts are critical; compute costs are helpful but not essential. Focus effort on what would block replication.

**Document the Delta**: If this experiment differs from a baseline or prior run, explicitly note what changed and why.

## Workflow

### 1. Auto-Extract Information

First, automatically gather reproducibility information from:

**Code & Configs:**
- `src/configs/` - Hydra config files (model, task, prompts)
- `src/configs/prompts/` - Full prompt templates
- `.hydra/config.yaml` and `.hydra/overrides.yaml` in output dirs
- Python files for sampling parameters, API calls, caching logic

**Experiment Outputs:**
- `out/*/` directories - Hydra logs, results.jsonl
- `.cache/` directory structure - Caching strategy evidence

**Environment:**
- `pyproject.toml` or `requirements.txt` - Dependencies
- Git commit hash and dirty state

### 2. Ask Targeted Questions for Gaps

For any missing critical information, ask the user directly. Prioritize:
- Items that cannot be inferred from code
- Items where multiple interpretations exist
- Limitations and assumptions not documented in code

### 3. Generate Report

Write to: `out/{experiment_dir}/reproducibility.md`

## Report Template

```markdown
# Reproducibility Report: {Experiment Name}

Generated: {timestamp}
Experiment dir: {path}
Git commit: {hash} {dirty_status}

## Quick Reference

**To reproduce this experiment:**
```bash
{exact_command}
```

**Key data paths:**
- Input: {input_path}
- Output: {output_path}
- Cache: {cache_path}

---

## 1. Model Configuration

### Model Identity
- **Model ID**: {exact_model_id} (e.g., `claude-3-5-sonnet-20241022`, `gpt-4-0613`)
- **Provider/Endpoint**: {provider} (e.g., Anthropic API, OpenAI API, vLLM, Together AI)
- **Base URL**: {base_url} (if non-default)
- **API Access Date**: {date_range}
- **System Fingerprint**: {fingerprint} (if available, for OpenAI)

### Sampling Parameters
| Parameter | Value |
|-----------|-------|
| Temperature | {temp} |
| Top-p | {top_p} |
| Top-k | {top_k} |
| Max tokens | {max_tokens} |
| Seed | {seed} |
| Stop sequences | {stop_seqs} |

### Token & Context Settings
- **Context window used**: {context_window}
- **Max input tokens**: {max_input}
- **Max output tokens**: {max_output}
- **Truncation strategy**: {truncation}

---

## 2. Prompts

### System Prompt
```
{system_prompt_full}
```

### User Prompt Template
```
{user_prompt_template}
```

### Assistant Prefill (if any)
```
{assistant_prefill}
```

### Few-shot Examples (if any)
{few_shot_examples}

### Prompt Source
- File: {prompt_file_path}
- Commit: {prompt_commit}

---

## 3. Data

### Dataset
- **Source**: {dataset_source}
- **Version/Date**: {dataset_version}
- **Size**: {n_samples} samples
- **Train/Val/Test Split**: {split_info}

### Data Processing
- **Filtering criteria**: {filtering}
- **Preprocessing steps**: {preprocessing}
- **Exclusions**: {exclusions}

### Data Paths
- Raw: `{raw_path}`
- Processed: `{processed_path}`
- Splits: `{splits_path}`

---

## 4. Experimental Setup

### Compute Resources
- **Hardware**: {hardware}
- **GPU hours**: {gpu_hours}
- **Total API cost**: ${cost}
- **Wall time**: {wall_time}

### Execution Details
- **Concurrency**: {concurrency} parallel calls
- **Retry strategy**: {retry_strategy}
- **Rate limits**: {rate_limits}

### Caching
- **Cache strategy**: {cache_strategy}
- **Cache location**: {cache_path}
- **Cache hit rate**: {hit_rate}%
- **Cache key method**: {cache_key_method}

---

## 5. Results & Statistics

### Main Results
{main_results_table}

### Statistical Reporting
- **Error bars**: {error_bar_type} (95% CI / std dev / std error)
- **Number of runs**: {n_runs}
- **Seeds used**: {seeds}
- **Statistical tests**: {tests}
- **p-values**: {p_values}

### Known Variance Sources
- {variance_sources}

---

## 6. Environment

### Dependencies
```
{dependencies}
```

### Full Command
```bash
cd {project_root}
{full_command}
```

### Config Files Used
- Main config: `{config_path}`
- Overrides: `{overrides}`

---

## 7. Limitations & Assumptions

### Scope Limitations
- {scope_limitations}

### Assumptions That May Not Hold in Practice
- {assumptions}

### Known Issues
- {known_issues}

### What Would Change Results
- {sensitivity_factors}

---

## 8. Reproduction Checklist

- [ ] Dependencies installed (`uv sync` or `pip install -r requirements.txt`)
- [ ] Data available at specified paths
- [ ] API keys configured for {provider}
- [ ] Cache cleared if needed (`--clear-cache`)
- [ ] Same model version still available

---

## 9. Verification (After Reproduction)

- [ ] Results within expected variance (±{expected_variance}%)
- [ ] Same number of samples processed ({n_samples})
- [ ] Cache behavior as expected (hit rate ~{expected_hit_rate}%)
- [ ] API costs roughly match (${expected_cost} ± 20%)
- [ ] No new errors or warnings

## Notes

{additional_notes}
```

## Checklist Items to Verify

### Critical (Must Have)

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

### Important (Should Have)

**Statistics:**
- [ ] Error bars with explanation (CI vs std)
- [ ] Number of runs/seeds
- [ ] Statistical significance tests
- [ ] Effect sizes

**Compute:**
- [ ] Hardware description
- [ ] Runtime
- [ ] API costs
- [ ] Concurrency settings

**Caching:**
- [ ] Cache strategy
- [ ] Cache hit/miss rates
- [ ] How to clear cache

### Helpful (Nice to Have)

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

## LLM-Specific Reproducibility Concerns

### Stochasticity
- Even with temperature=0 and seed, LLMs can be non-deterministic
- Document system_fingerprint (OpenAI) to detect backend changes
- Note API access dates - models may be updated or deprecated

### Prompt Sensitivity
- Minor prompt changes can dramatically affect results
- Document exact prompts including whitespace, newlines, special chars
- Note any prompt engineering iterations

### Model Version Drift
- APIs update models without changing IDs (especially "latest" aliases)
- Prefer versioned model IDs (e.g., `gpt-4-0613` not `gpt-4`)
- Document the exact date range of API calls

### Provider-Specific Metadata to Capture

| Provider | Metadata Field | Purpose |
|----------|---------------|---------|
| OpenAI | `system_fingerprint` | Detect backend model changes |
| OpenAI | `seed` parameter | Request-level reproducibility |
| Anthropic | Response headers | API version, rate limit info |
| All | `usage.prompt_tokens` | Verify tokenization, cost |
| All | `usage.completion_tokens` | Detect truncation |
| All | Response timestamps | Batch vs streaming, latency |

### Context and Token Handling
- How are long inputs truncated?
- Are outputs cut off at max_tokens?
- What tokenizer assumptions exist?

### Caching Considerations
- Cached responses may mask model updates
- Document cache key strategy (what fields are included?)
- Note whether caching affects reported metrics

### Multi-Provider and Fallback
- If using fallback providers (e.g., OpenAI → Anthropic on rate limit), document which provider served each request
- For ensembles, document: which models, combination method, voting/averaging strategy
- Note per-request provider logging for cost attribution and reproducibility
- Different providers have different tokenizers - document any tokenization assumptions

## Example: Filled-In Model Configuration

Here's a concrete example of a properly filled section:

```markdown
## 1. Model Configuration

### Model Identity
- **Model ID**: `claude-3-5-sonnet-20241022`
- **Provider/Endpoint**: Anthropic API
- **Base URL**: https://api.anthropic.com/v1 (default)
- **API Access Date**: 2024-12-15 to 2024-12-20
- **System Fingerprint**: N/A (Anthropic doesn't provide this)

### Sampling Parameters
| Parameter | Value |
|-----------|-------|
| Temperature | 0.0 |
| Top-p | 1.0 |
| Top-k | N/A |
| Max tokens | 1024 |
| Seed | N/A (not supported by Anthropic) |
| Stop sequences | None |

### Token & Context Settings
- **Context window used**: 8192 tokens (of 200k available)
- **Max input tokens**: 7168 (prompt + examples)
- **Max output tokens**: 1024
- **Truncation strategy**: Truncate oldest few-shot examples first
```

## Example Usage

**User**: "Generate a reproducibility report for the experiment in `out/241221_143052_refusal_detection/`"

**Skill Response**:
1. Read Hydra configs from `.hydra/` subdirectory
2. Extract prompts from referenced config files
3. Parse results.jsonl for sample sizes, metrics
4. Check git status for commit hash
5. Identify gaps (e.g., API costs, assumptions)
6. Ask user for missing critical information
7. Write `out/241221_143052_refusal_detection/reproducibility.md`

## Integration with Other Tools

- **data-analyst agent**: Can compute statistics for the report
- **research-skeptic agent**: Can identify unstated assumptions
- **research-presentation skill**: Shares prompt documentation requirements
- **Hydra logs**: Primary source for config and command extraction

## Quick Reference

When generating a report, prioritize:

1. **Model identity** - Exact ID with version suffix, not aliases like "gpt-4" or "claude-3-sonnet"
2. **Full prompts** - Verbatim, including whitespace and special characters
3. **Data paths and versions** - Exact file paths, dataset versions, commit hashes
4. **Exact reproduction command** - Copy-pasteable, including all flags and overrides
5. **Known limitations** - What assumptions might not hold in practice?

**Always ask for:**
- API costs (approximate is fine)
- Unstated assumptions
- Failed approaches that were tried
- Prompt iteration history (if relevant)
