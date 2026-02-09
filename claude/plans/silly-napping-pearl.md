# Plan: Seed Interview → SEED.md for C3 Adoption Barriers

## Context

The C3 (Cross-Context Consistency) method detects sandbagging by measuring inconsistency across paraphrased questions — sandbagging models choose *different* failure strategies each time, while genuinely incapable models fail consistently.

**Paper status:** Submitted to **ICML 2026** (main conference, anonymous) + multiple **ICLR 2026 workshops** (ICBINB, Trustworthy AI, Logical Reasoning, Agents in the Wild). Full paper is 1494 lines, 65+ sandbagging prompts, results across GPQA/MATH/USACO.

**Current results summary:**
- Prompted sandbagging: 67-100% recall @ 5% FPR (domain-dependent)
- Cross-capability (GPT mimicking weaker GPT): 94-100% recall
- Fine-tuned (password-locked): 36-53% recall (hardest prompted setting)
- Discovered incentive (Meinke-style scheming): 19% recall — only method with any signal
- Baselines (Trusted Monitoring, Lie Detectors): fail in same-model settings

**Known limitations from paper:**
1. Deterministic error recipes defeat C3 (but TM catches them → defense-in-depth)
2. Instruction-following confound → false positives
3. Not tested against RL-optimized adversaries
4. Only verified-answer domains (no open-ended tasks)
5. Cross-model style confound in cross-capability setting

**Key tensions the user raised (beyond paper):**
- **Model-level variation**: GPT-5-nano inherently less consistent than GPT-4.1-nano. Benign-but-uncertain models may look like sandbaggers.
- **Confidence ↔ consistency correlation**: Low confidence → low consistency → false positives. This is the core confound.
- **Operationalization for adoption**: What do frontier labs/auditors actually need? Thresholds? Calibration sets? Per-model baselines? How many queries?

## Plan

### Step 1: Run `/1-seed-interview`

Interactive 7-question interview to crystallize the brainstorming direction:
1. The Anomaly — what observation triggered this line of thinking
2. The Stakes — what changes if we solve adoption barriers
3. Prior Art — existing work on eval methodology adoption
4. The Experiment — 1-day test to probe the core question
5. The Kill Condition — what would prove this direction is a dead end
6. The Surprise — what result would shock experts
7. Rough Ideas — user's initial directions (they've already started articulating some)

The interview will incorporate context from the paper: current results, known limitations (deterministic error recipes, instruction-following confounds, fine-tuned sandbaggers), and the specific adoption questions the user raised.

### Step 2: Generate SEED.md

Create idea directory `ideas/YYYYMMDD-HHMMSS-c3-adoption-barriers/` with:
- `SEED.md` from interview answers
- `resources/` — link/copy relevant paper sections
- `scratchpad/` — ready for divergence

### Step 3: Validate & Share

The user wants to share this with LLMs and collaborators. The SEED.md + a concise summary of C3's current state should be self-contained enough for external readers to engage with.

## Verification

- SEED.md passes the quality gate (specific question, defined terms, falsifiable claim, kill condition)
- Document is self-contained for external readers (includes enough C3 context)
