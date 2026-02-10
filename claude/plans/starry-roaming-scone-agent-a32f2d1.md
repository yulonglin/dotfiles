# Plan: Explore Sandbagging Detection Data from Annotator's Perspective

## Goal
Write a Python script that loads real eval data and outputs a clear summary of what an annotator would actually see: questions, responses, paraphrases, scores, follow-ups.

## Script Structure (`/tmp/claude/explore_data.py`)

### Part 1: Sandbagging Run (GPQA CoT format ablation)
- Load ONE eval file from `logs/runs/gpqa-format-ablation-cot-20260126_121722/`
- For first 3 samples, extract:
  - `sample.id`
  - User message (the question)
  - Assistant message (the model's response)
  - All available scores (names + values)
  - Metadata fields
  - Whether it's sandbagging (via system prompt detection)

### Part 2: Benign Run (GPQA CoT benign)
- Load ONE eval file from `logs/runs/gpqa-format-ablation-cot-benign-20260126_214954/`
- Same extraction as Part 1

### Part 3: Lie Detector Run
- Load from `logs/runs/gpqa-lie-detector-4.1nano-test-20260125_041419/`
- Show ONE sample's full follow-up Q&A conversation format
- Extract: original question, model's answer, follow-up questions + responses

### Part 4: Score CSVs
- Read first few rows from `out/c3_gpqa_cot_sandbag.csv`
- Read first few rows from `out/tm_gpqa_cot.csv`
- Show column names and example data

### Implementation Notes
- Use `inspect_ai.log.read_eval_log()` to load `.eval` files
- Use `src.detection_game.utils.eval_log_utils.detect_sandbagging_from_log()` for label detection
- Use `src.detection_game.utils.lie_detector_utils.extract_followup_responses_from_log()` for lie detector data
- Run with `uv run python /tmp/claude/explore_data.py` from the dev/ directory
- Print clear section headers and truncate long text for readability
