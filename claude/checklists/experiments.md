# Experiments

Running experiments: getting a run to finish, and trusting it when it does.

## Run the small thing instead of writing about it

A number that does not fit the story, "is X or Y better?", a mechanism claimed twice and tested zero times — each is an arm, not an opinion. One contrast, matched on everything else, an arm that can lose, reported whichever way it came out.

## Pilot in two stages, both hard gates

A single pilot cannot clear both things a pilot is for, because `n=1` does not validate scaling — memory and length failures first appear around `n≥4`, which is above every size a one-sample pilot reaches. A run that clears a one-sample gate and goes straight to full scale can still OOM at hour three.

**Stage one, `n=1–2`, for correctness.** Every stage — parse, audit, render, compute, measure, report — runs end to end and is eyeballed this session, on this code. This proves the pipeline computes something, and nothing about whether it survives volume.

**Stage two, `n≥4` or the largest subsample you can afford, for memory and length.** Watch peak RSS and the longest rendered input, not just the exit code. Nothing goes to full scale until stage two has passed.

Audit the input for truncation, chrome and placeholder tokens, **with counts**, before any stage consumes it. Freeze rendering rules, prompt hashes, thresholds, the prediction and the planned `n` in a manifest before the first scored call — the prediction goes there rather than in chat, because a result that could not have come out differently was not an experiment (`research.md`). Give every spending stage a `--dry-run` you actually read.

## Contamination invalidates a run before it starts

The input audit above catches formatting damage; it says nothing about validity. The failures that quietly void a whole run are eval items already present in pretraining or finetuning data, few-shot exemplars that overlap the test set, and prompts reused across conditions that will later be compared.

Record the dataset and split hashes in the manifest alongside the prompt hashes. State the contamination check you ran — canary strings, n-gram or embedding overlap against the finetuning data — or state explicitly in the manifest that none was possible and that the numbers carry that caveat. Draw few-shot exemplars from a pool disjoint from the test items, and never reuse a test item across two conditions you intend to compare.

## Fail in five minutes, not at hour three

Before generating: endpoint health, disk for 3× projected output, memory against the readers' budgets, auth. Estimate dollars, GPU-hours, peak RSS and tokens out loud.

Debug on one-sample runs or fixtures — never by relaunching the full run with a print added. Validate outputs as they land. Prefer append-only resumable pipelines whose resume keys include the prompt and config hashes, so a reworded prompt invalidates stale rows rather than silently reusing them.

**Spend gate.** Estimate from actual rates. Under $100, run now and report the estimate with the result. $100 or more, propose and wait. Pre-paid cluster allocations skip it.

## Resource choices are decided and recorded

Concurrency is a decision about what else shares the box, not a number to maximise — so the manifest states the concurrency level chosen and what else was running on the box while the run held it. A level nobody wrote down cannot be blamed for the OOM afterwards.

- **Memory-heavy or long-lived** (past ~2 GB RSS or ~1 h) goes to the queue, whose cgroup caps are what stop the box OOMing.
- **Pure API fan-out** runs backgrounded from the main context, where a queue only adds latency.
- **Never launch detached work inside a subagent** — its children are orphaned when the turn ends, and the agent reports success regardless.
- Check a group's parallelism before submitting a fan-out.
- Parallelise embarrassingly parallel loops by default. Sequential only for real ordering dependencies, shared mutable state, or OS-level exclusivity.
- Cache on a key that includes everything that changes the answer: prompt, model, sampling parameters, config. A cache keyed on too little is worse than none.
- Disk: 3× projected output, checked before starting. Rate limits: know the ceiling and the retry policy before the fan-out, not after the 429s.

## Choosing the runner

The question is API-bound, GPU-bound, or memory-heavy — then route:

| Shape | Runner |
|---|---|
| API fan-out over many samples | backgrounded async from main context, batch APIs where latency allows |
| GPU, short | Modal |
| GPU, long or interactive | RunPod |
| Cluster allocation | SLURM |
| Anything past ~2 GB RSS or ~1 h | the local queue (pueue, via `jexp`), for its caps |
| Evals | Inspect AI, watching `max_samples`, `max_connections` and `stop_reason` |

## Say which kind of run it was

Sweeping variants is fine and often the point, but **the winner is a hypothesis, not a result** — it needs fresh episodes before it is quoted. Say explicitly whether a run was exploratory or confirmatory.

**One draw at temperature above zero is a sample, not a number.** Any stochastic run quoted as a result was either repeated across a stated number of seeds — at least two, the floor `results-analysis.md` sets and the one place to change it — with the variance reported, or run at temperature 0 — and the report says which of the two it was. A single nondeterministic draw quoted as a result is the cheapest way to publish noise.

Keep pinned revisions, seeds, prompt hashes and rendered inputs. Delete guard machinery that has broken more of the last ten runs than it caught problems in — counted from the run log, not from memory, because a guard is remembered by its last save and forgotten for every hour it cost.

**The output directory explains the experiment on its own** to a capable colleague who has never seen it. What counts as an output rather than scratch: `results-analysis.md`.

## Report what happened

Every condition, including the ones that did not work. Never quietly drop a failed condition, an outlier or a null result. Every surprise named in the report carries either a linked follow-up or a stated reason for not pursuing it — offering an explanation instead of either is the explaining-away this rule forbids.

## Related

Choosing what to run and designing it: `research.md`. Analysing and reporting what came back: `results-analysis.md`. Queue commands, caps and sandbox failure modes: the `jobs` skill.
