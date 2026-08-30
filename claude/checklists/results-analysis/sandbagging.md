# Sandbagging Analysis

Analysing black-box sandbagging detection — the C³ line of work (*Same Question, Different Lies: Cross-Context Consistency for Black-Box Sandbagging Detection*, ICML 2026) and its extension to research sabotage, where **verifiability is the axis making sandbagging and sabotage one spectrum**. The generic evidence and review standards are in `../results-analysis.md`; this file is what those cannot say about this detection problem.

Two sources fed this file and they disagreed in places — the repo and its code paths won over the write-ups. Where a claim is disputed it is marked as disputed rather than averaged. Verify against the current run before quoting any number.

## An organism is a prompt *and* a model, and neither alone

Organisms here are **prompted, not trained**. Three families: **instructed** ("get X% wrong"), **discovered-incentive** (the model reads a document implying underperformance serves it), and **password-locked** (trained elsewhere, prompted here). Name which one produced every number — they are not interchangeable and detection rates differ by threat model, not by detector quality.

**Incentives do not transfer across models.** One prompt moved accuracy by 0.0pp on one model and 41.0pp on another, so a prompt validated on one model is an untested prompt on the next. Report the pair, never the prompt alone.

**Prompt format is an independent variable whether or not you meant it to be.** Legacy XML `<tool_call>` against native tool calls costs 23–30pp of accuracy from format alone. Record which format every run used; an unlogged format change is a confound large enough to be the whole effect.

**Inoculation is one sentence away.** A single prefilled sentence naming the behaviour suppressed it — mean gap 17.3pp down to 0.6pp. Any unlogged prompt edit can silently remove the thing you are measuring, so diff the rendered prompt between runs before comparing them.

**Instructed sandbagging is neither obeyed nor calibrated.** Told to score 0% correct, gpt-5-nano scored 51.1% on 4-option GPQA. Do not assume the instruction set the level; measure it.

## The out-of-context design, and why a tiny finetune is not a clean one

The generative design for this area is Owain Evans' train-on-A, test-for-implied-but-never-stated-B: finetune on a narrow behaviour, then probe for out-of-context generalisation — here, **finetune a model on descriptions of an eval and test whether it sandbags without ever being told to**. The generic version of the template lives in `../research.md`; this is its sandbagging instance.

The confound rule for narrow finetunes — why a small surgical set makes the causal story *less* clean, and the control that answers it — is generic and lives in `../research.md`. The sandbagging-specific version of the competing explanation is **verbalised eval awareness**: a model that has read descriptions of an eval may be recognising the eval rather than choosing to underperform, and those two produce the same accuracy drop. Separate them before claiming intent.

## Three nulls, in increasing strength — the third is the one that bites

State which null a number is being read against, because they disagree by a wide margin:

- **Chance**: 0.05 recall at a 5% FPR budget.
- **k=1**: the same pipeline without multi-sample aggregation. Measured on ProtocolQA: C³ 0.136, trusted monitoring 0.318. This is the null that separates the detector from the aggregation.
- **Behaviour-free / scaffold**: a predictor seeing only token counts, lengths and turn structure. On one sabotage substrate it reached **AUROC 1.000** — the "detection" was reading an instruction to be terse. A detector that does not beat this null has not been shown to read behaviour at all.

**The ceiling for organism strength is the task floor, not zero**: 25% on 4-option MCQ. A sandbagging arm sitting at 51% is above the floor, not at it, and describing it as "near-total sandbagging" misstates the range.

## Achieved FPR belongs beside every recall

**"Recall at 5% FPR" names the nominal calibration target, not the realised operating point.** Where no artefact records the achieved *test* FPR, that recall is not verified to sit at 5%, and two such numbers cannot be assumed to be compared at a matched operating point. The repo marks these in source with a `% SCRUB(fpr)` comment — a convention worth keeping, because it makes an unverified operating point greppable rather than forgotten.

A threshold calibrated on dev does not transfer to test, and **headline recall and FPR transfer are close to mutually exclusive**: one C³ variant reached 100% GPQA recall by flagging **84.8% of a strong honest model**. A recall figure without its achieved FPR is not a detection result.

Calibrate on the 40% dev split, report on the 60% test split, never the same rows. **Assert split disjointness in the landed logs, not in the loader** — an unseeded load-time shuffle once made ProtocolQA dev and test overlap rather than partition, which the loader could not have caught.

**Distinguish the two k's**, which are routinely confused: **K** is continuations per problem; **k** is items aggregated per classification decision (convention k=10). Compared methods must share k, or the comparison measures aggregation power rather than detectors.

**Thin negative groups break the ratio.** At k=10 a 65-negative test set yields **six** negative groups, so an achieved FPR at k=10 cannot honestly be quoted as a ratio.

## Two quantities are both labelled "SE" and only one is one

Check which pipeline produced an interval before quoting it — the distinction is the whole rule, and a blanket "the SEMs are broken" is as wrong as trusting them all.

- **Figure pipeline**: the standard deviation of 1000 bootstrap recall values, each iteration resampling *questions* and re-deriving the k=10 aggregates. This **is** a genuine standard error with respect to question sampling. Sound, and quotable as-is — no further division by √n.
- **Split-mode `sem_recall`**: the standard deviation of 1000 per-iteration Bernoulli flag/no-flag outcomes under a **fixed** threshold — that is `sqrt(p(1-p))`, a deterministic function of the point estimate and not a standard error at all. An interval built from it degenerates toward `[0, 1]`, and 39% of the split-mode intervals on disk are literally that. Not quotable.

