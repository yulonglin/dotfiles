# Plan: Update Paper Figures with New Experimental Results

## Context

The paper's figures use outdated data from "Week 19-20 slides" with hardcoded values in `src/scripts/generate_figures.py`. New experimental results in `data/experiments/` show different findings:

**Old claims:**
- C³ achieves 67% recall on USACO (from 3 prompts)
- Password-locked: 99.6% recall on WMDP

**New data shows:**
- USACO: C³ and TM are mixed (neither dominates consistently)
- Password-locked MATH: ~10-12% recall @ 5% FPR
- Meinke prefill: All tested methods fail (~2% recall)

## Strategic Framing (from current-status.md)

**"Defense in Depth"** - Layer 1 (TM) catches explicit sandbagging; Layer 2 (C³) catches stealthy sandbagging that evades monitoring.

**Key issues**:
1. Current prompted sandbaggers sometimes leak their strategy (e.g., "I will apply systematic bias of -1"), which TM catches. This is a confound, not a fair comparison.
2. TM (Haiku judge) biases toward evaluating correctness rather than suspicion - it tends to solve problems itself and score based on whether the answer is right. This inflated GPQA TM scores specifically.

**Resolution**:
- Show TM wins on prompts with leakage
- Show C³ wins (or matches) on stealthy prompts and password-locked models
- Frame as complementary, not competitive
- Document TM limitations (correctness bias, self-solving)

## Prompt Selection Details

Prompts selected via Vendi diversity after filtering:
- Sandbagging gap ≥10pp (95% CI excludes 0)
- Refusal ≤10%
- Leakage <10%

| Dataset | 4.1-nano prompts | 5-nano prompts |
|---------|------------------|----------------|
| GPQA | 7 | 10 |
| MATH | 10 | 10 |
| USACO | 5 | 8 |

See `specs/icml-baseline-expts/dataset-specific-sandbagging-prompts.md` for full list.

---

## Data Availability Status

| Dataset | C³ | TM | Lie Detector | BP |
|---------|----|----|--------------|-----|
| **GPQA** | ✅ Complete (cat + emb) | ✅ Complete | ✅ 4.1nano, partial 5nano | ✅ Complete |
| **USACO** | ✅ Complete | ✅ Complete | ❌ Running (API timeouts) | Partial |
| **MATH** | ❌ Grouping issue | ❌ Scores empty | ✅ 5nano complete | ❌ Incomplete |
| **PW-MATH** | ✅ Complete | ✅ Complete | - | - |
| **PW-WMDP** | ✅ Complete | - | - | - |
| **Meinke (USACO)** | ❌ Missing | ✅ Complete (fails) | ❌ ~25% complete | ✅ Complete (fails) |

---

## Figures to Update

### Part 1: Main Results (GPQA/USACO)

| Figure | Current File | Status | Action |
|--------|--------------|--------|--------|
| fig:same_model_comparison | `same_model_c3_vs_ld.png` | OUTDATED (claims 67%) | **Recreate** with new USACO data showing C³ vs TM |
| fig:trusted_monitors | `trusted_monitors_comparison.png` | OUTDATED | **Recreate** with GPQA + USACO comparison |
| fig:gpqa_c3_density | `gpqa_c3_density.png` | Possibly OK | **Verify** data matches, may need update |
| fig:combined_methods_k_sweep | `combined_methods_recall_vs_k_comparison.png` | OUTDATED (user confirmed) | **Mark as outdated** or move to appendix |

### Part 2: Password-Locked Models

| Figure | Current File | Status | Action |
|--------|--------------|--------|--------|
| fig:password_locked | `password_locked_results.png` | OUTDATED (claims 99.6% WMDP) | **Recreate** with PW-MATH data (~10-12%) |

### Part 3: Meinke Prefill (if C³ data arrives)

| Figure | Current File | Status | Action |
|--------|--------------|--------|--------|
| (new) | N/A | Waiting on C³ runs | **Create new figure** showing all methods fail |

### Appendix Updates

- Mark Figures 5, 10, 11 (sample efficiency) as outdated
- Add all prompts from system_prompt configs to appendix

---

## Implementation Plan

### Step 1: Create Data Loading Module
**File:** `src/scripts/load_results.py`

Parse markdown tables from `data/experiments/results/*.md` into pandas DataFrames:
- `load_gpqa_results()` → Dict[method, DataFrame]
- `load_usaco_results()` → Dict[method, DataFrame]
- `load_math_results()` → Dict[method, DataFrame]
- `load_pw_results()` → Dict[dataset, DataFrame]
- `load_meinke_results()` → DataFrame

