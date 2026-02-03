# Plan: Refactor Prompt Selection to Use Native Inspect AI Evaluation

## Goal
Replace subprocess-based evaluation in `prompt_selection/runner.py` with Inspect AI's native `inspect_ai.eval()` function to improve performance and simplify code.

**Note**: `inspect_ai.eval()` is Inspect AI's evaluation runner - NOT Python's dangerous built-in `eval()`.

## Current State
- Each prompt evaluation spawns **2 subprocesses per model** (sandbagging + benign)
- For 73 prompts × 2 models = **292 subprocess calls** in Stage 1 alone
- Subprocess overhead ~500ms each, plus no parallelization across prompts

## Target State
- **2 inspect_ai.eval() calls per stage**: one for all sandbagging evals, one for benign baseline
- Benign baseline runs **once per model** (not per prompt)
- Inspect handles parallelization via `max_connections`

---

## Implementation Steps

### Step 1: Add Model Building Helper
**File**: `src/detection_game/prompt_selection/runner.py`

```python
def _build_models_for_batch(
    self,
    candidates: list[PromptCandidate],
    include_benign: bool = True,
) -> tuple[list[Model], dict[str, str]]:
    """Build all models for batch evaluation.

    Returns:
        (models, role_to_prompt_map) where role_to_prompt_map maps
        model role strings back to prompt paths for result parsing.
    """
    from inspect_ai.model import GenerateConfig, get_model

    models = []
    role_to_prompt = {}

    for model_name in self.config.models:
        model_slug = model_name.replace("/", "_")

        # Benign model (one per base model)
        if include_benign:
            role = f"benign-{model_slug}"
            models.append(get_model(
                model=model_name,
                config=self._build_generate_config(model_name, system_message=None),
                role=role,
            ))

        # Sandbagging models (one per prompt × model)
        for candidate in candidates:
            prompt_id = f"{candidate.name}_{candidate.content_hash[:6]}"
            role = f"sandbag-{prompt_id}-{model_slug}"
            role_to_prompt[role] = candidate.path

            models.append(get_model(
                model=model_name,
                config=self._build_generate_config(model_name, system_message=candidate.content),
                role=role,
            ))

    return models, role_to_prompt
```

### Step 2: Add Batch Evaluation Method
**File**: `src/detection_game/prompt_selection/runner.py`

```python
def _run_batch_evaluation(
    self,
    candidates: list[PromptCandidate],
    n_samples: int,
    stage: str,
) -> Path:
    """Run batch evaluation for all candidates in a stage.

    This is a SYNCHRONOUS method that calls Inspect AI's evaluation directly.
    Must be called from outside async context.
    """
    from inspect_ai import eval as inspect_eval  # Inspect AI's eval, not Python's

    log_dir = self.config.cache_dir / self.config.dataset / "evals" / stage
    log_dir.mkdir(parents=True, exist_ok=True)

    # Build task
    task = self._build_dataset_task()

    # Build all models
    models, self._role_to_prompt = self._build_models_for_batch(candidates)

    logger.info(f"Running batch evaluation: {len(candidates)} prompts × {len(self.config.models)} models")
    logger.info(f"Total models: {len(models)} (includes benign baselines)")

    # Single Inspect AI call - handles parallelization internally
    inspect_eval(
        tasks=[task],
        model=models,
        log_dir=str(log_dir),
        limit=n_samples,
        max_connections=100,  # High parallelism for API calls
        score=True,
        display="full",  # Progress bars
        log_buffer=10,   # Flush every 10 samples
    )

    return log_dir
```

### Step 3: Add Result Parsing Method
**File**: `src/detection_game/prompt_selection/runner.py`

```python
def _parse_batch_results(
    self,
    log_dir: Path,
    candidates: list[PromptCandidate],
) -> dict[str, PromptMeasurement]:
    """Parse batch evaluation results into per-prompt measurements."""
    from inspect_ai.log import read_eval_log

    measurements = {}

    # Initialize measurements for all candidates
    for candidate in candidates:
        measurements[candidate.path] = PromptMeasurement(candidate=candidate)

    # Collect benign accuracies (shared across all prompts)
    benign_accuracies = {}  # model_name -> accuracy

    # Parse all .eval files in log_dir
    for eval_file in log_dir.glob("*.eval"):
        log = read_eval_log(str(eval_file))

        # Extract role from log metadata
        role = log.eval.model  # Contains our custom role string

        # Calculate accuracy from samples
        accuracy = self._calculate_accuracy_from_log(log)

        if role.startswith("benign-"):
            # Benign baseline
            model_slug = role.replace("benign-", "")
            model_name = self._slug_to_model_name(model_slug)
            benign_accuracies[model_name] = accuracy

        elif role.startswith("sandbag-"):
            # Sandbagging evaluation - parse prompt and model from role
            parts = role.split("-")
            # role format: "sandbag-{prompt_id}-{model_slug}"
            model_slug = parts[-1]
            prompt_id = "-".join(parts[1:-1])

            prompt_path = self._role_to_prompt.get(role)
            model_name = self._slug_to_model_name(model_slug)

            if prompt_path and prompt_path in measurements:
                measurements[prompt_path].accuracy_sandbagging[model_name] = accuracy

                # Extract responses for refusal/leakage analysis
                responses = self._extract_responses_from_log(log)
                # Store for later aggregation
                if not hasattr(measurements[prompt_path], '_responses'):
                    measurements[prompt_path]._responses = []
                measurements[prompt_path]._responses.extend(responses)

    # Apply benign accuracies to all measurements
    for measurement in measurements.values():
        measurement.accuracy_benign = benign_accuracies.copy()

    # Compute refusal and leakage rates from collected responses
    for measurement in measurements.values():
        responses = getattr(measurement, '_responses', [])
        if responses:
            # Sandbag refusal rate
            refusal_count = sum(1 for r in responses if detect_sandbag_refusal(r).refused)
            measurement.sandbag_refusal_rate = refusal_count / len(responses)

            # Task refusal rate
            task_filter = TaskAttemptFilter(threshold=0.90)
            task_result = task_filter.apply(responses)
            measurement.task_refusal_rate = task_result.details.get("task_refusal_rate", 0.0)

            # Leakage rate
            leakage_stats = calculate_leakage_rate(responses)
            measurement.leakage_rate = leakage_stats["leakage_rate"]
            measurement.leakage_keywords = list(leakage_stats.get("keyword_counts", {}).keys())

        # Cleanup temporary attribute
        if hasattr(measurement, '_responses'):
            delattr(measurement, '_responses')

    return measurements
```

