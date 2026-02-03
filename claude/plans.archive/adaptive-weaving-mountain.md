# Plan: Fill Prompt Selection TODOs in Paper

## Summary

Address three categories of TODOs in `main.tex` related to the prompt selection pipeline:
1. Fill TBD placeholders with concrete numbers (catalogue size, per-model-dataset counts)
2. Add pass/rejection rates at each pipeline stage
3. Add full prompt transcripts in the appendix for all selected prompts

## Changes

### 1. Fill TBD at line 992: Prompts per model-dataset combination

Replace:
```
This yields [TBD] prompts per model-dataset combination.
```
With concrete counts from the selection data:
- GPQA: 7 (gpt-4.1-nano), 10 (gpt-5-nano)
- MATH: 10 (gpt-4.1-nano), 10 (gpt-5-nano)
- USACO: 5 (gpt-4.1-nano), 8 (gpt-5-nano)

Write this as a sentence like: "This yields 5–10 prompts per model-dataset combination (Table X)." and add a small table showing the breakdown.

### 2. Fill TBD at line 996: GPQA selected prompts section

Replace:
```
For GPQA, [TBD] prompts passed all selection criteria. Selected prompts and accuracy drops per model: [TBD].
```
With actual counts and a table of prompt names + accuracy drops per model.

### 3. Add pipeline funnel statistics

After the 4-filter enumeration (line 988), add a paragraph or table showing pass rates at each stage. Data from exploration:

| Stage | GPQA | MATH | USACO |
|-------|------|------|-------|
| Initial applicable candidates | ~77 | ~100 | TBD (verify) |
| After refusal filter | 45 (58%) | 100 (100%) | TBD |
| After sandbagging effectiveness | 36 (47%) | 15 (15%) | TBD |
| After stealth filter | 29 (38%) | 15 (15%) | TBD |
| After Vendi selection (gpt-4.1-nano / gpt-5-nano) | 7 / 10 | 10 / 10 | 5 / 8 |

Note: Numbers above are approximate from exploration. Will verify all from data files during implementation. USACO funnel stats need extraction from `hub/data/prompt-selection/usaco/`.

### 4. Add MATH and USACO selected prompt subsections (after GPQA)

Add `\subsubsection{MATH Selected Prompts}` and `\subsubsection{USACO Selected Prompts}` with the same format as GPQA: brief intro with counts, then full prompt transcripts.

### 5. Expand prompt transcripts in appendix

Currently only 2 prompts shown (aggressive_sandbagging, consistent_sandbagging). Need to add full text for all unique selected prompts across datasets. From the data:

**Key prompts to add** (deduplicated across datasets):
- `off_by_one` (deterministic errors)
- `fixed_confusion_matrix` (deterministic errors)
- `correct_reasoning_wrong_extraction` (deterministic errors)
- `second_guesser` (persona)
- `sandbag_0` (paper baseline, van der Weij)
- `zero_accuracy_explicit` (aggressive)
- `unit_confusion` (math-specific)
- `chaotic_coder` (coding-specific)
- `semantic_anchoring` (consistent sandbagging)
- Others as needed from selection results

Each prompt needs its full system prompt text in a `\begin{quote}\small ... \end{quote}` block with a `\paragraph{}` header.

### 6. Add GPQA/USACO paraphrase examples (line 805)

Remove the TODO comment and add real paraphrase examples for GPQA and USACO, matching the existing MATH format (lines 791-803).

## Files to modify

- `main.tex` — all changes are in the appendix sections (~lines 545-1056)

## Verification

- Run `bash src/compile.sh` to ensure LaTeX compiles without errors
- Check PDF output for formatting of new tables and prompt blocks

## Data sources

- Prompt catalogue: `hub/src/detection_game/configs/system_prompt/CATALOGUE.yaml` (89 prompts, paper says 98 — verify)
- Selection results: `hub/data/prompt-selection/` and `hub/specs/icml-baseline-expts/`
- Individual prompt YAML files: `hub/src/detection_game/configs/system_prompt/{family}/{name}.yaml`

## Key design decisions

1. **Dataset-dependent candidate counts**: The 98-prompt catalogue includes dataset-specific prompts (22 math-only, 6 coding-only, 2 MCQ-only, 4 WMDP-only). So the number of applicable candidates per dataset differs. The funnel table (step 3) must be per-dataset with dataset-specific starting counts. Will verify exact applicable counts from the CATALOGUE.yaml `datasets` field.
2. **89 vs 98**: Need to verify during implementation — could be 98 total entries vs 89 after dedup, or CATALOGUE may have been pruned since paper was written.
3. **All unique prompts**: Full transcripts for every selected prompt across all datasets (user confirmed). Read from YAML files during implementation.
