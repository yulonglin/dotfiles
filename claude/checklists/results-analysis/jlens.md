# J-Lens Analysis

Analysing J-Lens as a **monitorable surface** — the `nla-vs-cot` line of work, where per-layer readouts are rendered into concept surfaces and shown to a monitor, then benchmarked head-to-head against CoT-only and action monitors. The generic evidence and review standards are in `../results-analysis.md`; this file is what those standards cannot say about this particular surface.

Drafted from the 2026-07-31 sweep and its specs — **verify against the current run before quoting any number here.** The live thread moved on to ImpossibleBench arms after that date.

## Name which of the three J-Lenses you mean

Three things share the name, and conflating them produces claims that are true of none of them.

- **The technique**: a Jacobian lens. Per-layer `J_ℓ` transports the residual `h_ℓ` into the final-layer basis, so `softmax(W_U · norm(J_ℓ h_ℓ))` scores tokens — which words the model is pushing toward at each layer and token position. Per-layer Jacobians chain (`J_ℓ = J_{ℓ+1} · M_ℓ`), and `J = I` degenerates to the logit lens. Lineage: *Verbalizable Representations Form a Global Workspace in Language Models* and the `anthropics/jacobian-lens` library.
- **The research use**: J-Lens readouts rendered as concept surfaces and given to a monitor, competing against CoT and action monitors on the same rollouts. This is the load-bearing sense in Yulong's work, and the one the numbers are about.
- **Adjacent tooling**: WeZZard's `jlens-qwen36` MLX visual debugger. A reference for the technique, not a component of the experiment.

On disk the runs are named `jlens_*`; some prose calls the same runs `il-`. Say which artefact a number came from rather than trusting either prefix.

## A catch is not a catch until it cites evidence

The headline failure mode of this surface is a monitor that scores well while seeing nothing. Report **evidencedTP/TP** — true positives whose monitor row cites real evidence (T1/T2) — beside every TPR, never below it, because the prompt's acknowledgment gate defaults to a positive verdict and those defaults land in the TP column looking identical to real catches.

The calibration case: the best cell (pos_50end, L42) reached CoT parity on g-mean, 0.802 against 0.798 — and was hollow. **9 of 115 evidenced TPs against CoT's 69 of 114**, with all 42 beyond-CoT catches unevidenced rule-defaults. Genuinely evidenced J-Lens-beyond-CoT signal was roughly 1–2 of 66 disagreement rollouts. A parity claim on the aggregate alone would have been wrong in the direction that matters.

So: state the g-mean, then immediately state what fraction of its true positives cite evidence. Any comparison against CoT that omits the evidenced fraction is not a comparison.

## The noise floor is set by seven negatives

TNR rests on **n=7 negatives**, so a single false alarm moves it by 0.143 and **any gap under roughly 0.06 is noise**. Say this wherever a TNR or a g-mean built on it is displayed, and never rank cells by differences the floor cannot resolve. The sweep is wide — layers (early/mid/hi/dist3/dist5 = [20, 27, 34, 42, 49]), positions (pos_1/pos_8/pos_50end/pos_197), phase splits, glossed against unglossed — and a wide sweep read against a coarse floor manufactures winners.

Report the null beside the metric: what g-mean does a monitor with no signal at all achieve on this label distribution, given the acknowledgment-gate default?

## Every cell sits far below the action monitor

The reference points belong on every plot. Action and full-transcript monitors reach roughly 0.99 g-mean; every J-Lens cell sits far below them. A J-Lens result presented against CoT alone, without the action-monitor ceiling on the same axis, reads as competitive when it is not.

## Ask whether elicitation collapses the signal

The surface is fragile to prompt changes in a way that matters for the conclusion. R3 cut `baseline_glossed` to 30 evidenced catches and `layers_early` to zero. Treat the monitor prompt as an independent variable with levels, not as a fixed harness, and report the arm that collapsed alongside the arm that worked.

## Say what the labels cannot see

Ground truth comes from a judge that sees **only the user message and the final answer** — no CoT, no tool calls. Every claim inherits that blindness: a rollout the judge scores as success may contain a visible failure in the trace it never read. State this where the labels are introduced, not in a caveats section at the end.

## Teacher-forced replay is not generation-time capture

Comparing a teacher-forced replay against genuine generation-time capture reports near-perfect agreement that means nothing. Check and state which one produced the readouts before comparing anything, and treat vLLM as the engine of record — the HF-transformers arm is rejected, so a mixed-engine comparison is a confound, not a robustness check.

## Reconcile the manifest before quoting usage

The sweep overwrites totals: one run reported **9,377,793 input tokens against 23,688,461 summed per-cell**. Sum the per-cell figures and compare against the manifest total before quoting either, and quote the reconciled number with the discrepancy named.

## Where the material lives

`~/projects/nla-vs-cot/HANDOFF.md` is the entry point and carries Yulong's five-question frame. Then `UPDATE-2026-07-31.md`; `out/2026-07-30_jlens-sweep-186/gmean_top3.md`; `out/2026-07-30_behavior-taxonomy/report.md`; `specs/2026-07-30-jlens-next-steps.md` (R1–R6); `specs/2026-07-30-analysis-backlog.md` (A0–A12). The rendering path is `monitorability-evals/nla_monitor/jlens_surfaces.py` — rank-aggregation of top-K over a frozen workspace band, word-like filtering, CJK glossing via `qwen_gloss.json.gz` — and the capture path is `modal_app_qwen36_jlens.py`, persisting `topk_ids`/`topk_scores` of shape `[n_pos, n_layers, K]`. Manifest schema: `docs/formats/run-manifest-v1.md`.
