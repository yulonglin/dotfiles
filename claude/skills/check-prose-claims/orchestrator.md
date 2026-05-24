# Orchestration runtime for check-prose-claims

For documents with **>20 claims**. Below that threshold, verify inline in main session.

This file is the *runtime* counterpart to `SKILL.md`'s *protocol*. The protocol tells you what to check; this tells you how to dispatch the check across parallel agents without losing state.

For the orchestrator-mode framework itself (when to delegate, how to phrase agent prompts), see `core:orchestrate` — don't duplicate that here.

## Default batch profile

| Parameter | Value | Tune when |
|-----------|-------|-----------|
| Concurrent agents | 5 | Lower if rate-limited; raise to 8 if claims are simple WebSearch |
| Claims per agent | 6 | Lower if claims need deep cross-referencing |
| Claims per batch | 30 | = agents × claims/agent |
| Batches | `ceil(N / 30)` | Run sequentially; don't fan out batches in parallel |

Rationale: 5 agents × 6 claims keeps each agent context manageable (~6 WebFetch + WebSearch traces stays under 50k tokens) while saturating typical web-search concurrency limits.

## Persistent state layout

All under `out/claim-check-<UTC-timestamp>/`:

| File | Format | Lifecycle | Purpose |
|------|--------|-----------|---------|
| `claims.jsonl` | one JSON object per claim | Frozen after Pass 1 user-confirmation | Source of truth for what to verify |
| `results-batch<N>-agent<M>.jsonl` | one JSON object per result, keyed `claim_id` | Written once by one agent | Per-agent verification outcomes — never shared between agents (avoids append race) |
| `results.jsonl` | merged from all per-agent files | Rewritten by main after each batch | Source of truth queried for `completed_claim_ids` |
| `sources.jsonl` | one source per line, deduped | Read-only handoff to agents | Pre-resolved arXiv/DOI metadata, shared URL→content cache |
| `batch-state.json` | single JSON object | Rewritten after each batch | `{next_batch_idx, completed_claim_ids[], failed_claim_ids[]}` |
| `report.md` | rendered report | Generated at end (or on demand) | Final deliverable |

### Schema sketches

**claims.jsonl**
```json
{"claim_id": "C01", "text": "Model achieves 96.555% accuracy on ImageNet", "type": "Statistic", "location": "Slide 3, bullet 2", "cited_source": null, "arxiv_id": null}
{"claim_id": "C02", "text": "According to Chen et al. (2024), transformers scale linearly", "type": "Attribution", "location": "Slide 5, para 1", "cited_source": "Chen et al. 2024", "arxiv_id": "2401.12345"}
```

**results.jsonl**
```json
{"claim_id": "C01", "status": "Numerical Error", "source_value": "96.555%", "claimed_value": "96.555%", "deviation": "0", "source_url": "https://arxiv.org/abs/2401.12345", "source_loc": "Table 3, p.8", "confidence": "exact", "notes": ""}
```

**batch-state.json**
```json
{"next_batch_idx": 2, "completed_claim_ids": ["C01", "C02", "..."], "failed_claim_ids": ["C07"]}
```

## arXiv pre-resolution (do this in main context, once)

Before dispatching any agents:

1. Scan `claims.jsonl` for any `arxiv_id` field
2. Build a throwaway bib file with one `@misc{...}` entry per unique arXiv ID, then run:
   ```bash
   # In main context — one call, batched API, ~60s throttle avoided
   uv run ~/.claude/skills/check-bib-references/check_bib.py out/claim-check-<ts>/arxiv-ids.bib
   ```
   `check_bib.py` reads bib files (no `--arxiv-id` flag); see its `--help`. Internally it uses arXiv's `id_list=` batched API in a single request
3. Write resolved metadata to `sources.jsonl` keyed by arXiv ID
4. Each agent's prompt includes the pre-cached source blobs for its claims — agents do **not** hit arXiv themselves

Same applies for DOIs and OpenReview forum IDs (use `check-bib-references/check_bib.py` for OpenReview too — pass a bib with `@misc{k, note={https://openreview.net/forum?id=...}}` entries).

## Dispatch pattern

Per batch:

1. Pick next 30 unfinished claims from `claims.jsonl` minus `completed_claim_ids`
2. Split into 5 chunks of 6
3. Spawn 5 agents **in parallel** (single message with 5 Agent tool calls)
4. Each agent receives:
   - Its 6 claims (with pre-cached source blobs for any arXiv/DOI claims)
   - The status decision tree (copied verbatim from `SKILL.md`)
   - The numerical precision rules
   - Write instruction: **write results to its own dedicated file** `results-batch<N>-agent<M>.jsonl` (the orchestrator supplies the exact path per agent). One agent = one file. Never write to the shared `results.jsonl` — concurrent appends from non-atomic editors will overwrite each other and lose results
5. After all 5 return, **read each `results-batch<N>-agent<M>.jsonl` from disk** to verify completions — do not trust agent status (see "Failure handling" below). Then **concatenate the 5 per-agent files into `results.jsonl`** (append mode, in main context where there's only one writer)
6. Update `batch-state.json` with the union of `claim_id`s found across the per-agent files
7. Repeat

### Agent prompt skeleton

```
You are verifying 6 prose claims against authoritative sources.

INPUT CLAIMS (verify in order):
  <C13 ... C18 from claims.jsonl>

PRE-CACHED SOURCES (do not re-fetch):
  <relevant entries from sources.jsonl>

PROTOCOL:
  Apply the status decision tree (copied below).
  Apply numerical precision rules (copied below).
  Use WebSearch + WebFetch for claims without a pre-cached source.

OUTPUT:
  Write one JSON line per claim to <YOUR-OWN-FILE>:
    out/claim-check-<ts>/results-batch<N>-agent<M>.jsonl
  This file is yours alone — the orchestrator merges per-agent files
  in main context after you return. Do NOT touch `results.jsonl`.
  Schema: {claim_id, status, source_value, claimed_value, deviation,
           source_url, source_loc, confidence, notes}

CONSTRAINTS:
  Do not hit arXiv directly — use pre-cached blobs.
  If a claim needs more than 5 web queries, mark as "Unverified" with notes.
```

## Failure handling

| Signal | Action |
|--------|--------|
| Agent returns with `status: failed` | **Verify on disk first.** `classifyHandoffIfNeeded` bug returns false failures (see `~/.claude/rules/agents-and-delegation.md`). Read that agent's `results-batch<N>-agent<M>.jsonl` — if the claims are there, it succeeded |
| Agent crashes mid-batch | Re-dispatch only the missing `claim_id`s in the next batch |
| Single agent returns 0 verifications | Inspect the prompt — likely it failed to delegate to web search. See `~/.claude/rules/agents-and-delegation.md` § CLI Agent Delegation |
| **Batch failure rate >20%** | **Stop. Surface to user.** Don't burn the rest of the budget on a broken pipeline |
| Hit per-agent web-search quota | Reduce claims-per-agent to 3, raise concurrent agents if quota is per-agent not global |
| arXiv 429 (you ignored the pre-resolve advice) | Wait 60s; pre-resolve everything; retry |

## Resumability

To resume after interruption:

1. Read `batch-state.json` → know `completed_claim_ids`
2. Read `claims.jsonl` → know the full set
3. Diff → next batch starts at `len(completed) // 30`
4. Skip any claim in `completed_claim_ids`
5. Do **not** re-run completed claims even on flag changes — different verification runs go in a new timestamped directory

## When NOT to orchestrate

| Situation | Why inline is better |
|-----------|----------------------|
| <20 claims total | Setup overhead exceeds batch savings |
| Single-author document with all citations in one bib | One pass through `check_bib.py` covers most of it |
| User wants to triage results live (decide per-claim if it matters) | Orchestration produces a report at the end; live triage needs a conversation |
| Highly specialized domain (one source the user knows by heart) | User adds more value than a generalist search agent |

## Output convergence

After all batches complete:

1. Sort `results.jsonl` by `claim_id`
2. Group by `status` (Verified, Numerical Error, Hallucination, Misleading, Unverified, Citation Not Found, Not in Source)
3. Render `report.md` using the format in `SKILL.md` § Output format
4. Surface the summary table + the `Numerical Error` and `Hallucination` sections to user **first** — those are the actionable findings

## Files this runtime produces

```
out/claim-check-2026-05-23_14-30-00/
├── claims.jsonl          # Pass 1 output, frozen
├── sources.jsonl         # Pre-resolved arXiv/DOI/OpenReview metadata
├── results.jsonl         # Pass 2 output, append-only
├── batch-state.json      # Resumability
└── report.md             # Rendered verification report
```

Per `~/.claude/rules/workflow-defaults.md` § Auditability: someone arriving cold should open this directory and understand the audit without reading the transcript.