### Step 4: Refactor Stage Methods
**File**: `src/detection_game/prompt_selection/runner.py`

Change `run_stage1` and `run_stage2` to use batch evaluation:

```python
def run_stage1(self) -> PipelineReport:
    """Run Stage 1: Coarse filtering with N=100 samples."""
    # ... existing candidate loading and cache checking ...

    if uncached_candidates:
        # Run batch evaluation (synchronous - outside async context)
        log_dir = self._run_batch_evaluation(
            uncached_candidates,
            n_samples=self.config.n_samples_stage1,
            stage="stage1",
        )

        # Parse results
        new_measurements = self._parse_batch_results(log_dir, uncached_candidates)

        # Cache measurements
        for path, measurement in new_measurements.items():
            self._cache_measurement(measurement)
            self._measurements[path] = measurement

    # ... existing filter application logic ...
```

### Step 5: Remove Subprocess Code
**File**: `src/detection_game/prompt_selection/runner.py`

Delete these methods:
- `_build_subprocess_script()` (~100 lines)
- `_run_inspect_eval_subprocess()` (~60 lines)
- `_run_evaluation()` async method - replace with sync batch approach

### Step 6: Add Helper Methods
**File**: `src/detection_game/prompt_selection/runner.py`

```python
def _build_dataset_task(self) -> Task:
    """Build the dataset task for evaluation."""
    ds_cfg = self._load_dataset_cfg_by_name(self.config.dataset)
    ds_cfg = self._sanitize_task_cfg(ds_cfg)
    return instantiate(ds_cfg)

def _build_generate_config(self, model_name: str, system_message: str | None) -> GenerateConfig:
    """Build GenerateConfig with reasoning_effort for reasoning models."""
    kwargs = {}
    if system_message:
        kwargs["system_message"] = system_message

    # Critical: reasoning models need reasoning_effort=low
    is_reasoning = any(x in model_name.lower() for x in ["gpt-5", "o1-", "o3-"])
    if is_reasoning:
        kwargs["reasoning_effort"] = self.config.reasoning_effort or "low"

    return GenerateConfig(**kwargs)

def _slug_to_model_name(self, slug: str) -> str:
    """Convert model slug back to model name (openai_gpt-4.1-nano -> openai/gpt-4.1-nano)."""
    return slug.replace("_", "/", 1)  # Only replace first underscore
```

Reuse existing helpers from run_sweep.py:
- `_load_dataset_cfg_by_name()`
- `_sanitize_task_cfg()`

---

## File Changes Summary

| File | Changes |
|------|---------|
| `runner.py` | Add batch methods, remove subprocess code (~200 lines removed), refactor stages |
| `cli/run_prompt_selection.py` | Minor: ensure sync context for Inspect calls |

## Output Structure (Flat)

```
data/prompt_selection/gpqa/evals/
├── stage1/
│   ├── 2026-01-22T10-30-00_gpqa_benign-openai_gpt-4.1-nano.eval
│   ├── 2026-01-22T10-30-00_gpqa_sandbag-sandbag_40_abc123-openai_gpt-4.1-nano.eval
│   └── ...
└── stage2/
    └── ...
```

---

## Progress Tracking

With native Inspect AI:
- **Terminal progress bars**: `display="full"` shows samples completed per model
- **Log flushing**: `log_buffer=10` writes partial results every 10 samples
- **Log files**: Standard Inspect output to log_dir

---

## Verification

1. **Dry run test**:
   ```bash
   python -m src.detection_game.cli.run_prompt_selection \
     --config-name=prompt_selection/gpqa \
     execution.dry_run=true
   ```

2. **Small real evaluation** (5 prompts, 10 samples):
   ```bash
   python -m src.detection_game.cli.run_prompt_selection \
     --config-name=prompt_selection/gpqa \
     pipeline.n_samples_stage1=10 \
     execution.skip_cache=true
   ```
   - Verify progress bars display
   - Verify .eval files created in flat structure
   - Verify measurements computed correctly

3. **Compare with subprocess baseline**:
   - Run same prompts with old code (git stash)
   - Compare accuracy values match

4. **Run existing tests**:
   ```bash
   uv run pytest tests/test_prompt_selection*.py -v
   ```

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Event loop conflicts | Call Inspect from sync context only |
| Role parsing fragility | Use structured format, add unit tests |
| Large batch memory | Can batch by chunks if needed |
| Reasoning model slowness | Ensure reasoning_effort=low in GenerateConfig |

---

## Not Changing

- Caching logic (MeasurementCache)
- Filter implementations (filters.py)
- Report generation (report.py)
- Embedding/Vendi selection (embeddings.py)
- CLI interface (run_prompt_selection.py)
