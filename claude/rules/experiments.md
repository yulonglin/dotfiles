# Experiments

**Pilot before scale — a hard gate.** Nothing larger than about three samples until one or two have gone end to end through every stage and been eyeballed this session, on this code; `n=1` does not validate scaling, since memory and length failures first appear around `n≥4`.

**Spend gate.** Estimate from actual rates. Under $100, run now and report the estimate with the result; $100 or more, propose and wait. Pre-paid cluster allocations skip it.

**Never launch detached work inside a subagent** — its children are orphaned when the turn ends. Memory-heavy or long-lived work (past ~2 GB RSS or ~1 h) goes to the queue via `jexp` for its caps; pure API fan-out runs backgrounded from main context. The runner-by-shape table is in the checklist; commands and caps are in the `jobs` skill.

**The full standard is `~/.claude/checklists/experiments.md`** — piloting, the five-minute failure checks, resource awareness, exploratory vs confirmatory, and what the output directory must explain on its own. Designing the experiment before it runs: `~/.claude/checklists/research.md`.
