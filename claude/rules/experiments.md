# Experiments

**Pilot in two stages, both hard gates.** Stage one at `n=1–2` for the correctness of every stage, eyeballed this session on this code. Stage two at `n≥4` for memory and length, which is where those failures first appear — so a one-sample pilot cannot clear them. Nothing reaches full scale until both pass.

**Spend gate.** Estimate from actual rates. Under $100, run now and report the estimate with the result; $100 or more, propose and wait. Pre-paid cluster allocations skip it.

**Never launch detached work inside a subagent** — its children are orphaned when the turn ends. Memory-heavy or long-lived work (past ~2 GB RSS or ~1 h) goes to the queue via `jexp` for its caps; pure API fan-out runs backgrounded from main context. On a server with an attached volume at `/workspace`, experiment outputs and log directories go under `/workspace`, not the root disk. The runner-by-shape table is in the checklist; commands and caps are in the `jobs` skill.

**The full standard is `~/.claude/checklists/experiments.md`** — piloting, the five-minute failure checks, resource awareness, exploratory vs confirmatory, and what the output directory must explain on its own. Designing the experiment before it runs: `~/.claude/checklists/research.md`.