### Step 2: Create Figures (Parallel Agents)

Launch **3 parallel agents** for independent figure groups:

#### Agent 1: Main Results (GPQA + USACO)

**Figure A: GPQA Per-Prompt Results**
- Grouped bar chart: prompts × methods (BP, C³ cat, C³ emb, TM)
- For both 4.1-nano and 5-nano (separate panels or figures)
- Show Recall@5%FPR with SEM error bars
- Highlight: C³(emb) fails on some prompts (60-80% don't give explanations), C³(cat) better
- **Caveat**: TM scores inflated due to correctness bias (Haiku solves problems itself)

**Figure B: USACO Per-Prompt Results**
- Grouped bar chart: prompts × methods (C³, TM)
- Color-code winners (C³ wins / TM wins / Tie)
- Shows complementary strengths clearly

#### Agent 2: Password-Locked + MATH

**Figure C: Password-Locked MATH**
- Simple bar chart: C³ vs TM
- Show low recall (~10-12%) with large CIs
- Caption: "Detection is harder on fine-tuned sandbaggers"

**Figure D: MATH Lie Detector Results**
- Per-prompt breakdown for LD only
- Clear "Other methods incomplete" annotation
- Show variability across prompts (13.7% - 57.6%)

#### Agent 3: Meinke + Behavioral Probes

**Figure E: Meinke Detection Failure**
- Bar chart: TM (~2%), Probes (0%), [C³ pending]
- Strong visual: all methods at/below random
- Caption: "Discovered incentive sandbagging evades detection"

**Figure F: Behavioral Probes Analysis**
- Update existing fig:behavioral_probes if needed
- Show inverted signal issue (sandbaggers deny, benign admit)

### Step 3: Update generate_figures.py

Refactor to:
1. Import `load_results.py` functions
2. Replace hardcoded data with loaded data
3. Add new figure functions
4. Keep Petri/Anthropic styling

### Step 4: Update LaTeX

- Update figure references and captions
- Adjust narrative to "Defense in Depth" framing
- Mark Figures 5, 10, 11 (sample efficiency) as outdated in appendix
- Add prompt list to appendix (from `dataset-specific-sandbagging-prompts.md`)

---

## Plotting Style

Use **Petri style** from `~/.claude/ai_docs/petri-plotting.md`:
- Background: `#FAF9F5` (warm ivory)
- Primary: `#D97757` (coral/clay)
- Blue: `#6A9BCC`
- No gridlines, minimal borders
- 300 DPI, PNG + PDF

---

## Verification

1. Run `python src/scripts/generate_figures.py` to regenerate all figures
2. Compile paper: `bash src/compile.sh`
3. Visual check: figures match data in markdown files
4. Cross-check: values in figure captions match data tables

---

## Decisions (Resolved)

1. **Granularity**: Per-prompt breakdown to show complementary strengths
2. **MATH**: Include Lie Detector only with "incomplete" caveat
3. **Meinke**: Plot TM/Probes failure, note C³ pending
4. **GPQA**: Show both C³(cat) and C³(emb) variants - honest about limitations

---

## Files to Modify

- `src/scripts/generate_figures.py` - Main figure generation (refactor)
- `src/scripts/load_results.py` - NEW: Data loading utilities
- `main.tex` - Update figure references, captions, narrative
- `figures/*.png` - Regenerated figures

## Files to Read (Data Sources)

- `data/experiments/results/gpqa_results.md`
- `data/experiments/results/usaco-per-prompt-results.md`
- `data/experiments/results/MATH_RESULTS_20260128.md`
- `data/experiments/pw-models/pw-math.md`
- `data/experiments/pw-models/pw-wmdp.md`
- `data/prefilled-no-goal-sandbagging/meinke_detection_results.md`
- `specs/icml-baseline-expts/dataset-specific-sandbagging-prompts.md` (for appendix)

## Verification

1. **Data integrity**: Cross-check figure values against markdown tables
2. **Run generation**: `python src/scripts/generate_figures.py`
3. **Compile paper**: `bash src/compile.sh`
4. **Visual review**: Check figures match new narrative
5. **Consistency check**: Ensure captions match data shown

## Estimated Work

| Task | Complexity |
|------|------------|
| Data loading module | Medium (parsing markdown tables) |
| GPQA/USACO figures | Medium (per-prompt grouped bars) |
| PW/MATH figures | Low (simple bars) |
| Meinke figure | Low (3 bars) |
| LaTeX updates | Medium (narrative changes) |
| Appendix prompts | Low (copy from spec) |

**Total**: ~3-4 hours of implementation work, parallelizable across 3 agents
