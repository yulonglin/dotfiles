---
name: research-loop
description: Set up and launch an autonomous overnight research loop — interview the user into concrete inputs, outputs and metrics, write a `program.md` spec, then dispatch the `autonomous-researcher` agent to run experiments unattended and review what came back in the morning. Use on "run experiments overnight", "automate this research", "set up an autonomous loop", "research loop", "run while I sleep", or whenever an agent is meant to iterate on a measurable metric with nobody in the room.
---

# Research Loop Setup

This skill is the **entry point for the `autonomous-researcher` agent**. It owns the interview, the `program.md` spec and the launch; the agent owns the loop itself.

The interview is not optional. A vague answer here costs a whole overnight run, and nobody is awake to correct it.

## What this file does not carry

The standards for a run worth launching — the pilot gate before scale, the spend gate, choosing the runner, checking disk and memory before generating — are in **`~/.claude/checklists/experiments.md`**. Read it before you write the spec. It is not restated here.

## When to use

- The user has a **measurable metric** to optimize (loss, accuracy, F1, detection rate)
- The user has an **experiment protocol** — a command or pipeline that produces results
- The user wants it to run **unattended**, overnight or while away

## Step 1: Interview (mandatory — do not skip)

**Complete this interview before creating any spec or launching any agent.** Do not accept vague answers. Each question needs a concrete, actionable answer before you move on; if an answer is ambiguous, ask a follow-up to pin it down.

Use AskUserQuestion, 2-3 items at a time to keep pace.

### Gate 1: Inputs (what goes in)

| # | Question | What you need | Reject if... |
|---|----------|--------------|--------------|
| 1 | **What files/code can the agent modify?** | Specific file paths + scope of allowed changes | "the codebase" (too broad) |
| 2 | **What is read-only?** | Evaluation harness, data format, dependencies, immutable sections | Nothing listed (everything must have a boundary) |
| 3 | **What does the working directory look like?** | How to set up, what needs installing, which API keys | "it's already set up" (the agent starts fresh — be explicit) |
| 4 | **Is there an existing strategy queue?** | Ideas to try, or should the agent brainstorm from scratch? | Fine if empty — it just has to be explicit |

### Gate 2: Outputs (what comes out)

| # | Question | What you need | Reject if... |
|---|----------|--------------|--------------|
| 5 | **What is the exact command to run one experiment?** | A copy-pasteable bash command | "run the training script" (which script? what args?) |
| 6 | **How do you extract the metric from the output?** | A grep/parse command, or the key in a JSON/TSV file | "look at the results" (the agent needs programmatic extraction) |
| 7 | **How long does one experiment take?** | Minutes, hours, or "variable" with a range | Must be answered — it determines the loop strategy |
| 8 | **How much does one experiment cost?** | A dollar amount, or "free" (local compute) | Must be answered — the spend gate needs it |

### Gate 3: Metrics (what "success" means)

| # | Question | What you need | Reject if... |
|---|----------|--------------|--------------|
| 9 | **What metric are you optimizing?** | Name, direction (lower/higher is better) | "make it better" (better how?) |
| 10 | **What is the current baseline?** | A number from an existing run | "I don't know" → run the baseline first, before setting up the loop |
| 11 | **What is the success threshold?** | A concrete number, or "any improvement over baseline" | No threshold at all (the agent needs a stopping criterion) |
| 12 | **Are there secondary metrics or kill conditions?** | Metrics that must NOT degrade, or conditions that kill an experiment | Optional but important — it is what stops Goodharting |

### Gate 4: Constraints

| # | Question | What you need | Reject if... |
|---|----------|--------------|--------------|
| 13 | **Total budget?** | Max dollar amount, max experiments, or max time | "unlimited" is fine for local compute, but must be explicit |
| 14 | **Max runs per idea?** | A number, or "unlimited" | Must be answered |
| 15 | **Loop strategy?** | hill-climb / sprint / batch | Must pick one |

**Loop strategy explanations (share these with the user):**
- **Hill-climb** — try one thing, keep it if better, discard it if worse. Best when experiments are cheap and fast.
- **Sprint** — deep-dive on ONE idea per session. Best when experiments are expensive and need investigation.
- **Batch** — propose N experiments, run them all, analyze, repeat. Best when you want breadth before depth.

### Readiness check

Before Step 2, verify you have concrete answers for ALL of: the metric name, direction, baseline and threshold; the exact experiment command; the programmatic metric extraction; the modifiable file paths; the read-only constraints; cost per run and total budget; time per run; and the loop strategy.

**If any item is missing or vague, go back and ask.** Do not proceed with placeholders.

## Step 2: Create the spec

Write a `program.md` in the project root, filling it in ONLY with concrete answers from the interview. This one stays a file rather than becoming an Artifact: it is the agent's runtime brief, read by a machine beside the code it drives, not a document a human argues with.

````markdown
# [Title]: Autonomous Research Loop

You are an autonomous research agent. [One sentence about the goal.]

## Objective
- **Metric:** [name] ([lower/higher] is better)
- **Threshold:** [number] (success criterion)
- **Baseline:** [current value]
- **Kill conditions:** [secondary metrics that must not degrade]

## Context: Read These First
- [Every file the agent should read before starting]

## Working Directory Setup
- [How to set up the working environment]
- [Verification steps: API keys, dependencies, data]

