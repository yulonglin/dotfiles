# Plan: Add Epoch Support to Prompt Selection Pipeline

## Goal
Add epoch support so GPQA (79 dev samples) can get more statistical power via repeated evaluations.

## Key Decision: Use epochs in cache key (simpler)

**Approach:**
- epochs=1 (default): no suffix → `..._dev.json` (backward compatible)
- epochs>1: add suffix → `..._dev_e4.json`

Existing caches (no suffix) are treated as epochs=1, so no migration needed for default case.

## Implementation

### 1. Add epochs to PipelineConfig (runner.py:134)
```python
epochs: int = 1  # Repeat samples N times for more statistical power
```

### 2. Pass epochs to inspect_eval (runner.py:405)
```python
epochs=self.config.epochs if self.config.epochs > 1 else None,
```

### 3. Update cache key to include epochs (cache.py)

**CachedMeasurement** - add epochs field:
```python
epochs: int = 1
```

**_get_cache_path** - add epochs to filename (only if > 1):
```python
def _get_cache_path(self, ..., epochs: int = 1) -> Path:
    ...
    # Add epochs suffix only if > 1 (backward compatible)
    if epochs > 1:
        filename = f"..._{split}_e{epochs}.json"
    else:
        filename = f"..._{split}.json"  # No suffix for epochs=1
```

**get() / store()** - add epochs parameter, pass through to _get_cache_path

No migration script needed - old files (no suffix) = epochs=1 by convention.

### 5. Update Hydra configs

**base.yaml:**
```yaml
pipeline:
  epochs: 1
```

**gpqa.yaml:**
```yaml
pipeline:
  epochs: 4  # 79 × 4 = 316 effective samples
```

### 6. Update CLI config conversion
```python
epochs=pipeline.get("epochs", 1),
```

## Files to Modify

| File | Change |
|------|--------|
| `runner.py` | Add epochs to PipelineConfig, pass to inspect_eval |
| `cache.py` | Add epochs to CachedMeasurement, _get_cache_path, get/store |
| `run_prompt_selection.py` | Add epochs to config conversion |
| `configs/prompt_selection/base.yaml` | Add epochs: 1 (default) |
| `configs/prompt_selection/gpqa.yaml` | Add epochs: 4 |

## Execution Order

1. **Update code** (cache.py, runner.py, configs)
2. **Test with dry_run** (verify config flows, old cache still works)
3. **Full run for GPQA gpt-4.1-nano** (with epochs=4)

## Verification
```bash
# 1. Dry run - verify old cache still works (epochs=1 implied)
python -m src.detection_game.cli.run_prompt_selection \
  --config-name=prompt_selection/gpqa \
  'pipeline.models=[openai/gpt-4.1-nano]' \
  pipeline.epochs=1 \
  execution.dry_run=true

# 2. Full run with epochs=4
python -m src.detection_game.cli.run_prompt_selection \
  --config-name=prompt_selection/gpqa \
  'pipeline.models=[openai/gpt-4.1-nano]'

# 3. Check new cache files have _e4 suffix
ls data/prompt_selection/gpqa/measurements/ | grep "_e4" | head -3
```

## Expected Outcome
- Old caches (no suffix) work as epochs=1 (backward compatible)
- New runs with epochs=4 create `..._e4.json` files
- gpt-4.1-nano on GPQA: more prompts passing due to 316 samples (tighter CIs)
