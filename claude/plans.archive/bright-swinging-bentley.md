# Specification: Research Tooling Enhancements

## Overview
**Created**: 25-01-2026
**Status**: Draft

Add four improvements to research workflow: (1) standardized UTC date/timestamp helpers, (2) research-focused spec interview skill, (3) Petri-inspired plotting style system, and (4) pre-run validation gates to prevent experimental errors.

## Context & Motivation

Current pain points in research workflow:
- **Date formats inconsistent**: Mix of YYMMDD_HHmmss (hard to read), ISO-8601, and ad-hoc formats across skills and CLAUDE.md
- **Spec interview is product-focused**: Missing research-critical elements (variables, hypotheses, baselines, resources)
- **No unified plotting aesthetic**: Existing anthropic.mplstyle works but want Petri's warm, editorial look for research papers
- **Accidental reruns from config errors**: Forgot to change defaults, missing seeds, undocumented hyperparameters waste time and money

User research workflow:
1. Brainstorm research question with AI
2. Collaborate on hypotheses and experimental design
3. **Critical gate**: Validate all configs before running (prevent reruns)
4. Execute experiments with proper tracking
5. Generate publication-quality Petri-style plots

## Requirements

### Functional Requirements

#### 1. Date/Timestamp Helpers
- **[REQ-001]** The system MUST provide `utc_date` command outputting `DD-MM-YYYY` format (e.g., `25-01-2026`)
- **[REQ-002]** The system MUST provide `utc_timestamp` command outputting `DD-MM-YYYY_HH-MM-SS` format (e.g., `25-01-2026_14-30-22`)
- **[REQ-003]** Both commands MUST use UTC timezone exclusively
- **[REQ-004]** Commands MUST be executable scripts in `custom_bins/` (added to PATH)
- **[REQ-005]** CLAUDE.md MUST document these commands for AI reference
- **[REQ-006]** Existing YYMMDD_HHmmss references in CLAUDE.md SHOULD be updated to new format

#### 2. Research Spec Interview Skill
- **[REQ-007]** The system MUST provide `/spec-interview-research` skill (separate from product spec interview)
- **[REQ-008]** Interview MUST cover research-specific categories:
  - Research question & motivation
  - Hypotheses & falsification criteria
  - Independent, dependent, control variables (high-level → drill down on critical ones)
  - Confounding variables & controls
  - Models, hyperparameters, baselines
  - Datasets being used
  - Metrics to measure
  - Graphs to plot
  - Resources (CPU, memory, budget) with inline validation
  - Sample size & statistical power
  - Reproducibility (seeds, versions, logging)
