# Plan: Transcript Review Infrastructure for Experiments

## Context

After running experiments, we currently report aggregate metrics without systematically reading individual transcripts. This misses critical issues: scorer misconfiguration, LLM misunderstanding instructions, eval awareness, refusals, tool errors, and format parsing bugs. We want **automatic transcript review** that samples failures/successes/random, reads full transcripts, and flags suspicious patterns.

This must work across experiment types:
- **Inspect AI evals** (`.eval` gzipped JSON logs)
- **Custom scaffolds/tooling** (JSONL output, raw logs, custom formats)
- **Safety-tooling** (ad-hoc safety evaluations)
- **Latteries** and other lottery-based evaluation frameworks
- **Any experiment** that produces per-sample transcripts or logs

**Key constraint**: Must not cause recursive agent spawning.

## Design (Revised After Critique)

### Two-Tier Architecture

The plan-critic identified that a Read+Grep-only agent **cannot parse `.eval` files** (gzipped JSON). Instead of giving the reviewer Bash (recursion risk) or requiring manual extraction, we use two tiers:

**Tier 1: `check_transcripts.py` (deterministic, fast, no LLM)**
- Python script that handles **multiple input formats**:
  - Inspect AI `.eval` files (via `inspect_ai.log.read_eval_log()`)
  - JSONL files (common output from custom scaffolds — one JSON object per sample)
  - Directories of log files (one file per sample, e.g., `logs/sample_001.json`)
  - Raw text logs with delimiter-separated samples
- Samples transcripts by outcome (failures prioritized)
- Runs deterministic checks (degenerate scores, empty responses, error patterns, refusal markers)
- Extracts sampled transcripts to readable JSON/text files in a standard format
- Outputs structured report + extracted files for Tier 2
- Runs in seconds, zero LLM cost

**Tier 2: `transcript-reviewer` agent (LLM judgment, Read+Grep only)**
- Reads the **extracted** transcript files from Tier 1 (plain JSON/text, normalized format)
- Works on **any** experiment output — the normalization happens in Tier 1
- Applies nuanced analysis: eval awareness detection, subtle scorer issues, instruction misunderstanding
- For custom scaffolds without formal scorers: focuses on whether the model's behavior matches researcher intent
- Returns structured severity report (CRITICAL/WARNING/INFO)
- Read+Grep only → zero recursion risk (extraction already done by Tier 1)

**Optional Tier 3: `inspect scout` (deep LLM-powered scanning)**
- For Inspect AI evals specifically — large-scale LLM-powered transcript scanning
- Recommended but not required; uses OpenRouter credits
- Agent suggests running scout when appropriate

### Where Enforcement Lives

| Context | Enforcement | How |
|---------|-------------|-----|
| **Any Bash experiment command** | **PostToolUse hook** (most reliable) | Detects `run_*.sh`, `run_*.py`, `inspect eval`, etc. and injects reminder |
| Interactive sessions | Rule in agent description (`MUST BE USED`) | Claude follows rule, spawns reviewer after evals |
| `autonomous-researcher` overnight | Inline Bash (Tier 1 only) | Agent runs `check_transcripts.py` directly, logs findings |
| `research-loop` morning review | Skill step | Explicit instruction to spawn full Tier 1+2 review |
| Ad-hoc | `/review-transcripts` skill | User invokes manually |

The **PostToolUse hook** is the primary enforcement — it catches direct Bash execution of experiment scripts that bypass the skills. The rule and skill modifications are secondary reinforcement.

This addresses the critique that autonomous-researcher has no Agent tool — it just runs the Python script inline.

## Files to Create

### 1. `plugins/research/hooks/nudge_transcript_review.sh`
**Path**: `~/code/marketplaces/ai-safety-plugins/plugins/research/hooks/nudge_transcript_review.sh`

**Type**: PostToolUse hook on Bash (nudge, not block — exit 0 with systemMessage)

**Pattern matching** — triggers when command matches any of:
- `run_*.sh` or `run_*.py` (experiment runner scripts)
- `inspect eval` (Inspect AI CLI)
- `python run_` or `uv run python run_` or `python -m` with eval-related args
- `pytest` with eval/benchmark paths (some evals use pytest)
- Script names containing `eval`, `experiment`, `benchmark`, `scaffold`
- `latteries` commands or scripts
- `safety-tooling` / `safety_tooling` related scripts
- Any command whose output dir matches `out/`, `logs/`, `results/` patterns

