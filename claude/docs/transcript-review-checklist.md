# Transcript Review Checklist

Canonical reference for reviewing experiment transcripts. Used by `transcript-reviewer` agent after `check-transcripts` extracts samples.

---

## 1. Normalized Transcript Format

Output of `check-transcripts` — one file per sample in `transcript_review/samples/`:

```json
{
  "id": "sample_042",
  "input": "prompt or task description",
  "output": "model's full response",
  "score": 0.0,
  "score_label": "fail",
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user", "content": "..."},
    {"role": "assistant", "content": "..."}
  ],
  "metadata": {
    "source_format": "inspect_eval",
    "original_id": "..."
  }
}
```

Summary in `transcript_review/summary.json` — aggregate findings and sample inventory.

## 2. Source Formats

| Format | Extension | Structure | Score Field |
|--------|-----------|-----------|-------------|
| Inspect AI | `.eval` (gzip) | `samples[].messages`, `samples[].scores` | `scores.<scorer>.value` |
| JSONL | `.jsonl` | One JSON per line | Configurable (`--score-field`) |
| Directory | dir of `.json` | One file per sample | Varies |
| JSON | `.json` | `samples[]` or `results[]` array | Varies |
| Raw text | `.log`/`.txt` | Delimiter-separated | None (manual) |

## 3. Per-Transcript Checklist

### 3.1 Scorer Misconfiguration
- [ ] Score matches content? (model correct → high score, model wrong → low score)
- [ ] Scoring function appropriate for task? (exact match vs contains vs model-graded)
- [ ] Edge cases handled? (whitespace, punctuation, case, trailing period)
- [ ] Model-graded: is grader prompt specific enough? Same model as subject?
- [ ] Partial credit awarded when appropriate?

### 3.2 Instruction Misunderstanding
- [ ] Model answering the right question?
- [ ] Model completing the task vs. describing the task?
- [ ] System prompt clear and unambiguous?
- [ ] Few-shot examples (if any) consistent with expected behavior?
- [ ] Task genuinely ambiguous? (flag for researcher, not model's fault)

### 3.3 Eval Awareness
- [ ] Any explicit mention of being tested/evaluated?
- [ ] Unusually cautious or hedging behavior?
- [ ] Strategic behavior inconsistent with task instructions?
- [ ] References to benchmarks, evaluation frameworks, or testing?

### 3.4 Refusals
- [ ] Explicit refusal present?
- [ ] Soft refusal (caveats without completing task)?
- [ ] Refusal rate: isolated or systematic?
- [ ] Refusal justified (genuine safety concern) or over-cautious?

### 3.5 Tool/Environment Errors
- [ ] Any error messages in tool call responses?
- [ ] Sandbox/permission failures?
- [ ] API timeouts or rate limits?
- [ ] Retry loops consuming context?

### 3.6 Format/Parsing
- [ ] Score is null/None when output exists? (extraction failure)
- [ ] Response truncated? (check if near max_tokens)
- [ ] Output format matches scorer expectations?
- [ ] Multi-part answer — was full answer captured?

## 4. Red-Flag Patterns

Grep-able strings to search for in transcripts:

**Refusals:**
- `I cannot`, `I can't`, `I'm sorry`, `I apologize`
- `as an AI`, `as a language model`, `I'm not able to`
- `I must decline`, `I'm unable to`, `It would be inappropriate`

**Eval Awareness:**
- `this is a test`, `being evaluated`, `benchmark`
- `being tested`, `being assessed`, `evaluation`
- `appears to be a`, `seems like a test`

**Errors:**
- `Error:`, `Traceback`, `Exception`
- `Permission denied`, `timeout`, `rate limit`
- `connection refused`, `404`, `500`
- `OOM`, `out of memory`, `killed`

**Truncation:**
- Response ends mid-sentence or mid-word
- Response significantly shorter than expected
- `[truncated]`, `...` at end

## 5. Score Distribution Checks

| Pattern | Likely Cause | Severity |
|---------|-------------|----------|
| All scores identical | Scorer broken (constant output) | CRITICAL |
| >90% pass | Too easy / lenient scorer / wrong subset | WARNING |
| >90% fail | Too hard / broken scorer / systematic errors | WARNING |
| Bimodal (0 and 1 only) | May be correct for binary tasks, or scorer lacks granularity | INFO |
| Scores never null | Good — extraction working | OK |
| Some scores null | Extraction failures — check those samples | WARNING |

## 6. Common Scorer Pitfalls

| Scorer Type | Common Failure | Fix |
|-------------|---------------|-----|
| `match` / `exact` | Case, whitespace, punctuation differences | Use `includes()` or normalize |
| `includes` / `contains` | False positives from partial string matches | Add boundary checks |
| `model_graded_qa` | Grader too lenient/strict, vague rubric | Tighten rubric, use different grader model |
| `pattern` / `regex` | Overly strict, doesn't handle model formatting | Test regex on actual model outputs |
| Custom | Off-by-one indexing, type coercion, wrong field | Unit test the scorer separately |

## 7. Ad-Hoc Experiment Patterns

For experiments without formal scorers (safety-tooling, latteries, custom scaffolds):

- Does model behavior match researcher's stated intent?
- Systematic patterns in failures? (same question type, same failure mode)
- Model doing something unexpected but technically valid?
- Results consistent across similar samples?
- Any evidence of gaming or strategic behavior?
- Logs contain enough information to diagnose failures?

## 8. Severity Guide

| Severity | Criteria | Action |
|----------|----------|--------|
| **CRITICAL** | Scorer broken, systematic eval awareness, all samples same error, degenerate scores | Fix before trusting ANY results |
| **WARNING** | Some refusals, format issues, suspicious distribution, possible scorer edge cases | Investigate, may need partial rerun |
| **INFO** | Minor variations, expected refusals, notes for researcher | Note and move on |
