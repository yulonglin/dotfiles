# Experiments

Getting a run to finish, and trusting it when it does.

## Run the small thing instead of writing about it

A number that does not fit the story, "is X or Y better?", a mechanism claimed twice and tested zero times — each is an arm, not an opinion. One contrast, matched on everything else, an arm that can lose, reported whichever way it came out.

## Pilot before scale, and treat it as a gate

Nothing larger than about three samples until one or two have gone end to end through **every** stage — parse, audit, render, compute, measure, report — and been eyeballed this session, on this code. This is a hard gate. `n=1` does not validate scaling: memory and length failures first appear around `n≥4`.

Audit the input for truncation, chrome and placeholder tokens, **with counts**, before any stage consumes it. Freeze rendering rules, prompt hashes and thresholds in a manifest before the first scored call. Give every spending stage a `--dry-run` you actually read.

## Fail in five minutes, not at hour three

Before generating: endpoint health, disk for 3× projected output, memory against the readers' budgets, auth. Estimate dollars, GPU-hours, peak RSS and tokens out loud.

Debug on one-sample runs or fixtures — never by relaunching the full run with a print added. Validate outputs as they land. Prefer append-only resumable pipelines whose resume keys include the prompt and config hashes, so a reworded prompt invalidates stale rows rather than silently reusing them.

**Spend gate.** Estimate from actual rates. Under $100, run now and report the estimate with the result. $100 or more, propose and wait. Pre-paid cluster allocations skip it.

## Resource awareness is a decision, not a default

Concurrency is a decision about what else shares the box, not a number to maximise.

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
| Anything past ~2 GB RSS or ~1 h | the local queue, for its caps |
| Evals | Inspect AI, watching `max_samples`, `max_connections` and `stop_reason` |

## Say which kind of run it was

Sweeping variants is fine and often the point, but **the winner is a hypothesis, not a result** — it needs fresh episodes before it is quoted. Say explicitly whether a run was exploratory or confirmatory.

Keep pinned revisions, seeds, prompt hashes and rendered inputs. Delete guard machinery that has caused more failures than it caught.

**The output directory explains the experiment on its own** to a capable colleague who has never seen it. Scripts, plots, report and figures are outputs, not scratch.

## Report what happened

Every condition, including the ones that did not work. Never quietly drop a failed condition, an outlier or a null result. Investigate surprises rather than explaining them away.

## Related

Choosing what to run: `research.md`. Reporting: `results.md`. Queue commands, caps and sandbox failure modes: the `jobs` skill.