**What it does**:
- Only fires on PostToolUse (command already ran successfully, exit_code=0)
- Checks if command matches experiment patterns
- If match: injects systemMessage reminding to review transcripts:
  ```
  ⚠️ Experiment command detected. Before reporting results, review transcripts:
  1. Run: python check_transcripts.py <output_path>  (Tier 1: deterministic checks)
     Supports: .eval files, JSONL, log directories, raw text logs
  2. Spawn research:transcript-reviewer on extracted samples  (Tier 2: LLM review)
  3. For Inspect AI evals: scout scan <eval_log> (if installed, Tier 3)
  Focus on failures — sample a few to understand WHY they failed.
  For custom scaffolds: check if model behavior matches researcher intent.
  ```
- Does NOT block (exit 0, not exit 2) — it's a nudge, not a gate
- **Recursion prevention**: Does NOT trigger on `check_transcripts.py` itself or `scout scan`
  (explicit exclusion in pattern matching to avoid the hook nudging about its own review tools)

**Following existing patterns**: Similar to `nudge_modern_tools.sh` (PreToolUse nudge) and
`auto_log.sh` (PostToolUse logging). Uses jq to parse tool_input.command.

### 2. `plugins/research/agents/transcript-reviewer.md`
**Path**: `~/code/marketplaces/ai-safety-plugins/plugins/research/agents/transcript-reviewer.md`

New agent with:
- **Tools**: `Read,Grep` (reads pre-extracted transcripts, not raw .eval files)
- **Description**: `MUST BE USED after experiments complete to review sampled transcripts...` (follows research-skeptic/data-analyst pattern, not Inspect AI-specific)
- **Capabilities**: 6 detection categories (scorer bugs, instruction misunderstanding, eval awareness, refusals, tool errors, format issues)
- **Sampling strategy**: Adaptive — `min(max(3, N*0.05), 15)` total, ~40% failures, ~30% successes, ~30% random. Review all failures if <20 total samples
- **Output format**: Structured report with CRITICAL/WARNING/INFO severity ratings
- **Input**: Expects pre-extracted transcript files (from `check_transcripts.py`) in normalized JSON format, or raw readable files (JSONL, JSON, text logs). Does NOT handle `.eval` (gzipped) directly
- **Escalation**: scorer bugs → research-engineer, eval awareness → research-skeptic, design issues → experiment-designer

### 3. `plugins/research/agents/references/transcript-review-checklist.md`
**Path**: `~/code/marketplaces/ai-safety-plugins/plugins/research/agents/references/transcript-review-checklist.md`

Reference doc (follows `ci-standards.md` pattern) containing:
- **Normalized transcript format** (what `check_transcripts.py` outputs)
- **Inspect AI** `.eval` log JSON structure (top-level, sample structure, message structure, scores)
- **Custom scaffold patterns** — common JSONL structures, how to identify input/output/score fields
- Per-transcript checklist items (format-agnostic)
- Red-flag patterns (grep-able strings for refusals, awareness, errors)
- Score distribution checks (degenerate detection, expected entropy)
- Common scorer pitfalls by scorer type (`match`, `includes`, `model_graded_qa`, `exact`)
- **Ad-hoc experiment patterns** — what to look for when there's no formal scorer (behavioral alignment with researcher intent)

### 4. `plugins/research/skills/review-transcripts/SKILL.md`
**Path**: `~/code/marketplaces/ai-safety-plugins/plugins/research/skills/review-transcripts/SKILL.md`

Standalone skill for ad-hoc transcript review:
1. Takes eval log path as argument (or finds most recent `.eval` file)
2. Runs `check_transcripts.py` to extract + do deterministic checks
3. Spawns `transcript-reviewer` agent on extracted files
4. Optionally recommends `scout scan` for deeper analysis
5. Presents combined Tier 1 + Tier 2 report

### 5. `plugins/research/scripts/check_transcripts.py`
**Path**: `~/code/marketplaces/ai-safety-plugins/plugins/research/scripts/check_transcripts.py`

Python script (Tier 1 deterministic checks):

**Input format auto-detection**:
- `.eval` files → `inspect_ai.log.read_eval_log()` (gzipped JSON)
- `.jsonl` files → line-by-line JSON (expects `score`/`status`/`result` field for outcome)
- Directories → scan for `.json`/`.jsonl`/`.log` files (one per sample)
- `.json` files → single JSON with `samples` array or similar structure
- Falls back to treating as raw text log if no structured format detected

**Sampling**: failures prioritized, adaptive count based on total N

**Deterministic checks** (format-agnostic where possible):
- Degenerate scores (all 0, all 1, uniform) — if scores available
- Empty/truncated responses
- Refusal markers ("I cannot", "I'm sorry", "as an AI", "I apologize")
- Tool call errors in messages (timeout, permission denied, API error patterns)
- Score distribution anomalies
- For custom scaffolds: at minimum checks for empty responses and error patterns