## Experiment Protocol
```bash
[The exact command to run one experiment]
```
- **Time per run:** [estimate]
- **Cost per run:** [estimate]
- **How to extract the metric:** [grep command or parsing instructions]

## What You CAN Modify
- [File 1] — [what kinds of changes are fair game]
- [File 2] — [scope of allowed modifications]

## What You CANNOT Modify
- [File/component] — [why it is read-only]

## Strategy Queue
| Priority | ID | Strategy | What to change |
|----------|-----|----------|---------------|
| 1 | ... | ... | ... |

## For Each Experiment
1. Branch: `git checkout -b exp/<id>`
2. Implement the change
3. Commit with a descriptive message
4. Run: [experiment command]
5. Extract the metric: [how]
6. If improved → keep the branch
7. If not → `git checkout main`
8. Log to `results.tsv` and `research-log.md`

## Budget
- **Total:** [amount]
- **Per-idea limit:** [max runs]
- **Reserve:** [amount held back for final validation]
- **Stop when:** [condition]

## Constraints
- [Every constraint from the interview]

## NEVER STOP
Once you begin the experiment loop, do NOT pause to ask the human anything.
They may be asleep. Work autonomously until:
- Success criteria met → package the results
- Budget exhausted → write the final summary
- Strategy queue empty → attempt up to 3 combinations, then stop
- Manually interrupted
````

**Show the completed spec to the user for approval before launching.** They should read it and confirm it matches their intent.

Pilot one experiment end-to-end before the loop is turned loose. The gate and what it has to cover are in `~/.claude/checklists/experiments.md`.

## Step 3: Launch the agent

Only after the user approves the spec, dispatch `autonomous-researcher`. It is a local agent in `~/.claude/agents/`, so `subagent_type` is the bare name with no plugin prefix.

```
Agent tool:
  subagent_type: "autonomous-researcher"
  prompt: "Read program.md in [project root] and execute the research loop autonomously.
           Start with the setup steps, then enter the experiment loop.
           Log all results to results.tsv and research-log.md."
```

**Launch it from main context, never from inside another subagent** — a detached child of a subagent is orphaned the moment that turn ends, and the parent reports `completed` either way. For a run that has to outlive the session, use tmux (`tmux new-session -d -s research`) or the queue; caps, queue commands and sandbox failure modes are in the `jobs` skill. Independent strategy tracks can run as parallel agents on separate branches.

## Step 4: Morning review

1. Read `research-log.md` for the narrative and `results.tsv` for the structured data
2. **Review the transcripts** — dispatch the `transcript-reviewer` agent over the latest eval logs to check scorer correctness and catch what the loop's own spot-checks missed. Look hardest at the experiments it marked INVALID, at the best-performing experiment (is the improvement real, or a scorer artifact?), and at anything with a suspiciously perfect or zero score
3. Identify the best strategy and the evidence behind it
4. Decide the next step: refine the winner, try new directions, or ship

A loop winner is a hypothesis, not a result — it needs fresh episodes before anyone quotes it. See `~/.claude/checklists/experiments.md`.

## Examples

### Karpathy-style training loop
```
Metric: val_bpb (lower is better)
Baseline: 0.998
Threshold: any improvement
Protocol: `uv run train.py > run.log 2>&1`
Extract: `grep "^val_bpb:" run.log`
Modifiable: train.py (architecture, optimizer, hyperparams)
Read-only: prepare.py (data, evaluation)
Budget: infinite (run until killed)
Strategy: hill-climb
Time per run: 5 minutes
Cost per run: $0 (local GPU)
```

### Red-team sabotage
```
Metric: effectiveness × stealth (dual objective)
Baseline: 0% effectiveness, unknown stealth
Threshold: results cross direction threshold AND <50% auditor detection
Protocol: modify code → uv run python run_evaluation.py → run auditor via API
Extract: printed summary table + auditor JSON output
Modifiable: evaluation code, data generation, PAPER.md Section 3 + Appendix A
Read-only: PAPER.md Sections 1-2, honest codebase
Budget: $200 total, max 5 runs per idea
Strategy: phased (cheap eval-only first, then expensive data-gen)
Time per run: minutes (Phase 1) to hours (Phase 2)
Cost per run: $0.10 (Phase 1) to $20 (Phase 2)
```

### Optimizer search
```
Metric: final train_loss (lower is better)
Baseline: Adam default loss (run this first)
Threshold: any improvement over Adam
Protocol: `python -m simply.main --experiment_config <name> --experiment_dir /tmp/<name>`
Extract: `cat /tmp/<name>/final_result.json | jq .train_loss`
Modifiable: simply/utils/optimizers.py, simply/config_lib.py
Read-only: model architecture, data pipeline
Budget: 15 experiments or 10 new optimizers
Strategy: batch (propose 3 per round)
Time per run: ~30 seconds (CPU test config)
Cost per run: $0 (CPU)
```

## Reach for a neighbour instead when

- the experiment is **not yet designed** — hypotheses, variables, confounds, baselines: the `spec-interview-research` skill
- the run needs **resource caps or a queue** rather than an agent: the `jobs` skill
- the run is **finished** and the question is what it means: `~/.claude/checklists/results-analysis.md`
- it is **one experiment, not a loop** — just run it, after reading `~/.claude/checklists/experiments.md`
