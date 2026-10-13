# Rigour checks: duplicates and contradictions

Companion to `checks.json` (75 rows). Line numbers are from commit `96c350bd`. `C/` below means `/Users/yulong/code/dotfiles/claude/`.

## Almost nothing is enforced

Of 75 checks, 72 are text only. The only rigour-adjacent hooks that actually run are `block_unannotated_artifact.sh` (blocks an HTML publish without the annotation layer), `nudge_uncapped_reader.sh` plus `capped` failing closed, and `require_plan_approval.sh` (a systemMessage on EnterPlanMode).

- The four substitution guards exist, are tested in `C/hooks/test_substitution_guards.sh`, and have a wiring script (`/Users/yulong/code/dotfiles/scripts/setup/wire_harness_hooks.py:112-117`), but they are not wired in the live `~/.claude/settings.json`: `guard_existing_code.sh`, `nudge_synthetic_data.py`, `nudge_hyperparam_provenance.py`, `nudge_number_provenance.py`.
- `nudge_experiment_jobs.sh` is wired (`C/settings.json:424`) but disabled by `nudges = off` (`C/hooks/features.conf:4`).
- `verify_pueue_kill.sh` is unwired.
- Agent prompts that say BLOCKING or MANDATORY (research-engineer, data-analyst) fire only when that agent is dispatched.

## Contradictions

- **Interval formula.** `C/docs/ci-standards.md:17-20` uses the normal approximation (mean ± 1.96 SE) for every score. `C/skills/results-artifact/SKILL.md:14` says proportions get Wilson, never the normal approximation. These are hard conflicts. data-analyst, research-skeptic and experiment-designer all point at ci-standards.
- **Overlapping CIs.** `C/docs/ci-standards.md:36` says to bold the best method only if the CIs do not overlap. `C/skills/results-artifact/SKILL.md:14` says overlapping intervals are never a substitute for a paired test.
- **A point estimate without an interval.** `C/agents/data-analyst.md:274` says never report a point estimate without uncertainty. `C/checklists/results-analysis.md:17` says a failed attempt gets no take-rates with Wilson bounds. `C/checklists/results-analysis/sandbagging.md:54` says to report the point estimate alone when the only interval is degenerate.
- **Seed count.** `C/checklists/experiments.md:66` and `C/checklists/results-analysis.md:11` set at least 2 seeds as mandatory for any quoted stochastic result ("the one place to change it"). `C/agents/research-engineer.md:119,140` makes seeds only a WARN and suggests 5. `C/skills/spec-interview-research/references/research-interview-guide.md:94` also suggests 5. `C/docs/ci-standards.md:53-61` says small-n seeds get mean and range, no CI. `C/skills/inspect-ai-evals/SKILL.md:101-105` makes repeat seeds a second phase, gated on first showing signal. That last one can be reconciled as explore-versus-quote, but no file says so.
- **Human gates against "commit and run".** `C/CLAUDE.md:16` says to proceed on partial answers and stop only for the irreversible. Two places add human gates anyway:
  - `C/agents/research-engineer.md:99-167` makes the agent STOP before writing code and wait for the user to edit the spec, and asks Y/n on warnings.
  - `/Users/yulong/code/dotfiles/.claude/skills/verification-planning/SKILL.md:12-19` says to enter plan mode before running an experiment or analysing results. `C/hooks/require_plan_approval.sh` then says to ask the user before entering plan mode. That is two gates per experiment, but only in the dotfiles repo.
- **Multiple comparisons.** `C/agents/data-analyst.md:33,243` and `C/agents/experiment-designer.md:54` require a Bonferroni or FDR correction. `C/rules/research-core.md:11` and `C/checklists/results-analysis.md:105` require disclosing how many slices and comparisons were examined, not a correction. Two different policies.
- **Behaviour-free baseline (wording tension; I read it as soft, not hard).** `C/checklists/results-analysis.md:15` says the scaffold-only baseline is a diagnostic of the organism, not the bar a detector must clear. It also says that saying "the detector failed to beat the style null" misattributes the failure. `C/checklists/results-analysis/sandbagging.md:31` says a detector that does not beat this null "has not been shown to read behaviour at all". `C/skills/results-artifact/SKILL.md:29` says "the experiment is measuring the scaffold". All three agree that no detection claim can be made, but sandbagging.md reads as making it the detector's bar. Reword sandbagging.md:31 to match.
- **Keyword triage against "never regex for meaning".** `C/docs/transcript-review-checklist.md:86-99` lists grep strings for eval awareness and refusals. `C/skills/llm-judge/SKILL.md:8` says classification by meaning never uses keywords. This is acceptable as Tier-1 triage, but nothing says it is not a measurement.
- **Stale pointer.** `C/skills/spec-interview-research/SKILL.md:10` says the pilot gate is in research.md. It is in `C/checklists/experiments.md:9-15`.
- **Style.** `C/rules/communication.md:17` and `C/checklists/presentation.md:51` say never write "arm". `C/checklists/experiments.md:7`, `C/checklists/research.md:15` and `C/checklists/results-analysis/sandbagging.md` use it throughout.

## Most duplicated checks

Each was merged into one row; the row's `locations` lists every copy.

| Check | Copies |
|---|---|
| Two-stage pilot (P01) | 8 |
| Seeds (U08) | 9 |
| Interval and unit of analysis (A04) | 10 |
| Null and chance line (A01) | 9 |
| No mock data (U13) | 10 (five agent prompts; the only always-on copy is CLAUDE.md:38) |
| Reproducibility logging (U10) | 8 |
| Prediction in the manifest (D01) | 7 |
| No broad try/except (U14) | 5 (agent prompts only) |

`C/rules/experiments.md` restates the pilot and spend gates from `C/checklists/experiments.md` almost word for word. `C/rules/research-core.md` restates `C/checklists/results-analysis.md:111-119`. Both duplications are by design, since the rule files are the always-loaded tier, but they use always-on budget. That makes the two restatements in `rules/experiments.md` trim candidates.

## Most costly checks for iteration speed

These come only from the design, pilot and run stages.

1. **D13, research-engineer's 9-item blocking spec gate.** It is a human wait, and most of its items do not change a result. Lean: drop.
2. **D14, verification-planning plus require_plan_approval.** Two human gates per experiment, scoped to the dotfiles repo today. Lean: soften.
3. **D06, an adaptive-attack hour per detector.** It costs an hour if read as applying to every iteration. Lean: require it before quoting.
4. **D16, the overnight pre-launch review.** A human gate before every overnight run. Lean: launch on a stated default after a timeout.
5. **P06, the spend gate at $100 or more.** A human wait, though the threshold keeps most iterations ungated. Lean: keep.

Runner-up: **U08**, two seeds for quoted results, doubles compute. Effort is only M, but the cost is in money and wall-clock time.