**Outputs**:
- `transcript_review/summary.json` — structured findings (format, sample count, issues found)
- `transcript_review/samples/*.json` — extracted transcript files in **normalized format**:
  ```json
  { "id": "sample_001", "input": "...", "output": "...", "score": 0.0,
    "messages": [...], "metadata": { "source_format": "inspect_eval" } }
  ```
- Prints human-readable report to stdout

**CLI**: `python check_transcripts.py <path> [--format auto|eval|jsonl|dir|text] [--output-dir transcript_review] [--max-samples 15] [--score-field score]`
- `--score-field` lets custom scaffolds specify which JSON field holds the outcome
- `--format auto` is default (auto-detect)
- No LLM calls, runs in <5 seconds

## Files to Modify

### 6. `plugins/research/agents/autonomous-researcher.md`
**Path**: `~/code/marketplaces/ai-safety-plugins/plugins/research/agents/autonomous-researcher.md`

Minimal changes (addresses critique about not adding Agent tool):

**In EXECUTION PROTOCOL** (after "Extract metrics from output", before "Compare against threshold/baseline"):
```
   - **Transcript spot-check (if Inspect AI eval):** Run `python check_transcripts.py <eval_log>`
     to sample and check transcripts. If CRITICAL issues found (degenerate scorer, systematic
     errors), treat experiment as INVALID regardless of metric. Log findings to research-log.md.
```

**In ERROR HANDLING table**, add:
```
| Transcript review: CRITICAL issue | Log issue, attempt fix (1 try), rerun. If still CRITICAL, skip to next |
```

**In OUTPUT template**, add after "Result":
```
   - **Transcript check:** [clean / N issues — summary]
```

### 7. `plugins/research/skills/research-loop/skill.md`
**Path**: `~/code/marketplaces/ai-safety-plugins/plugins/research/skills/research-loop/skill.md`

**In Step 4 (Morning Review)**, expand the existing review steps:
```
## Step 4: Morning Review

When the user returns, help them review:
1. Read `research-log.md` for the narrative
2. Read `results.tsv` for structured data
3. **Review transcripts**: Spawn `research:transcript-reviewer` on the latest eval logs
   to verify scorer correctness and catch issues the autonomous agent's spot-checks may have missed.
   Focus especially on:
   - Experiments marked INVALID by the agent (what went wrong?)
   - The best-performing experiment (is the improvement real or a scorer artifact?)
   - Any experiments with suspiciously perfect or zero scores
4. Identify the best strategy and its evidence
5. Decide next steps: refine the winner, try new directions, or ship
```

### 8. `plugins/research/skills/run-experiment/SKILL.md`
**Path**: `~/code/marketplaces/ai-safety-plugins/plugins/research/skills/run-experiment/SKILL.md`

**Add new section after "Status Check"**:
```
6. **Transcript Review (after experiment completes)**:
   - Run: `python check_transcripts.py <output_path>` (Tier 1: deterministic checks)
     Works with .eval, JSONL, log directories, or raw text — auto-detects format
   - If issues found OR experiment is important: spawn `research:transcript-reviewer` (Tier 2: LLM review)
   - For Inspect AI evals: recommend `scout scan <eval_log>` if inspect_scout is installed
   - Report findings to user before declaring experiment complete
```

## Verification Plan

1. **nudge_transcript_review.sh**: Run a Bash command matching `run_*.py` pattern, verify hook fires systemMessage nudge. Run `check_transcripts.py`, verify hook does NOT fire (exclusion works)
2. **check_transcripts.py**: Run against a real `.eval` file, verify it produces `summary.json` and extracted sample files
3. **transcript-reviewer agent**: Feed it pre-extracted sample files from a known-bad eval (scorer bug), verify it catches the issue
4. **Integration**: Run `/review-transcripts <eval_path>` end-to-end, verify both tiers execute and produce combined report
5. **Recursion safety**: Verify transcript-reviewer agent definition has only `Read,Grep` tools. Verify hook excludes its own review commands
6. **autonomous-researcher**: Verify the Bash command `python check_transcripts.py` works inline (no agent spawning needed)

## What This Plan Does NOT Do

- Does NOT block experiments (hook is a nudge, not a gate — exit 0, not exit 2)
- Does NOT hard-depend on inspect scout (recommended, not required)
- Does NOT give transcript-reviewer Bash access (extraction happens upstream)
- Does NOT modify autonomous-researcher's tool list (inline Bash is sufficient)
