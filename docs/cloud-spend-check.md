# cloud-spend-check: flat daily spend is the idle-resource signature

`custom_bins/cloud-spend-check` reports cloud resources billing a near-identical amount every day. A daily systemd timer runs it, and `claude/hooks/nudge_cloud_spend.sh` surfaces any finding at session start.

## Why it keys on flatness rather than on size

In 2026-08/09 one Modal H100 billed about $96 a day for 30 days and nobody noticed: $3,060, 96.7% of all Modal spend in the period. A health-check poller left running in a tmux pane polled the endpoint every 180 s against a 300 s `scaledown_window`, so the container could never scale to zero. The full write-up is `~/vault/research/monitorability/docs/2026-09-16-modal-h100-watchdog-burn.md`.

Candidate rules were simulated against that real billing series, 61 days, with `tests/fixtures/modal-billing-2026-07-16_2026-09-15.json` as the captured input:

| Rule | First fires | Saved | False positives |
|---|---|---|---|
| Any day over $50 | 2026-08-13 | $3,056 | 6, all on real eval work |
| 3 days running over $50 | 2026-08-17 | $2,741 | 0 |
| 3 flat days, under 5% variance | 2026-08-17 | $2,741 | 0 |
| Rolling 7-day over $500 | 2026-08-18 | $2,580 | 1 |

The plain magnitude threshold fires earliest and is the worst choice: six of its firings are legitimate work, and a guard that cries wolf gets muted. The two zero-false-positive rules tie, and **this data cannot separate them** — the sample holds no legitimate run lasting three or more days above $50/day, which is the case that breaks the "3 days running" rule. Flatness is preferred on mechanism, not on these numbers. Real work varies day to day because splits, rollouts and interruptions differ; an idle pinned container held flat to within 1% for a month.

## What it cannot decide

A flat series is not proof of waste. A long training run on a fixed allocation is flat too. The output asks whether the spend is still intended and never stops anything — acting on it is a human's job. That is also why the nudge is advisory and the tool has no `--kill` mode.

## Tuning and scope

Thresholds come from the environment: `CLOUD_SPEND_FLAT_DAYS` (default 3), `CLOUD_SPEND_FLAT_TOL` (0.05), `CLOUD_SPEND_FLOOR` (20 dollars/day). State is `~/.local/state/cloud-spend/latest.json`, which the nudge reads.

Modal is the only implemented collector and it queries **every** profile in `~/.modal.toml`, not just the active one — the incident's spend sat in a shared workspace that was not this machine's default. `runpod`, `vastai` and `mats` are recognised names with no collector yet; they report as skipped rather than silently contributing nothing to an all-clear. Adding one means writing a `collect_<provider>` that returns `{(provider, account, resource): {day: cost}}` and adding it to `build_report`; the flatness rule is provider-agnostic.

Exit codes: 0 the check ran, with or without findings; 3 no provider could be queried. Exit 3 is deliberately not in the unit's `SuccessExitStatus`, so a monitor that cannot monitor shows up in `systemctl --user --failed` instead of logging a quiet success. `deploy.sh` only enables the timer where `~/.modal.toml` exists, so a box that has never used Modal does not get a daily failing unit.

## Four things the collector has to get right

Each of these was a real defect caught in review, and each has a test.

- **Key on the provider's object ID, never the description.** Eight of the twelve app names in the captured fixture map to more than one object, and `jlens-monitor-qwen36` maps to 36. Keyed on the name, a cheap ephemeral app overwrites a continuously billed GPU on every shared day and the flat run disappears into an all-clear.
- **Drop inherited `MODAL_TOKEN_ID` and `MODAL_TOKEN_SECRET` from each child.** They outrank `.modal.toml` (`modal/config.py:9`), and direnv exports them here, so leaving them in place would send every per-profile query to one workspace while labelling the results with a different profile name each time — the other workspaces silently unchecked behind a clean report.
- **Handle a failing profile per profile.** One revoked credential or timeout must not discard the profiles already collected, or the nudge sees a findings-free report. `checked` lists each account actually queried, so an all-clear states its own coverage.
- **A flat run must reach the latest billed day.** Otherwise a resource that stopped keeps being reported every day until it falls out of the lookback window. A whole series older than `CLOUD_SPEND_MAX_CUTOFF_LAG_DAYS` (default 2) is treated as history and reports nothing.

## The related process guard

`cwrm` refuses to remove a worktree that has live processes in it, and `cwclean` marks such a worktree `+procs` and keeps it. `--force` does **not** bypass this: that flag is about gitignored artifacts, which you discard deliberately, whereas orphaning a running process is the more expensive mistake. `--ignore-procs` is the explicit opt-out. In the incident the poller outlived its worktree by 16 days, still writing to a log in a directory that had been deleted and recreated around it.

## The deadline nudge catches it three layers earlier

`claude/hooks/nudge_undeadlined_poller.sh` fires before a Bash command that looks like a polling loop carrying no deadline — a `watchdog`/`keep-warm`/`keepalive` invocation, or a `while true` loop containing a `sleep`. It points at coreutils `timeout`, which already does the job; shipping another wrapper would only duplicate it.

The nudge is silent when the command is already bounded (`timeout`, `systemd-run`, `jexp`, an explicit `--max-age`/`--deadline`, or `--no-deadline` as the opt-out), and when the command merely reads, searches or kills something with one of those words in its name. It runs on **every** Bash call, so a false positive is expensive; `tests/test_nudge_undeadlined_poller.sh` pins 26 cases, 5 loud and 21 quiet, including the real command from the incident.

It also asks the question that actually mattered: **is the poll interval shorter than the idle timeout of the thing being polled?** At 180 s against a 300 s `scaledown_window` the watchdog was a keep-alive wearing a health check's name, and no deadline would have made that correct — only cheaper.

The three guards sit at different distances from the mistake. The nudge fires before the poller starts, `cwrm` refuses to orphan it, and `cloud-spend-check` catches the bill a few days later. The last of those is the backstop, not the fix.
