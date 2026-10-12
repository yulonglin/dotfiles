# runrec: every run leaves a record before it spends

`custom_bins/runrec` wraps an experiment launch. It writes the run directory, a launch record and one line in the repo's run index before the command starts; it refuses a Modal or RunPod launch with no cost cap, burn rate or idle limit; it stops the command when a cap trips; and it keeps one Markdown board per project current. Spec and the reasoning behind each rule: `artifacts/research-run-records/spec.md`.

## Launch

```
runrec launch --slug judge-pilot --backend local --api-cap 2 \
  --progress-path out/judge/verdicts.jsonl --expect-n 200 \
  -- python -m jspace_output.monitor --limit 200

runrec launch --slug capture-qwen --backend modal \
  --cost-cap 25 --rate 4.5 --max-idle 15m --timeout 6h --api-cap 0 \
  -- modal run modal_apps/capture_replay_modal.py
```

| Flag | Meaning |
|---|---|
| `--backend` | `local`, `modal` or `runpod`. A `local` launch whose command runs `modal` or `runpodctl` is refused as mislabelled |
| `--cost-cap`, `--rate` | Stop when rate (USD per hour, the total burn across containers) times wall-clock reaches the cap. Required for `modal` and `runpod` |
| `--max-idle` | Stop when the run's output has not grown for this long. Required for `modal` and `runpod`. With `--progress-path`, only that path counts; without it, anything the command writes into the run dir or prints |
| `--timeout` | Stop after this much wall-clock time |
| `--api-cap` | Required on every launch; `0` declares no paid LLM calls. Above 0 with `--api-provider openrouter`, the balance is read before launch and the launch refused when it is below the cap |
| `--api-enforce` | Also stop the run when the OpenRouter key's usage since launch reaches the cap. Off by default because the key is shared with other sessions, so that figure is an upper bound |
| `--expect-n`, `--progress-path` | The ETA denominator. Lines of a file, or entries of a directory, counted from launch, so a resumed `--run-dir` starts at 0 |
| `--run-dir` | Record into an existing directory the script already chose |
| `--config` | Snapshot a config file into `<run dir>/config/` with its sha256 |

Stopping sends SIGINT to the whole process group (which makes `modal run` stop its app), then SIGTERM, then SIGKILL, until the group is gone. Exit code: the command's own code; 2 when refused; 124 when stopped or interrupted.

The command sees `RUN_ID`, `RUN_DIR`, `RUN_COST_CAP_USD` and `RUN_API_CAP_USD` in its environment.

## Files

Under `<out-root>`, which is `<git toplevel>/out` unless `--out-root` or `RUNREC_OUT_ROOT` says otherwise:

- `runs.jsonl`: the index, one `launch` and one `finish` event per run, each a locked append.
- `<date>_<slug>/launch.json`: the live record, rewritten every heartbeat. Only `runrec` writes it.
- `<date>_<slug>/manifest.json`: gets a `launch` key merged in once the command has exited. `runrec` never writes it while the command runs, so a script that writes its own `manifest.json` cannot race it; every other key is left as the script wrote it.
- `<date>_<slug>/launch.log`: the command's stdout and stderr.
- `runrec.json`, optional: `{"project": "nla-vs-cot", "board": "~/vault/research/monitorability/docs/run-board.md"}`.

## Board

`runrec board` prints the page; `runrec board --write` writes it to the `board` path; `runrec ls` prints one line per run. With a `board` path configured, every live run rewrites the page on launch, every 5 minutes and at finish. A run whose heartbeat is three intervals old shows under **Lost**: its wrapper died, and the job may still be billing.

Nothing rewrites the page once the last wrapper is gone, so the page leads with its "as of" time. If it is older than 5 minutes and still lists running rows, run `runrec board --write` on the host.

## What it does not cover

- **Detached Modal apps.** `modal deploy` and `modal run --detach` are refused, because the app outlives the process `runrec` supervises.
- **RunPod pods.** `runrec` stops the command, not the pod; teardown must live inside the command, as the EXIT trap in a launch script does.
- **OpenAI and Anthropic credit.** Project keys cannot read billing, so the cap is only exported as `RUN_API_CAP_USD` for an in-process ledger to honour.
- **Real billing.** GPU cost is an estimate from the declared rate. `cloud-spend-check` remains the backstop that reads actual Modal billing.

## Pilot on hn, 2026-10-12

Total paid spend: \$0.03 of API and a few seconds of a quarter-CPU Modal container.

- **Real judge step.** A 2-call `jspace_output.monitor` run on the Agentic Misalignment rollouts (`--conditions cot_text --draws 1 --max-calls 2`) went through `runrec` with `--api-cap 2 --api-provider openai`. It succeeded, counted 2 of 2 verdicts as progress, and measured \$0.0306. Its free `--dry-run` went first, under `--api-cap 0`.
- **Modal stop.** A CPU-only Modal function that would run 10 minutes was launched with `--cost-cap 0.05 --rate 3.6`. `runrec` stopped it on cost after about 50 s, `modal run` aborted the app, and `modal app list` showed it `stopped` with 0 tasks.
- **Refusals on the real CLI.** A Modal launch without caps was refused, and so was a `scaledown_window=60` app under `--max-idle 30s`. The OpenRouter preflight read a real balance, admitted `--api-cap 2` and refused `--api-cap 100000`.
- **Failures are recorded too.** Three monitor dry runs on the 30 September ImpossibleBench inputs failed: the current monitor wants them rebuilt with `ib_rollouts`. They are in the index and on the board as `failed`.
- **Board.** `/workspace/projects/nla-vs-cot/out/runrec.json` points the board at `~/vault/research/monitorability/docs/run-board.md`, which the vault's continuous sync carries to the phone.
- **Tests.** `tests/test_runrec.py` passes on macOS (29, plus 1 Linux-only skip) and on hn (30).