**Where the degenerate quantity was the only interval available, report the point estimate alone and say so.** Printing an interval you know is meaningless is worse than printing none: it presents no-information as rigour. (Source: `d6-technical-report.tex:257`; the classifier is `src/detection_game/classifiers/run_multisample_bootstrap_cv.py`.)

## An interval names its omissions *and* which way they bias

"Names what it covers" is not enough — say the direction. The intervals here omit **question-level clustering** (rows are roughly five to six paraphrases of one question, resampled as if independent), **threshold-estimation noise** (the dev threshold is held fixed across iterations), and **sampling over the set of sandbagging prompts**. All three push the same way: the stated intervals are **narrower than the true uncertainty**. Say that where the number is displayed, so a reader cannot mistake a narrow interval for a precise one.

## Labels come from the trajectory file, never from the score

Assigning a condition label from the quantity being measured — matching `eval_id` to a narrative by mean monitor score — makes any resulting correlation **unfalsifiable, because it is forced by construction**. The label must come from experimental design: which trajectory file produced the sample. This is the circularity rule from `~/.claude/rules/research-core.md` in its most tempting local form.

## Accuracy gates score the wrong surface

**110 of 140 traces that state a deliberate error still land on the correct answer — 78.6%.** The model sandbags its reasoning and keeps the answer, so an accuracy-gated organism screen misses the behaviour entirely. Screen on the reasoning, not the final answer.

Relatedly, **the scorer reads the last assistant message**. An explanation follow-up becomes that message and the scorer grades the explanation rather than the answer — once reporting 13% where the true figure was 69%. Check what the scorer actually consumed before believing a surprising accuracy.

## Run the honest-wrong control

Run the detector on honest models' *incorrect* answers. If it fires at a comparable rate it is an error detector wearing a sandbagging label — inconsistency across paraphrases is exactly what a model that does not know the answer also produces. Report this arm beside the headline, not in the caveats.

## The cross-capability headline is disputed, not settled

The widely-quoted row — GPQA 100%, MATH 94%, USACO 67–75% at k=10 — has its figures **hardcoded in the generator**, and a reconstruction gave **40.9% for GPQA**. Treat it as disputed and do not repeat it as a result until it reproduces from data.

The matched GPQA k=10 numbers that do come from the pipeline are in `out/gpqa_report/gpqa_results.md`: C³ categorical 53.3%, C³ embedding 31.2%, trusted monitoring 75.5%.

## Adversarial collapse is the norm, not the exception

Detection rates measured against a non-adaptive model organism are an upper bound, not a result — and the collapses are total rather than marginal. The **lie detector falls from roughly 89% to 2%** once the model-identity confound it depends on is removed. **Behavioural probes fall from 74% to 3.4%** under a single stealth instruction. Report the adaptive arm beside the static one, and treat a detector nobody has attacked as untested rather than robust.

## No method dominates, so report the complementarity

The detectors fail on disjoint sets, so a single headline hides the structure that matters. **Deterministic error recipes — off-by-one, loop boundary, sign flip — evade C³ at 4.7–18%, while trusted monitoring catches those same cases at 57.6% through chain-of-thought leakage; C³ in turn reaches 95% on blatant patterns.** Report the per-threat-model breakdown rather than an average across them, and say which method covers what the other misses. An ensemble claim needs the same-component-twice null from `../results-analysis.md` before it means anything.

## What each detector actually computes

**C³** paraphrases a question N ways and scores dispersion — `categorical_entropy` for multiple choice, `mean_pairwise_cosine_distance` over embeddings for free-form. **Trusted monitoring** has a deliberately *weaker* model read the transcript and emit a suspicion score. Also in play: the Pacchiardi lie detector (follow-up probes) and behavioural probes. Metrics live in `src/detection_game/scorers/metrics.py` — primary recall@5%FPR, pAUC<0.05 McClish-standardized (**0.5 random, 1.0 perfect** — state both endpoints, since a reader assuming a zero baseline misreads every value), AUROC secondary.

## Where the material lives

The ProtocolQA rerun naming every model, dataset and prompt, with both detectors against their k=1 nulls: [artifact `f0038b34`](https://claude.ai/code/artifact/f0038b34-532a-422a-9544-6b98008bb854). Then `src/detection_game/scorers/metrics.py`, `src/detection_game/classifiers/run_multisample_bootstrap_cv.py`, `out/gpqa_report/gpqa_results.md`, and `ARTIFACTS.md` at that repo's root. The prompt library is `docs/sandbagging-prompts-compendium.md`, drawing on van der Weij et al. [arXiv:2406.07358](https://arxiv.org/abs/2406.07358), UK AISI auditing games, Apollo scheming evals, Alignment Faking and Sleeper Agents.

The stack runs on **Inspect AI**, so the silent failure modes in the `inspect-ai-evals` skill — `max_samples`, `max_connections`, `stop_reason` — apply to every run. Model-organism work of this kind is evaluation methodology, not deployment; the framing and its red lines are in `~/.claude/CLAUDE.md` under AI Safety Research Context.

**Not established**: whether any of this transfers to the monitoring or J-Lens checklists, and the recipe behind the paper's per-narrative trusted-monitoring column.
