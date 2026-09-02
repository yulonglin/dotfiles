---
name: spec-interview-research
description: Interview Yulong into a research spec before an experiment is built — hypotheses and what would falsify them, independent and dependent variables, controls and confounds, baselines, datasets, sample size and power, resources, reproducibility. Use when starting a new experiment, an ablation, an A/B test or a benchmark run, when a design needs its assumptions challenged before any code is written, or on "spec this experiment", "help me design this run", "interview me about this experiment".
---

# Research Spec Interview

The question bank is the content: **`~/.claude/skills/spec-interview-research/references/research-interview-guide.md`** holds 15 categories with the questions under each. Read it now and work from it; this file only says how to run the interview and where the answers go.

What makes a design worth running — falsifiability, the arm that can lose, the null, the pilot gate — is in `~/.claude/checklists/research.md`, and the shape of the spec you write at the end is in the `spec-artifact` skill. Neither is restated here.

## Run it in rounds, and challenge rather than transcribe

Open by saying what the interview covers, then ask **2-4 questions per round** rather than dumping all 15 categories. Start high-level (research question, motivation, hypotheses), then drill into the categories where guessing wrong would waste the whole run — usually the independent variables, the confounds and the baselines.

Challenge constructively as you go: "why baseline X instead of Y?", "what if confound Z explains the result?", "how confident are you in that assumption?". A transcribed interview produces a spec that agrees with whatever the researcher already believed.

**Validate resources inline**, at the moment they come up, not afterwards. Run `nproc && free -h` on Linux or `sysctl hw.physicalcpu hw.memsize` on macOS, compare against the stated requirement, and say plainly which way it came out. A resource number nobody checked is the one that kills the run at hour three.

## The spec is an Artifact, not a file

`~/.claude/skills/spec-interview-research/references/research-spec-template.md` gives the section-by-section shape — question, hypotheses with falsification, the four variable classes, models, baselines, datasets, metrics, resources, reproducibility. It maps onto the three mandatory spec sections: Overview, Requirements (the variables and baselines), Acceptance Criteria.

Publish it as an Artifact and hand back the link. There is no `specs/` folder convention here — a spec exists to be argued with, and a file in a folder cannot be argued with. Mechanics are in `spec-artifact` and `artifact-writing`. One experiment keeps one link: update it in place rather than minting a new URL per revision.

Then present it and ask what is missing before anything gets built.

## Reach for a neighbour instead when

- the plan is **already written** and the job is to stress-test it: the `interview-me` skill
- the questions are **not about an experiment** — a feature, a tool, a piece of product work: the `spec-interview` skill
- you need the **spec shape** rather than the interview: `spec-artifact`
- the run is designed and the question is how to **get it to finish**: `~/.claude/checklists/experiments.md`, and the `jobs` skill for queues and caps
- the run is **done** and the question is what it means: `~/.claude/checklists/results-analysis.md`
