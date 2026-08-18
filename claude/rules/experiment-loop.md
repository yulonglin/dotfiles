# Experiment-Loop Commandments

For every empirical run — eval, rollout batch, sweep, replay. Born from monitorability-evals' August 2026 failure streak (9 failed launches, all self-inflicted); adapted from "Tips for Empirical Alignment Research" (LessWrong). Repo-specific numbers live in each repo's own `.claude/rules/experiment-loop.md`.

1. **Smoke first, always.** No run larger than ~3 samples until a tiny end-to-end run has produced nonempty, parseable output this session, on this code. n=1 does not validate scaling (memory/length failures routinely first appear at n≥4).

2. **Fail within 5 minutes.** Everything knowable before generation must be checked before generation: endpoint health (with a cold-boot-sized timeout, not a 20s probe), `df` for ≥3× projected output, `free -g` against the planned readers' budgets, auth. A run that dies at hour 3 for a minute-2-knowable reason is a process failure.

3. **Budget memory per process, enforced.** Any reader/analysis process expected to exceed ~2GB RSS runs under `capped -- <cmd>` (`custom_bins/capped`), which applies `MemoryMax`, takes an exclusive lock so only one heavy reader runs per box, and fails closed rather than running uncapped. Full-file log parsers cost order-30× file size in RSS — stream per-sample where the API allows. **Never set `MemoryHigh` as the safety limit**: it throttles rather than kills, and with `MemorySwapMax=0` a runaway sits between High and Max indefinitely instead of dying (measured 2026-08-18: a 2GB allocation under `MemoryMax=256M` survived past 90s with High at 80% and 95%; without High it was killed in ~1s). A cap that hangs is worse than no cap, because nothing reports the stall.

4. **Disk is shared across sessions.** Bulk pulls (Modal volumes, HF snapshots) target a data volume or checked path, never the root fs. A free-space watchdog runs whenever a long job is in flight.

5. **The debug iteration unit is under 5 minutes.** Debug on 1-sample runs or recorded fixtures, never by relaunching the full experiment with a print added.

6. **A normal experiment targets under 1 hour.** Longer only when intrinsically necessary (training, exhaustive-attempt designs) — and then on a durable host (tmux/systemd, never a subagent's shell), with completion + resource monitors armed before launch.

7. **Estimate resources out loud before launching.** $ at verified rates, GPU-hours, peak reader RSS, output bytes, API tokens. Concurrency is a decision, not a default: check what else shares the box/endpoint first.

8. **Validate outputs as they land, not after the run.** First rows checked for nonempty/parseable/sane before the next stage spends money. Prefer append-only, resumable pipelines so downstream stages can start on partial data.

9. **Provenance is cheap; guard machinery must earn its keep.** Keep pinned revisions, seeds, prompt hashes, manifests, append-only rows with rendered inputs. But when a validator or cache has caused more failures than it caught, delete it — prefer deleting complexity to optimizing it.

10. **Record wall-clock time.** `date` at start and end of substantial tasks; log elapsed beside the result (user is in Berkeley, PT). Unknown cost can't be prioritized.