- **[REQ-009]** Resource validation MUST run inline during interview (soft validation: check and warn, don't block)
- **[REQ-010]** Output MUST be lightweight spec (~100 lines) to `specs/research-interview-DD-MM-YYYY.md`
- **[REQ-011]** Interview MUST use 2-4 non-obvious questions per round, challenge assumptions

#### 3. Petri Plotting Style System
- **[REQ-012]** The system MUST provide `petri.mplstyle` file for matplotlib
- **[REQ-013]** The system MUST provide `petriplot.py` helper module (like `anthroplot.py`)
- **[REQ-014]** Style MUST include:
  - Warm beige background (#FAF9F5 from Petri figures)
  - Pastel accent colors (coral/orange #D97757, blue #6A9BCC, green/mint #B8D4C8, tan/oat #E3DACC)
  - Clean sans-serif fonts (system fallbacks since Petri likely uses custom Anthropic fonts)
  - Minimal borders, no gridlines
  - Rounded corners on boxes/rectangles
- **[REQ-015]** `petriplot.py` MUST provide helper functions for:
  - Flowchart boxes with rounded corners
  - Flow arrows
  - Color palette constants (with hex codes)
  - Annotation helpers
- **[REQ-016]** Color palette reference MUST be documented for use in TikZ/Excalidraw
- **[REQ-017]** Style MUST coexist with existing `anthropic.mplstyle` (not replace)
- **[REQ-018]** Petri aesthetic note: Inspired by Anthropic's Petri paper (https://alignment.anthropic.com/2025/petri/)

#### 4. Pre-Run Validation Gate
- **[REQ-019]** Research-engineer or experiment-setup agents MUST validate specs before execution
- **[REQ-020]** Validation MUST BLOCK execution if missing:
  - Hyperparameters documented
  - Output path specified
  - Hypothesis specified with falsification criteria
  - Metrics to measure defined
  - Datasets specified
  - Graphs/plots planned for metrics
- **[REQ-021]** Validation SHOULD warn (but not block) if:
  - Resources exceed system available (user might use remote)
  - No baseline comparison
  - Random seeds not set (warn strongly)
- **[REQ-022]** Validation output MUST be clear checklist showing pass/fail/warn for each item

#### 5. Non-Destructive Outputs
- **[REQ-023]** Plot filenames MUST use timestamp format: `{name}_{DD-MM-YYYY_HH-MM-SS}.png`
- **[REQ-024]** NEVER overwrite existing plot files
- **[REQ-025]** Hydra experiment outputs continue using timestamped directories

### Non-Functional Requirements
- **Maintainability**: Separate concerns (dates, interview, plotting, validation) into distinct files
- **Consistency**: All dates/timestamps use UTC and DD-MM-YYYY format across system
- **Usability**: Helpers discoverable in PATH, documented in CLAUDE.md for AI agents
- **Extensibility**: Petri style system can expand to TikZ/Excalidraw in future

## Design

### High-Level Architecture

```
custom_bins/
├── utc_date          # Outputs DD-MM-YYYY
└── utc_timestamp     # Outputs DD-MM-YYYY_HH-MM-SS

~/.claude/skills/
└── spec-interview-research/
    ├── SKILL.md                           # Main skill definition
    └── references/
        ├── research-interview-guide.md    # 13 question categories
        └── research-spec-template.md      # Lightweight output template

~/.claude/ai_docs/
└── petri-plotting.md                      # Color palette reference for all tools

config/matplotlib/
├── petri.mplstyle                         # Matplotlib style file
└── petriplot.py                           # Helper module with flowchart functions

~/.claude/agents/
└── research-engineer.md                   # Updated with validation gate logic
```

### Component Details

#### 1. Date Helpers Implementation

**utc_date**:
```bash
#!/bin/bash
# Output: DD-MM-YYYY in UTC
date -u +%d-%m-%Y
```

**utc_timestamp**:
```bash
#!/bin/bash
# Output: DD-MM-YYYY_HH-MM-SS in UTC
date -u +%d-%m-%Y_%H-%M-%S
```

**CLAUDE.md updates**:
- Section on date formatting (replace YYMMDD_HHmmss references)
- Document commands: `$(utc_date)` and `$(utc_timestamp)`
- Update examples in Output Strategy, File Organization sections

**Files affected**:
- `/Users/yulong/code/dotfiles/scripts/shared/helpers.sh` (backup_file function)
- `/Users/yulong/code/dotfiles/deploy.sh` (backup paths)
- `/Users/yulong/.claude/CLAUDE.md` (lines 79, 164, 391)
- `/Users/yulong/.claude/skills/experiment-setup/templates/hydra_config.yaml`
- `/Users/yulong/.claude/skills/run-experiment/SKILL.md`

#### 2. Research Spec Interview Skill

**Question Categories** (15 total):

1. **Research Question & Motivation**: What exactly are you investigating? Why does this matter?
2. **Hypotheses & Falsification**: What are your explicit hypotheses? What results would falsify them?
3. **Independent Variables**: What are you manipulating? (Start high-level, drill down on critical ones)
4. **Dependent Variables & Metrics**: What are you measuring? Exact metrics (e.g., "exact_match on MMLU")?
5. **Control Variables**: What must stay constant across conditions?
6. **Confounding Variables**: What alternative explanations exist? How will you rule them out?
7. **Models & Hyperparameters**: Which models? Hyperparameters? Justification for choices?
8. **Baselines & Comparisons**: What are you comparing against? Why fair/strong baselines?
9. **Datasets**: Which datasets? Versions? Preprocessing? Train/val/test splits?
10. **Graphs & Visualizations**: What plots will show the key results? Axes, groupings?
11. **Resources & Validation**: CPU/GPU/memory needed? Budget? [Inline check: "System has X, you need Y - proceed?"]
12. **Sample Size & Power**: How many samples? Statistical significance threshold?
13. **Performance & Caching**: What gets cached? Cache keys? What needs to rerun? Concurrency level? Exponential backoff strategy?
14. **Error Handling & Retries**: Which errors are transient vs permanent? Retry logic? Rate limit handling?
15. **Reproducibility**: Random seeds? Code versions? Exact configs? Logging plan?

**Output Template** (lightweight ~100 lines):
```markdown
# Research Interview Spec: [Topic]

## Overview
**Created**: DD-MM-YYYY
**Status**: Draft Interview Spec

[1-2 sentence summary]

## Research Question
[Specific, measurable question]

## Hypotheses
- **H1**: [Hypothesis] → Prediction: [Specific outcome] → Falsification: [What would disprove]
- **H2**: ...

## Variables
### Independent (What We Manipulate)
- [Variable 1]: [Values/levels, e.g., model size: [1B, 7B, 13B]]
- [Variable 2]: ...

### Dependent (What We Measure)
- [Metric 1]: [Exact definition, e.g., "exact_match accuracy on MMLU"]
- [Metric 2]: ...

### Control (Held Constant)
- [Constant 1]: ...

### Confounds & Controls
| Confound | How Controlled |
|----------|----------------|
| [Alternative explanation] | [Method to rule out] |

## Models & Hyperparameters
| Component | Choice | Justification |
|-----------|--------|---------------|
| Model | [e.g., Claude Sonnet 4.5] | [Why this model] |
| Hyperparameter | [e.g., temperature=0.7] | [Why this value] |

## Baselines
- **Baseline 1**: [Description, why fair/strong]
- **Baseline 2**: ...

## Datasets
- **Dataset**: [Name, version, source]
- **Splits**: [Train/val/test sizes and selection]
- **Preprocessing**: [Steps taken]

## Metrics & Visualizations
### Metrics to Track
- [Metric 1, Metric 2, ...]

### Planned Graphs
- **Figure 1**: [X-axis: ..., Y-axis: ..., Grouping: ..., Purpose: ...]
- **Figure 2**: ...

## Resources & Constraints
**Validated Against System**:
- **Compute**: [Needs X cores, system has Y] ✓/⚠
- **Memory**: [Needs X GB, system has Y] ✓/⚠
- **Budget**: [Estimated API cost: $X, available: $Y] ✓/⚠
- **Timeline**: [Estimated duration]

## Sample Size & Statistics
- **N**: [Number of samples, justification]
- **Significance**: [α threshold, e.g., p<0.05]
- **Power**: [If calculated]

## Performance & Caching Strategy
### Caching
- **What Gets Cached**: [e.g., API responses, model outputs, embeddings]
- **Cache Keys**: [How uniqueness determined, e.g., `hash(model_name + prompt + temperature)`]
- **Cache Location**: [e.g., `.cache/api_responses/`, per CLAUDE.md]
- **Cache Invalidation**: [When to clear, e.g., `--clear-cache` flag]
- **What Must Rerun**: [e.g., final aggregation, plotting, statistical tests]

### Concurrency & Rate Limiting
- **Concurrency Level**: [e.g., 100 concurrent API calls via `asyncio.Semaphore(100)`]
- **Rate Limits**: [Known limits, e.g., "Anthropic: 50 req/min"]
- **Backoff Strategy**:
  - **Transient errors** (429, 503): Exponential backoff (1s, 2s, 4s, 8s, 16s max)
  - **Permanent errors** (400, 401, 404): No retry, log and fail
- **Retry Logic**: [e.g., `tenacity` library with max 5 retries]

### Error Handling
| Error Type | Retry? | Strategy |
|------------|--------|----------|
| 429 Rate Limit | Yes | Exponential backoff, respect retry-after header |
| 503 Service Unavailable | Yes | Exponential backoff (max 3 retries) |
| 500 Server Error | Yes | Exponential backoff (max 3 retries) |
| 400 Bad Request | No | Log, skip sample, continue |
| 401 Unauthorized | No | Fail immediately (check API key) |
| Timeout | Yes | Retry with longer timeout (max 3 retries) |

## Reproducibility Plan
- **Random Seeds**: [Strategy, e.g., seeds=[42, 43, 44, 45, 46] for 5 runs]
- **Code Version**: [Git commit or tag]
- **Data Version**: [Hash or version number]
- **Logging**: [What gets logged, where]
- **Output Path**: [Exact directory, e.g., out/DD-MM-YYYY_HH-MM-SS_experiment_name/]

## Validation Checklist (Pre-Run Gate)
### BLOCKING (Must Pass)
- [ ] Hyperparameters documented
- [ ] Output path specified
- [ ] Hypothesis with falsification criteria
- [ ] Metrics defined
- [ ] Datasets specified
- [ ] Graphs planned
- [ ] Caching strategy defined (what cached, what rerun)
- [ ] Concurrency level specified
- [ ] Error handling & retry logic documented

### WARNING (Should Pass)
- [ ] Random seeds set
- [ ] Resources available
- [ ] Baseline comparison defined

## Open Questions
- [ ] [Unresolved question 1]
- [ ] [Unresolved question 2]
```

**Interview Flow**:
1. Ask 2-4 questions per category
2. For variables: Start high-level → drill down on critical ones
3. For resources: Inline validation (check system, show available vs needed, warn if mismatch)
4. Challenge assumptions: "Why baseline X instead of Y?" "What if Z confound explains results?"
5. Continue until checklist complete

#### 3. Petri Plotting Style

**Color Palette** (extracted from Petri figures):
- Background: `#FAF9F5` (warm ivory)
- Primary accent: `#D97757` (coral/clay)
- Blue accent: `#6A9BCC` (soft blue)
- Green/mint: `#B8D4C8` (muted green)
- Tan/oat: `#E3DACC` (warm neutral)
- Orange accent: `#E6A860` (soft orange)
- Text: `#141413` (near-black slate)

**petri.mplstyle**:
```python
# Figure
figure.facecolor: FAF9F5
figure.edgecolor: FAF9F5
figure.figsize: 8, 6
figure.dpi: 150

# Axes
axes.facecolor: FAF9F5
axes.edgecolor: 141413
axes.linewidth: 0.8
axes.spines.top: False
axes.spines.right: False
axes.grid: False
axes.prop_cycle: cycler('color', ['D97757', '6A9BCC', 'B8D4C8', 'E6A860', 'E3DACC'])

# Ticks
xtick.color: 141413
ytick.color: 141413
xtick.major.width: 0.8
ytick.major.width: 0.8

# Grid (disabled but available if re-enabled)
grid.color: E3DACC
grid.linestyle: -
grid.linewidth: 0.5
grid.alpha: 0.3

# Legend
legend.frameon: False
legend.fancybox: False

# Font
font.family: sans-serif
font.sans-serif: Inter, -apple-system, SF Pro Text, Helvetica Neue, Arial, sans-serif
font.size: 11

# Saving
savefig.dpi: 300
savefig.bbox: tight
savefig.facecolor: FAF9F5
savefig.edgecolor: FAF9F5
```

**petriplot.py** (helper module):
```python
"""
Petri plotting style helpers
Inspired by Anthropic's Petri paper: https://alignment.anthropic.com/2025/petri/

Color palette extracted from published figures.
"""

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch
import numpy as np

# Color Palette (Hex codes)
IVORY = '#FAF9F5'        # Background
SLATE = '#141413'        # Text
CORAL = '#D97757'        # Primary accent
BLUE = '#6A9BCC'         # Blue accent
MINT = '#B8D4C8'         # Green/mint
OAT = '#E3DACC'          # Tan/neutral
ORANGE = '#E6A860'       # Orange accent

# Semantic color mapping
COLORS = {
    'background': IVORY,
    'text': SLATE,
    'accent_primary': CORAL,
    'accent_blue': BLUE,
    'accent_green': MINT,
    'accent_neutral': OAT,
    'accent_orange': ORANGE,
}

# Color cycle for plots
COLOR_CYCLE = [CORAL, BLUE, MINT, ORANGE, OAT]

def flow_box(ax, text, xy, width=2, height=0.8, color=BLUE,
             text_color=SLATE, fontsize=10, alpha=0.3):
    """
    Add a rounded rectangle box for flowcharts

    Args:
        ax: matplotlib axes
        text: Label text
        xy: (x, y) bottom-left corner
        width, height: Box dimensions
        color: Fill color (hex or named)
        text_color: Text color
        fontsize: Font size for label
        alpha: Fill transparency (0-1)

    Returns:
        FancyBboxPatch object
    """
    box = FancyBboxPatch(
        xy, width, height,
        boxstyle="round,pad=0.1",
        facecolor=color,
        edgecolor=SLATE,
        linewidth=0.8,
        alpha=alpha
    )
    ax.add_patch(box)

    # Add centered text
    ax.text(
        xy[0] + width/2, xy[1] + height/2,
        text,
        ha='center', va='center',
        color=text_color,
        fontsize=fontsize,
        weight='normal'
    )

    return box

def flow_arrow(ax, start, end, color=SLATE, width=1.5):
    """
    Add arrow for flowcharts

    Args:
        ax: matplotlib axes
        start: (x, y) start point
        end: (x, y) end point
        color: Arrow color
        width: Line width
    """
    ax.annotate(
        '',
        xy=end,
        xytext=start,
        arrowprops=dict(
            arrowstyle='->',
            color=color,
            lw=width,
            shrinkA=0,
            shrinkB=0
        )
    )

def set_petri_style():
    """Apply Petri plotting style globally"""
    plt.style.use('petri')  # Assumes petri.mplstyle is installed

# Example usage
if __name__ == "__main__":
    fig, ax = plt.subplots(figsize=(8, 6))

    # Sample flowchart
    flow_box(ax, "Formulate\nhypothesis", (0.5, 3), color=OAT)
    flow_box(ax, "Design\nscenarios", (0.5, 2), color=ORANGE, alpha=0.3)
    flow_box(ax, "Run\nexperiments", (0.5, 1), color=BLUE, alpha=0.3)
    flow_box(ax, "Iterate", (0.5, 0), color=MINT, alpha=0.3)

    flow_arrow(ax, (1.5, 3), (1.5, 2.8))
    flow_arrow(ax, (1.5, 2), (1.5, 1.8))
    flow_arrow(ax, (1.5, 1), (1.5, 0.8))

    ax.set_xlim(0, 4)
    ax.set_ylim(-0.5, 4)
    ax.axis('off')

    plt.tight_layout()
    plt.savefig(f'petri_example_{utc_timestamp()}.png', dpi=300)
    plt.show()
```

**Color Reference Document** (`~/.claude/ai_docs/petri-plotting.md`):
```markdown
# Petri Plotting Style Guide

Inspired by Anthropic's Petri paper: https://alignment.anthropic.com/2025/petri/

## Color Palette

Use these colors for consistency across matplotlib, TikZ, Excalidraw, and other tools.

### Primary Colors
- **Background**: `#FAF9F5` (warm ivory)
- **Text**: `#141413` (slate, near-black)

### Accent Colors
- **Coral/Clay** (primary): `#D97757`
- **Blue**: `#6A9BCC`
- **Mint/Green**: `#B8D4C8`
- **Orange**: `#E6A860`
- **Tan/Oat** (neutral): `#E3DACC`

### Usage Guidelines
- **Backgrounds**: Always `#FAF9F5`, never pure white
- **Box fills**: Use accent colors with 30% opacity (alpha=0.3)
- **Text**: `#141413` for all labels and annotations
- **Borders**: Thin (0.8pt), `#141413`
- **No gridlines**: Clean, minimal aesthetic

## Matplotlib
```python
import matplotlib.pyplot as plt
plt.style.use('petri')
```

## TikZ
```latex
\definecolor{ivory}{HTML}{FAF9F5}
\definecolor{slate}{HTML}{141413}
\definecolor{coral}{HTML}{D97757}
\definecolor{blue}{HTML}{6A9BCC}
\definecolor{mint}{HTML}{B8D4C8}
\definecolor{orange}{HTML}{E6A860}
\definecolor{oat}{HTML}{E3DACC}
```

## Excalidraw
Import color palette:
- Background: `#FAF9F5`
- Stroke: `#141413`
- Fill options: `#D97757`, `#6A9BCC`, `#B8D4C8`, `#E6A860`, `#E3DACC`
- Opacity: 30% for fills

## Fonts
- **Sans-serif**: Inter, SF Pro Text, Helvetica Neue, Arial
- **Fallback**: System default sans-serif
- **Size**: 10-11pt for labels, 12-14pt for titles

## Design Principles
1. **Warm editorial feel**: Beige background vs stark white
2. **Pastel accents**: Soft, muted colors (avoid saturated primaries)
3. **Rounded corners**: Use rounded rectangles for boxes
4. **Minimal borders**: Thin lines, remove unnecessary spines
5. **Clean layout**: Generous whitespace, no clutter
```

#### 4. Pre-Run Validation Gate

**Integration Point**: `research-engineer` agent (already handles experiment implementation)

**Validation Logic** (add to research-engineer.md):
```markdown
## Pre-Run Validation Checklist

Before executing any experiment, validate the research spec:

### BLOCKING (Must Pass)
- [ ] **Hyperparameters documented**: All model/training hyperparameters explicitly listed
- [ ] **Output path specified**: Exact directory for results (e.g., `out/DD-MM-YYYY_HH-MM-SS_exp_name/`)
- [ ] **Hypothesis with falsification**: Clear hypothesis + what results would disprove it
- [ ] **Metrics defined**: Exact metrics to measure (not just "accuracy" but "exact_match on MMLU")
- [ ] **Datasets specified**: Which datasets, versions, splits
- [ ] **Graphs planned**: What plots will be generated (axes, groupings)

### WARNING (Should Pass, Can Override)
- [ ] **Random seeds**: Set for reproducibility (warn strongly if missing)
- [ ] **Resources available**: System has enough CPU/memory/budget
- [ ] **Baseline comparison**: At least one strong baseline defined

### Validation Output Format
```
🔍 Pre-Run Validation Report
============================

✅ PASS: Hyperparameters documented (12 params in spec)
✅ PASS: Output path: out/25-01-2026_14-30-22_alignment_eval/
✅ PASS: Hypothesis: "Model X will outperform baseline Y on metric Z" | Falsification: "If accuracy < baseline"
✅ PASS: Metrics: exact_match (MMLU), rouge-L (summarization)
✅ PASS: Datasets: MMLU v1.0, train=1000, val=200, test=500
✅ PASS: Graphs: accuracy vs model size (x=params, y=score, group=dataset)
✅ PASS: Caching: API responses cached by hash(model+prompt+temp), stored in .cache/api_responses/
✅ PASS: Concurrency: 100 concurrent calls via asyncio.Semaphore(100)
✅ PASS: Error handling: 429/503 → exp backoff, 400/401 → fail, documented in spec
⚠️  WARN: Random seeds not specified (set seeds=[42,43,44,45,46] for 5 runs)
⚠️  WARN: System has 64GB RAM, spec requires 128GB (if running remotely, ignore)

RESULT: 9/9 blocking checks passed, 2 warnings
```

If any BLOCKING check fails → Print report → **STOP EXECUTION** → Ask user to update spec.
```

### Technical Decisions

| Decision | Options Considered | Choice | Rationale |
|----------|-------------------|--------|-----------|
| Date format | YYYYMMDD, DDMMYYYY, DD-MM-YYYY | DD-MM-YYYY with hyphens | User preference, readable from front, matches Singapore/UK conventions |
| Date helpers location | CLAUDE.md only, custom_bins only, both | Both (bins + CLAUDE.md docs) | Humans use bins, AI references CLAUDE.md |
| Research interview | Extend existing, separate skill, auto-detect | Separate `/spec-interview-research` | Different question categories and output template |
| Interview depth (variables) | High-level only, full detail, adaptive | Start high-level, drill down critical | Fast iteration but thorough on key decisions |
| Resource validation timing | Before, during, after interview | During interview (inline) | Contextual feedback without interrupting flow |
| Validation strictness | Block all, warn all, mixed | Block critical (hyperparams, hypothesis, metrics), warn nice-to-have (seeds, resources) | Safety net without being restrictive |
| Plotting system | .mplstyle only, Python module only, both | Both (style file + petriplot.py) | Style for basic plots, module for flowcharts |
| Plotting scope | Matplotlib only, include TikZ/Excalidraw, future extension | Include color palette docs for all tools | Consistent aesthetic, document now even if implementation comes later |
| Plot versioning | Timestamp in filename, Hydra dirs, counter + metadata | Timestamp in filename | Never overwrites, simple, matches user preference |
| Spec output | Full research-spec.md, lightweight only, two-phase | Two-phase: light interview spec → (validation gate) → full spec | Fast brainstorming + safety validation + detailed tracking |

## Edge Cases & Error Handling

| Scenario | Handling |
|----------|----------|
| `utc_date` called on system without `date -u` | Use fallback: `date +%d-%m-%Y` (local time, warn user) |
| Research interview on non-research project | Still works, just asks research questions (user can skip irrelevant ones) |
| Validation gate finds missing hyperparameter | Block execution, show checklist, ask user to update spec |
| Plot filename collision (unlikely with timestamp) | Append counter: `fig_25-01-2026_14-30-22_v2.png` |
| Petri style used without fonts | Fallback to system sans-serif (already in .mplstyle) |
| User wants to skip validation gate | Add `--skip-validation` flag (warn strongly, log decision) |
| Resources exceed system but user knows it's OK (remote exec) | Validation warns but doesn't block, user proceeds |

## Implementation Plan

### Phase 1: Date Helpers
1. Create `custom_bins/utc_date` and `custom_bins/utc_timestamp` scripts
2. Make executable (`chmod +x`)
3. Test output format
4. Update CLAUDE.md:
   - Add "Date Formatting" section documenting commands
   - Replace YYMMDD_HHmmss references with DD-MM-YYYY format
   - Update examples in Output Strategy, File Organization sections
5. Update affected files:
   - `scripts/shared/helpers.sh` (backup_file function)
   - `deploy.sh` (backup paths)
   - `skills/experiment-setup/templates/hydra_config.yaml`
   - `skills/run-experiment/SKILL.md`
6. Deploy with `./deploy.sh` (symlinks bins)

### Phase 2: Research Spec Interview Skill
1. Create skill directory structure:
   ```
   ~/.claude/skills/spec-interview-research/
   ├── SKILL.md
   └── references/
       ├── research-interview-guide.md (13 categories)
       └── research-spec-template.md (lightweight output)
   ```
2. Write research-interview-guide.md with 13 question categories
3. Write research-spec-template.md (~100 lines, focused)
4. Write SKILL.md with:
   - Interview flow (2-4 questions/round, drill down on critical variables)
   - Resource validation (inline during interview)
   - Reference to guide and template
5. Test with dummy research project

### Phase 3: Petri Plotting Style
1. Create `config/matplotlib/petri.mplstyle` with colors/fonts/styling
2. Create `config/matplotlib/petriplot.py` with:
   - Color constants (IVORY, CORAL, BLUE, MINT, OAT, ORANGE, SLATE)
   - `flow_box()` function (rounded rectangles)
   - `flow_arrow()` function
   - `set_petri_style()` helper
   - Example usage in `__main__`
3. Create `~/.claude/ai_docs/petri-plotting.md` with:
   - Color palette (hex codes)
   - Usage for matplotlib, TikZ, Excalidraw
   - Design principles
4. Update `deploy.sh`:
   - Symlink `petri.mplstyle` to `~/.config/matplotlib/stylelib/`
   - Copy `petriplot.py` to `~/.config/matplotlib/` (or add to PYTHONPATH)
5. Test: Run example flowchart generation
6. Update matplotlib deployment section in dotfiles CLAUDE.md

### Phase 4: Pre-Run Validation Gate
1. Update `~/.claude/agents/research-engineer.md`:
   - Add "Pre-Run Validation Checklist" section
   - Define blocking vs warning checks
   - Add validation output format template
   - Add logic: if validation fails → stop execution → ask user to fix spec
2. Update `~/.claude/skills/experiment-setup/GUIDE.md`:
   - Reference validation requirement
   - Show example validation report
3. Create example validation script (optional):
   ```python
   # validate_research_spec.py
   # Reads research-interview spec, checks requirements, outputs report
   ```
4. Test validation with:
   - Valid spec (all checks pass)
   - Missing hyperparameters (should block)
   - Missing seeds (should warn)
   - Resources exceed system (should warn)

### Phase 5: Integration & Documentation
1. Update main CLAUDE.md:
   - Reference new date format standard
   - Note `/spec-interview-research` skill
   - Link to petri-plotting.md for visualization standards
   - Reference validation gate in Research Methodology section
2. Update dotfiles CLAUDE.md:
   - Document custom_bins/ additions
   - Note matplotlib petri style
3. Test full workflow:
   - Run `/spec-interview-research` → generates lightweight spec
   - Validation gate checks spec
   - Run experiment with Petri-style plots
   - Verify outputs use DD-MM-YYYY timestamps
4. Commit all changes with clear commit message

## Verification

### End-to-End Test
1. **Date helpers**:
   ```bash
   utc_date         # Should output: DD-MM-YYYY
   utc_timestamp    # Should output: DD-MM-YYYY_HH-MM-SS
   ```
2. **Research spec interview**:
   - Run `/spec-interview-research hypothesis-testing`
   - Verify asks about variables, hypotheses, baselines, resources
   - Check inline resource validation shows system specs
   - Verify output in `specs/research-interview-DD-MM-YYYY.md`
   - Validate spec has all required sections
3. **Petri plotting**:
   ```python
   import matplotlib.pyplot as plt
   import petriplot as pp

   plt.style.use('petri')
   fig, ax = plt.subplots()
   pp.flow_box(ax, "Test", (0, 0), color=pp.CORAL)
   plt.savefig(f'test_{utc_timestamp()}.png')
   ```
   - Verify warm beige background
   - Verify rounded boxes
   - Verify filename has timestamp
4. **Validation gate**:
   - Create incomplete spec (missing hyperparameters)
   - Attempt to run experiment
   - Verify blocks execution with clear error
   - Fix spec, retry, verify proceeds
5. **Non-destructive outputs**:
   - Generate plot multiple times
   - Verify each has unique timestamp filename
   - Verify no overwrites

### Files to Review
- `custom_bins/utc_date` and `utc_timestamp`
- `~/.claude/CLAUDE.md` (date format documentation)
- `~/.claude/skills/spec-interview-research/` (all files)
- `config/matplotlib/petri.mplstyle`
- `config/matplotlib/petriplot.py`
- `~/.claude/ai_docs/petri-plotting.md`
- `~/.claude/agents/research-engineer.md` (validation section)

## Critical Files to Modify

### New Files (14)
1. `custom_bins/utc_date`
2. `custom_bins/utc_timestamp`
3. `~/.claude/skills/spec-interview-research/SKILL.md`
4. `~/.claude/skills/spec-interview-research/references/research-interview-guide.md`
5. `~/.claude/skills/spec-interview-research/references/research-spec-template.md`
6. `config/matplotlib/petri.mplstyle`
7. `config/matplotlib/petriplot.py`
8. `~/.claude/ai_docs/petri-plotting.md`

### Modified Files (8)
1. `/Users/yulong/.claude/CLAUDE.md` - Date format docs, reference validation gate
2. `/Users/yulong/code/dotfiles/CLAUDE.md` - Document custom_bins, matplotlib style
3. `/Users/yulong/code/dotfiles/scripts/shared/helpers.sh` - Update backup_file()
4. `/Users/yulong/code/dotfiles/deploy.sh` - Update backup paths, add petri style deployment
5. `/Users/yulong/.claude/skills/experiment-setup/templates/hydra_config.yaml` - New date format
6. `/Users/yulong/.claude/skills/run-experiment/SKILL.md` - New date format in examples
7. `/Users/yulong/.claude/agents/research-engineer.md` - Add validation gate
8. `/Users/yulong/.claude/skills/experiment-setup/GUIDE.md` - Reference validation

## Out of Scope

- Updating all historical timestamps in logs/outputs (only new outputs use new format)
- TikZ/Excalidraw code generation (documented colors only, implementation later)
- Full research-spec.md integration (interview produces lightweight spec only)
- Automatic plot generation from metrics (user still writes plotting code)
- System resource monitoring/tracking (validation is one-time check at spec creation)
- Migration script for old date formats (update on-demand as files are touched)

## Open Questions

- [ ] Should `utc_timestamp` include seconds, or just `DD-MM-YYYY_HH-MM`? (Decided: include seconds for uniqueness)
- [ ] Should Petri style be default for new projects, or opt-in? (Decided: opt-in via `plt.style.use('petri')`)
- [ ] Should validation gate also check for code version (git commit) in spec? (Decided: nice-to-have, not blocking)
- [ ] Should plotting helpers include network graph layouts (for agent architectures)? (Decided: future extension)

## Success Criteria

✅ Date helpers output correct format and are in PATH
✅ CLAUDE.md documents new date format with examples
✅ `/spec-interview-research` generates complete lightweight research spec
✅ Research spec includes all required sections (variables, hypotheses, baselines, metrics, graphs, resources)
✅ Resource validation runs inline during interview and shows system specs
✅ Validation gate blocks execution if critical items missing
✅ Petri matplotlib style produces warm beige background with pastel accents
✅ `petriplot.py` can generate rounded boxes and flow arrows
✅ Color palette documented for TikZ/Excalidraw use
✅ Plot filenames include timestamps and never overwrite
✅ End-to-end workflow: interview → spec → validation → experiment → Petri plots works seamlessly
