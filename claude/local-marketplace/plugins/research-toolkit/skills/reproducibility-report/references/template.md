# Reproducibility Report Template

Write to: `out/{experiment_dir}/reproducibility.md`

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

## Example: Filled-In Model Configuration

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
