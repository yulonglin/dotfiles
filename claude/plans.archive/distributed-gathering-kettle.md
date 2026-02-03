# Plan: Regenerate GPQA Prompt Selection with Proper CI

## Goal
1. Commit the glob fix (use latest .eval file only)
2. Run prompt selection for both gpt-4.1-nano and gpt-5-nano with `skip_cache=true`
3. Get updated reports with proper 95% CI and Vendi scores

## Steps

### Step 1: Commit the glob fix
```bash
git add src/detection_game/prompt_selection/runner.py
git commit -m "fix(prompt-selection): use latest .eval file only, not all historical runs"
```

### Step 2: Run prompt selection for gpt-4.1-nano
```bash
python -m src.detection_game.cli.run_prompt_selection \
  --config-name=prompt_selection/gpqa \
  execution.skip_cache=true
```

### Step 3: Run prompt selection for gpt-5-nano
```bash
python -m src.detection_game.cli.run_prompt_selection \
  --config-name=prompt_selection/gpqa-gpt5-nano \
  execution.skip_cache=true
```

## Expected Output
- Updated cache files with `benign_scores` and `sandbag_scores` lists
- Reports showing:
  - Mean gap (pp)
  - SEM (paired)
  - 95% CI that properly excludes 0 for passing prompts
  - Vendi diversity scores (cumulative and marginal)
  - All threshold information

## Verification
- Check that CI column shows actual ranges like `(12.5, 22.3)` instead of `n/a*`
- Check that Vendi selection table is populated
- Reports saved to `out/prompt_selection/gpqa/`
