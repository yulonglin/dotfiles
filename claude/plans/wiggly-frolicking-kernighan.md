# Plan: Fix Paraphrasing Implementation Issues

## Summary
Fix 5 issues identified by code review: 2 CLAUDE.md violations and 3 bugs.

**Deferred**: API response caching (#6) - being handled by another session.

---

## Issues & Fixes

### 1. CRITICAL: Silent fallback in `paraphrasing_solver.py` (CLAUDE.md violation)

**Files**: `src/detection_game/dataset/paraphrasing_solver.py`

**Problem**: Lines 97-108 and 287-297 catch `Exception` and silently continue with original prompt. This masks failures and corrupts experiment results.

**Fix**: Remove try/except blocks entirely. Let `ParaphrasingError` propagate (consistent with `paraphraser.py`).

```python
# BEFORE (lines 73-108):
try:
    paraphrased = await paraphrase_prompt(...)
    # ... update state
except Exception as e:
    print(f"Warning: Full prompt paraphrasing failed: {e}")
    state.metadata["full_prompt_paraphrasing"] = {..., "fallback_to_original": True}

# AFTER:
paraphrased = await paraphrase_prompt(...)
state.user_prompt.text = paraphrased
state.metadata["full_prompt_paraphrasing"] = {...}
```

Same fix for lines 263-297 in `multiple_choice_with_paraphrasing()`.

---

### 2. CRITICAL: Silent exception in `paraphraser_config.py` (CLAUDE.md violation)

**Files**: `src/detection_game/dataset/paraphraser_config.py`

**Problem**: Line 330-332 silently ignores YAML parse errors.

**Fix**: Log warning with specific exception type:

```python
# BEFORE:
except Exception:
    pass

# AFTER:
except yaml.YAMLError as e:
    logger.warning(f"Failed to parse {file}: {e}")
```

---

### 3. BUG: Dead code with type confusion - `create_paraphrased_dataset()`

**Files**: `src/detection_game/dataset/paraphraser.py`

**Problem**: Lines 268-315 define `create_paraphrased_dataset()` (sync wrapper) which:
- Returns `asyncio.Task` when called from async context, violating its `List[Sample]` return type
- Is **not used anywhere** in production (only `create_paraphrased_dataset_from_task()` is used in `run_sweep.py`)
- Test file references it but doesn't actually call it

**Fix**: Delete the dead function entirely (lines 268-315). It's unused and has a type bug.

```python
# DELETE this entire function (lines 268-315):
def create_paraphrased_dataset(
    original_dataset: List[Sample],
    ...
) -> List[Sample]:
    ...
```

Also update `tests/test_paraphraser.py` to remove the unused test class `TestCreateParaphrasedDataset`.

---

### 4. BUG: Wrong path in `list_available_versions()`

**Files**: `src/detection_game/dataset/paraphraser_config.py`

**Problem**: Line 198 uses `parent` instead of `parent.parent`, pointing to wrong directory.

**Fix**:
```python
# BEFORE:
config_dir = Path(__file__).parent / "configs" / "paraphraser_prompt"

# AFTER:
config_dir = Path(__file__).parent.parent / "configs" / "paraphraser_prompt"
```

Same fix for `get_all_known_strategies()` at line 318.

---

### 5. BUG: Use OpenAI directly instead of OpenRouter

**Files**: `src/detection_game/cli/run_sweep.py`

**Problem**: `PARAPHRASER_MODEL = "openrouter/openai/gpt-4.1-nano"` doesn't work correctly with the existing OpenAI-optimized code path.

**Fix**: Simply change the model constant to use OpenAI directly:

```python
# BEFORE (line 60):
PARAPHRASER_MODEL = "openrouter/openai/gpt-4.1-nano"

# AFTER:
PARAPHRASER_MODEL = "openai/gpt-4.1-nano"
```

This uses the fast AsyncOpenAI path that's already implemented and properly validated.

---

### 6. DEFERRED: API response caching for paraphrasing

Being handled by another Claude Code session. Not in scope for this plan.

---

## Files to Modify

| File | Changes |
|------|---------|
| `src/detection_game/dataset/paraphrasing_solver.py` | Remove try/except fallbacks (lines 73-108, 263-297) |
| `src/detection_game/dataset/paraphraser_config.py` | Fix path bug (lines 198, 318), add logging for YAML errors (line 330) |
| `src/detection_game/dataset/paraphraser.py` | Delete dead `create_paraphrased_dataset()` function (lines 268-315) |
| `src/detection_game/cli/run_sweep.py` | Change `PARAPHRASER_MODEL` to `openai/gpt-4.1-nano` (line 60) |
| `tests/test_paraphraser.py` | Remove unused `TestCreateParaphrasedDataset` class |

---

## Testing

1. Run existing tests: `uv run pytest tests/`
2. Test paraphrasing with OpenAI model manually (small sample)
3. Verify errors propagate (no silent fallbacks) by intentionally triggering a failure
