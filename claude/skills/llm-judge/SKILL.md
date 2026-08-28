---
name: llm-judge
description: Build an LLM judge that scores text by meaning — intent, deception, tone — covering prompt design, blinding, fan-out, JSONL persistence.
---

# LLM Judges

Any classification of text by **meaning** — intent, awareness, deception, tone, whether a claim was acknowledged — uses an LLM judge, never a regex or keyword list. Regex is acceptable only for a literal token whose surface form is fixed and enumerable: a UUID, an exact error string, a flag name. Keyword matching silently misses paraphrase and silently over-counts quotation of the very string being searched for, and both errors point the same way as the hypothesis, so they read as signal.

## Shape of a judge run

**One API call per sample.** Never batch several samples into one prompt: it leaks context between samples, collapses per-sample rationales, and turns one parse failure into many lost rows. Fan out concurrently instead — an embarrassingly parallel loop.

**The judge must reason before it commits.** Every field emits `rationale` first, then the boolean or value. Any positive value MUST carry a verbatim `quote` from the input, with an explicit instruction not to infer what cannot be quoted.

**Fields that assert an absence cannot be quote-grounded** ("never acknowledges X"). The judge will substitute an irrelevant quote to satisfy the instruction. Either rewrite the field as a positive, or mark it as requiring separate hand-validation — do not treat its quote field as evidence.

**State the surface.** Record exactly what the judge saw: full transcript, CoT only, final answer only. A judge scoring a narrower surface than the monitors or humans it is compared against produces agreement numbers that do not mean what they appear to.

**Blind the judge.** No access to the labels it will be compared to, other judges' outputs, or the hypothesis under test. Labelling comes from experimental design, never from outcomes (`rules/research-core.md`).

## Persistence

Prompts live in versioned files, never inline string literals — one file per judge, with its `sha256` recorded in the run manifest so a reworded prompt is detectable after the fact.

Persist one append-only JSONL row per sample containing the sample key, the **rendered input actually sent**, the raw model output, parsed fields, model id, prompt sha256, timestamp, and attempt count. Append-only means the run is resumable and cacheable — re-running skips rows already present with `parse_ok`. Write a manifest with per-cell row counts, parse-failure counts, token usage, and the input-data sha256.

Report parse failures as a number, never silently drop them.
