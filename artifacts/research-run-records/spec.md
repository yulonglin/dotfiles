# Research Run Records

Every experiment launch writes a manifest and an index line before it spends, refuses a GPU launch with no cost cap or idle limit, and feeds one status-and-spend board per project. Tier 0 of the 2026-10-04 research-loop priorities; spec for the `runrec` MVP in this repo.

## Overview

The one live research loop stalled three ways that a tool can fix. Nobody could see what was running, for how long, or at what cost: "status?", "how long more" and "have we started any modal runs lately?" recur on hn from 12 to 30 September. Numbers could not be traced to a run: "what's the difference between 257 and 247?" on 30 September. And spend was unguarded: an idle Modal H100 burned \$3,060 over 31 days (the [watchdog post-mortem](https://claude.ai/artifact/Su5RQcCp6eQWNwHVVVyDkP)), and on 17 September a run stalled when its LLM account ran out of credit.

`runrec` is one stdlib-only Python command in `custom_bins/` that wraps a launch. It does three things, in delivery order:

1. **Run record.** It creates `out/<date>_<slug>/`, keeps a live `launch.json` there, merges a `launch` block into that directory's `manifest.json` when the run ends, and appends `launch` and `finish` events to one `out/runs.jsonl` per repo.
2. **Spend guard.** It refuses a Modal or RunPod launch that declares no cost cap, burn rate or idle limit, refuses every launch that declares no LLM API cap, checks the API balance before starting, and stops the run when its estimated cost, idle time or deadline is exceeded.
3. **Board.** `runrec board` folds the index into one Markdown page per project: what runs where, progress and ETA, cost so far against the cap. On hn it writes into the Obsidian vault, which syncs it to the phone with no Claude session in the loop. It is separate from the per-session debrief.

### Reused, not reinvented

A survey of hn on 2026-10-12 found these, and the design builds on each:

| Existing piece | Where | How `runrec` uses it |
|---|---|---|
| `run-manifest/1` contract (`additionalProperties: true`) | nla-vs-cot `docs/formats/run-manifest-v1.md`, branch `yulong/results-format-f1` | `runrec` owns one extra top-level key, `launch`, and never touches the keys the run's own script writes |
| `SpendLedger`, `project_cost`, `RateTable` | monitorability-evals `v2_rerun/spend_gate.py` | In-process LLM ceiling; `runrec` exports `RUN_API_CAP_USD` for it to read (follow-up PR in that repo) |
| Progress-watchdog design, tier 1 | vault `research/monitorability/docs/2026-09-17-progress-watchdog-design.md` | Idle means "the run's own output stopped growing", watched by mtime and size, never by polling an endpoint |
| `cloud-spend-check` (#176) | `custom_bins/cloud-spend-check` | Stays the after-the-fact backstop on real billing; `runrec` is the before-and-during guard |
| OpenRouter key endpoint | `claude/agents/llm-billing.py` | Reads the key's own ceiling and usage; the account balance comes from `/credits`, which `llm-billing.py` does not read |

Nothing existing records a run index, and nothing caps GPU dollars: the Modal apps set `timeout` and some set `scaledown_window`, but no launch path carries a dollar cap.

## Requirements

### R1. Every launch writes a manifest and an index line

- `runrec launch --slug S --backend {local,modal,runpod} [caps] [--config FILE]... -- CMD...` MUST create `<out-root>/<YYYY-MM-DD>_<slug>/` and refuse if it exists. `--run-dir` names an existing directory instead, for scripts that choose their own output path. `<out-root>` is `<git toplevel>/out`, or `--out-root`, or `RUNREC_OUT_ROOT`.
- While the command runs, the live record MUST live in `RUN_DIR/launch.json`, a file only `runrec` writes, rewritten atomically every heartbeat. `runrec` MUST NOT touch `manifest.json` until the command's process has exited, and then merge in one top-level key, `launch`, leaving every other key as the script wrote it. Existing scripts write their own `manifest.json` (15 of the 32 run directories in nla-vs-cot's `out/` have one, each written ad hoc) and none of them takes a lock, so any mid-run write by `runrec` could revert a script's update. A manifest `runrec` creates alone carries no top-level `schema_version`, since it cannot supply the `inputs` and `stages` that `run-manifest/1` requires.
- The `launch` object MUST hold: `schema` (`run-launch/1`), `run_id`, `slug`, `backend`, `argv`, `cwd`, `host`, `git_sha`, `git_dirty`, `config` (each `--config` file copied into the run directory, with its sha256), `caps` (cost cap, burn rate, max idle, timeout, API cap), `started_at`, `heartbeat_at`, `ended_at`, `status`, `exit_code`, `spend` (GPU estimate, API upper bound), and `progress` (done, expected).
- `status` takes one of: `running`, `succeeded`, `failed`, `stopped:cost`, `stopped:idle`, `stopped:timeout`, `stopped:api`, `interrupted`. The board adds `lost` for a `running` run whose heartbeat is older than three intervals, which is what a killed wrapper, an OOM kill or a host reboot leaves behind. A dropped ssh session sends SIGHUP, which `runrec` handles as `interrupted`.
- On Linux the command MUST die with the wrapper: it is started with `PR_SET_PDEATHSIG`, so a SIGKILLed `runrec` takes `modal run` with it, and `modal run` stops its app when it exits.
- `<out-root>/runs.jsonl` MUST receive one `launch` event at start and one `finish` event at end, each a single locked append. The index plus `launch.json`, not the manifest, is what the board reads.
- The child MUST receive `RUN_ID`, `RUN_DIR`, `RUN_COST_CAP_USD` and `RUN_API_CAP_USD`, and its stdout and stderr MUST be teed to `RUN_DIR/launch.log`.

### R2. A GPU launch without caps is refused, and a running one is stopped at its cap

- A `modal` or `runpod` launch MUST be refused unless it declares `--cost-cap USD`, `--rate USD_PER_HOUR` (the total burn, so N containers times the GPU rate) and `--max-idle DURATION`.
- Every launch MUST declare `--api-cap USD`; `0` declares that the run makes no paid LLM calls.
- A `local` launch whose command runs `modal` or `runpodctl` MUST be refused as mislabelled.
- `modal deploy` and `modal run --detach` MUST be refused, because the app outlives the process `runrec` supervises and no in-run stop can reach it.
- For a Modal launch, every `.py` file on the command line MUST be scanned: a `scaledown_window` larger than `--max-idle` refuses the launch, and a function with no `timeout=` draws a warning. This is the static form of the lesson from the \$3,060 incident.
- While running, `runrec` MUST stop the child's process group when any of these trips. Stopping means SIGINT, which makes `modal run` stop its app, then SIGTERM after 30 s, then SIGKILL after 10 s more.
  - **Cost:** burn rate times elapsed time reaches the cap. Labelled an estimate, since Modal billing lags by hours.
  - **Idle:** the run made no progress for `--max-idle`. With `--progress-path`, only that path counts, so a command that logs retries without finishing work still goes idle. Without it, anything the command writes into `RUN_DIR` or prints counts. `runrec`'s own files never count.
  - **Timeout:** `--timeout` has elapsed.
- A RunPod launch is bounded only as far as the wrapped command: `runrec` stops the process, not the pod. The pod's teardown must live inside the command, as the EXIT trap in `runpod/launch_rl.sh` does. The board says so on every RunPod row.

### R3. LLM credit is checked before launch and tracked during the run

- With `--api-cap` above 0 and `--api-provider openrouter`, `runrec` MUST read the remaining credit before launch and refuse if it is below the cap. Remaining credit is the smaller of the key's own `limit_remaining` (`GET /api/v1/key`) and the account balance (`GET /api/v1/credits`, which answers only for a management key, read from `OPENROUTER_MANAGEMENT_KEY` or the run key). That refusal is the fix for the 17 September stall, where the run started and only later found the account empty. When neither figure can be read, as for an unlimited key with no management key, the launch MUST be refused unless the operator passes `--api-unverified`.
- During the run it SHOULD poll the key's usage every 5 minutes and record usage since launch as `spend.api_usd_upper`. The key is shared with other sessions, so this is an upper bound. It warns at 80% of the cap and stops the run only under `--api-enforce`.
- **So in this MVP the API cap is a checked budget, not an enforced ceiling.** The preflight is a hard gate; the in-run figure is advisory, and even under `--api-enforce` a 5-minute poll lets in-flight calls overshoot. A hard ceiling needs either a dedicated OpenRouter key with a provider-enforced limit, which the preflight already honours, or `SpendLedger` reading `RUN_API_CAP_USD`, which is the follow-up in monitorability-evals.
- For `--api-provider openai`, the project keys in use cannot read billing, so `runrec` only exports `RUN_API_CAP_USD`. Enforcement is in-process through `SpendLedger`, and the board marks that cap "unverified".

### R4. One board per project shows what runs where, ETA and cost so far

- `runrec board` MUST print a Markdown page for one out-root with these parts:
  - a **Running** table: run, backend, host, started, elapsed, progress, ETA, GPU estimate against cap, API spend against cap, idle for, deadline;
  - a **Lost** table;
  - the last 20 finished runs with status, duration and cost;
  - spend over the last 7 days.
- ETA MUST come from a declared denominator: `--expect-n N` plus a progress file whose lines are counted. Without one the board shows the deadline and "no ETA", never a guess.
- Progress MUST count only what this run adds: the count at launch is recorded as a baseline and subtracted, so a resumed `--run-dir` does not credit old lines as new work.
- If `<out-root>/runrec.json` names a `board` path, `runrec` MUST rewrite that file atomically on launch, every 5 minutes while running, and at finish. For nla-vs-cot on hn that path is `~/vault/research/monitorability/docs/run-board.md`. hn's vault syncs bidirectionally (checked 2026-10-12), so the board reaches the phone.
- Nothing rewrites the board after the last wrapper dies, so the page MUST lead with its "as of" time and say that a page older than 5 minutes with running rows means a dead wrapper. A periodic `runrec board --write` on hn would close this; it is a follow-up.
- `runrec ls` SHOULD print the same running and recent rows as a terminal table.

### Deliberately out of scope

- Stopping detached Modal apps on breach (they are refused instead).
- A RunPod billing collector, and installing the `cloud-spend-check` timer on hn, which today runs nowhere there.
- Promoting `spend_gate.py` into a shared module, and the `RUN_API_CAP_USD` hook in its three callers. That is a follow-up PR in monitorability-evals.
- The stage-0 dataset-sanity gate, which is the next item in the tier.

## Acceptance Criteria

### Tests prove each refusal and each stop

`tests/test_runrec.py` runs the real script on free commands (`sleep`, `true`, a Python one-liner that writes files) and asserts:

- each refusal in R2 and R3 exits non-zero and creates no run directory;
- the cost, idle and timeout stops each end in the right `stopped:*` status, with the process group gone, including a background grandchild that ignores SIGINT;
- `runrec`'s own heartbeat writes do not reset the idle clock, and a command that logs without advancing its progress path still goes idle;
- a script that overwrites `manifest.json` mid-run keeps its own keys and gains `launch` at finish;
- a resumed `--run-dir` counts only new progress lines;
- an account with no credit refuses even when the key has headroom;
- four concurrent launches into one out-root produce exactly eight well-formed index lines;
- the board renders `lost` for a run with a stale heartbeat, and "no ETA" without a denominator.

### A two-sample real pilot stays under five dollars

On hn, with a combined worst case under \$5, estimated before launch:

- one 2-call run of a real monitorability-evals judge step (`jspace_output.monitor --max-calls 2`), launched through `runrec` into nla-vs-cot's `out/` with `--api-cap 2`, so that it appears on the phone-synced board;
- one Modal CPU function launched through `runrec` into a scratch out-root with a cost cap of a few cents, so that the cost stop really fires and `modal app list` shows the app stopped afterwards.

The pilot records its actual spend in the PR and in `docs/runrec.md`.

### Review is cross-family

The PR is reviewed by GPT-6.1 Sol through `model-router:adversarial-code-reviewer` before merge. It stays a draft unless that review is clean and the change is limited to the script, its tests and its doc.

GPT-6.1 Sol also reviewed this spec before the build, on 2026-10-12, and found six defects; this version carries the fixes. Mid-run manifest writes could revert a research script's own update, so the live record moved to `launch.json`. The API cap was described as enforced when it is advisory, so R3 now says so. The OpenRouter key endpoint reports a key ceiling, not account credit, so the preflight also reads `/credits`. The wrapper's own writes and log chatter could reset the idle clock, so idle now has a defined signal. A resumed run directory would credit old progress lines, so progress has a baseline. And a frozen board looks current after its last writer dies, so it leads with its age.
