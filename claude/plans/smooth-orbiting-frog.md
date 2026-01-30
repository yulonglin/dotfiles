# Plan: Update USACO/GPQA Plots + White Backgrounds + Adversarial PoC Figure

## Overview

Three changes:
1. **White backgrounds globally** — change Petri style from ivory to white for all figures
2. **Update defense-in-depth figure** — remove adversarial prompts (off-by-one, loop-boundary, sign-flip) from main figure, keeping only 5 non-adversarial prompts for gpt-5-nano
3. **New adversarial PoC figure** — separate figure showing C³ vs TM on adversarial prompts (off-by-one, loop-boundary, sign-flip) + TM results showing these prompts leak intent. Frame as proof-of-concept limitation.
4. **Replace PW-MATH figure with GSM8K** — update password-locked detection figure with new GSM8K data (LD, C³, TM, BP)
5. **Update paper text** — adjust main.tex: new figure references, limitations discussion, appendix separation of adversarial prompts

## Step 1: Switch to anthroplot style + white backgrounds

**File**: `src/scripts/generate_figures.py`

Replace the manual Petri rcParams block (lines 22-62) with:
```python
import matplotlib.pyplot as plt
plt.style.use('anthropic')  # Uses ~/.config/matplotlib/stylelib/anthropic.mplstyle

# Override: white backgrounds (anthroplot defaults to ivory)
plt.rcParams.update({
    'figure.facecolor': 'white',
    'axes.facecolor': 'white',
    'savefig.facecolor': 'white',
    'figure.dpi': 300,
    'savefig.dpi': 300,
})
```

Keep the `METHOD_COLORS` dict but update to use anthroplot color names where they match:
- CORAL → `#D97757` (same as anthroplot DARK_ORANGE/CLAY)
- BLUE → `#6A9BCC` (same as anthroplot SKY)
- Keep MINT, OAT, etc. as-is (they complement the palette)

The anthroplot style already provides:
- Larger font sizes (title=14 bold, label=11, ticks=10, legend=10)
- `spines.top/right: False` (no need to set per-figure)
- Proper color cycle
- `legend.frameon: False`

Also bump any per-figure `fontsize=8` or `fontsize=7` → 10+ for readability.

Remove explicit `facecolor='white'` from individual figures (meinke, cross_model, etc.) — now handled globally.

## Step 2: Update defense-in-depth figure (remove adversarial prompts)

**File**: `src/scripts/generate_figures.py` → `fig_defense_in_depth()`
**Data**: `data/experiments/results/usaco-per-prompt-results.md` (unchanged, authoritative)

In `fig_defense_in_depth()` (line 488), after loading comparison data, filter out adversarial prompts:
```python
ADVERSARIAL_PROMPTS = {'off_by_one', 'loop_boundary', 'sign_flip'}
df = df[~df['Prompt'].isin(ADVERSARIAL_PROMPTS)]
```

This leaves 5 prompts: chaotic_coder, anti_pattern_solver, canonical_reasoning, v_weak_model, generic.

## Step 3: New adversarial PoC figure

**File**: `src/scripts/generate_figures.py` — add `fig_adversarial_poc()`

Create a figure showing:
- **Left panel**: C³ vs TM on off-by-one, loop-boundary, sign-flip (from old data)
- **Right panel or annotation**: TM catches these because models explicitly state "let me subtract 1" etc.

Data (from `usaco-per-prompt-results.md`, gpt-5-nano comparison table):
| Prompt | C³ | TM |
|--------|-----|-----|
| off_by_one | 18.0% | 22.9% |
| loop_boundary | 4.7% | 57.6% |
| sign_flip | 10.8% | 10.8% |

Also show **refusing-to-answer** gets caught by TM (mention in caption/text, data from in-context scheming setup — need to confirm source).

Frame clearly as: "These concrete strategies are designed to defeat C³ and represent unrealistic adversarial conditions."

## Step 4: Replace PW-MATH with GSM8K

**Files**:
- `src/scripts/generate_figures.py` → update `fig_pw_math()` or rename to `fig_pw_gsm8k()`
- `src/scripts/load_results.py` → add `load_pw_gsm8k_results()` or update existing loader

New data (from `pw-gsm8k-results_2.md`):
| Method | Recall@5%FPR | SE |
|--------|-------------|-----|
| LD | **50.4%** | 0.005 |
| C³ | 36.0% | 0.005 |
| TM | 34.7% | 0.005 |
| BP | 3.5% | 0.002 |

Update figure to show 4 methods instead of 2. Update y-axis limit (~60%). Update title to "Password-Locked DeepSeek (GSM8K)".

**Also update**: `main.tex` figure reference/caption if needed.

## Step 5: Update main.tex

### 5a: Defense-in-depth caption
Update caption at line ~333 to note only non-adversarial prompts shown.

### 5b: Add adversarial PoC figure
Add new figure in limitations or results section. Include caption explaining:
- These are highly specific strategies (off-by-one, loop-boundary, sign-flip) designed to leave no doubt how to sandbag
- Proof of concept that concrete strategies can defeat C³
- TM catches some because models leak intent ("let me subtract 1")
- Refusing-to-answer also caught by TM

### 5c: Appendix — separate adversarial prompts
In the sandbagging prompt appendix (line ~1013), separate adversarial prompts from main USACO prompt list.

### 5d: Update PW figure reference
Update caption/text for GSM8K instead of MATH.

## Step 6: Regenerate all figures

```bash
cd /Users/yulong/writing/papers/sandbagging-detection
uv run python src/scripts/generate_figures.py
```

## Step 7: Recompile paper

```bash
bash src/compile.sh
```

## Critical Files

- `src/scripts/generate_figures.py` — main changes (white bg, filter adversarial, new PoC figure, GSM8K)
- `src/scripts/load_results.py` — add GSM8K loader
- `data/experiments/results/usaco-per-prompt-results.md` — authoritative USACO data (read-only)
- `main.tex` — figure references, captions, limitations text, appendix restructure
- `/Users/yulong/Downloads/pw-gsm8k-results_3.md` — GSM8K source data (same content as _2, confirmed identical)

## Verification

1. Run `generate_figures.py` — all figures generate without errors
2. Check `figures/` — all PNGs have white backgrounds (visual inspection)
3. Compile paper — `bash src/compile.sh` succeeds
4. Verify defense_in_depth shows 5 prompts (no adversarial)
5. Verify new adversarial PoC figure exists
6. Verify GSM8K figure replaces MATH figure
