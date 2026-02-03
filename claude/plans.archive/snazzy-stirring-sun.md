# Plan: GPQA Score Extraction Script with Process Parallelism

## Goal
Update `scripts/extract_gpqa_scores.sh` to:
1. Automatically find the latest successful .eval runs
2. Validate runs match expected spec values
3. Use aggressive process parallelism (32 CPUs available)

## Key Changes

### 1. Validation Phase (Python with ProcessPoolExecutor)
- Use `ProcessPoolExecutor` (not ThreadPoolExecutor) to bypass GIL
- Why processes over threads/async:
  - Local filesystem I/O doesn't benefit from async (syscalls still block)
  - `read_eval_log()` has CPU work (decompression, parsing)
  - Processes give true parallelism for both I/O and CPU
- Parallelize across all 12 method/model/split combinations (12 processes)
- Within each combo, parallelize .eval file reads (up to 16 workers)
- Early exit: once a successful directory is found, stop checking older ones

### 2. Expected Values from Spec
From `specs/icml-baseline-expts/dataset-specific-sandbagging-prompts.md`:
- 4.1-nano: 7 prompts + 1 benign = 8 .eval files
- 5-nano: 10 prompts + 1 benign = 11 .eval files
- GPQA dev: 79 samples, test: 119 samples
- C3: 5 paraphrase strategies, 5 epochs → samples = original × 5 × 5
- BP: 4 follow-ups, 5 epochs → samples = original × 4 × 5
- LD: 48 follow-ups, varies

### 3. Extraction Phase (Bash background jobs)
- Launch all extraction commands as background jobs (`&`)
- ~24 parallel extraction jobs (C3×8 + LD×8 + BP×4 + TM×2)
- Track success/failure per job
- Wait for all jobs, report results

### 4. Output
- Print validation results with ✓/✗ indicators
- Show: directory name, file count, sample count, message count
- Print extraction job status as they complete

## Files to Modify
- `scripts/extract_gpqa_scores.sh` - complete rewrite with parallelism

## Verification
```bash
# Test validation only
bash scripts/extract_gpqa_scores.sh --dry-run

# Full run
bash scripts/extract_gpqa_scores.sh

# Check outputs
ls -la out/gpqa_*.csv
```
