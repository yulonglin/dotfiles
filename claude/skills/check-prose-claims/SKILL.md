---
name: check-prose-claims
description: "Fact-check prose claims — stats, comparatives, quotes — in slides, reports and PDFs. Use on 'fact-check this deck', 'audit this PDF'."
---

# Check prose claims against authoritative sources

## When to invoke

- **Before any external publication** — papers, decks, blog posts, reports, talks carrying quantitative or attributed claims
- **After LLM-assisted drafting** — anything an LLM wrote that contains numbers, attributions or comparisons
- **When a claim smells off** — suspiciously clean comparatives ("3x faster"), confident attribution to a paper with no page reference
- User asks: "check the claims in this deck", "fact-check the report", "audit this PDF", "verify the numbers"
- **Doc-only mode** — "only use this document" / "verify against the PDF only" / "don't search the web"

Not this skill: BibTeX entry verification (`check-bib-references`), a single fact mid-conversation (just WebSearch — `~/.claude/rules/verify-before-instructing.md`), or editing for tone and clarity (writing skills).

## The failure mode this catches

Prose drift between source and claim. The bib entry can be correct and the cited paper real — but the sentence attached to the cite says something the paper doesn't.

| Failure | Example |
|---------|---------|
| **Wrong value** — paper says 12% gain, slide says 15% | Not rounding; a different number |
| **Wrong direction** — paper says X reduces Y, slide says X increases Y | Sign flip, pure hallucination |
| **Wrong comparator** — paper beats a baseline, slide claims it beats SOTA | Same effect size, bigger claim |
| **Missing context** — finding holds on subset A, slide drops the qualifier | "Best performance" when the paper says "best on the easy subset" |
| **Attributed to nobody** — "Studies show X", "According to research…" | Padding that verifies to nothing |
| **Causal inflation** — paper shows correlation, slide says "X causes Y" | See `~/.claude/rules/research-core.md` § Causal Claims |
| **Visual distortion** — truncated y-axis turns a 2% gap into a 40% one | Chart compels, source data is mundane |
| **Cherry-picked timeframe** — chart shows the spike, full series is flat | Misleading by omission |

## Two-pass architecture

**Never interleave extraction and verification.** Discovering new claims mid-verification breaks consistency.

```
Pass 1 (extract) → freeze list → user confirms → Pass 2 (verify in parallel) → report
```

**Pass 1 — extraction.** Read the whole document; for PDFs over 10 pages delegate to a subagent (`~/.claude/rules/delegation.md`). Extract every claim matching the IN taxonomy, with **no verification yet**. Output a numbered list and **present it to the user for confirmation** — this gate is where most of the skill's value lands, because the user spots missed and mistyped claims. Freeze the confirmed list to `out/claim-check-<UTC-timestamp>/claims.jsonl`.

**Pass 2 — verification.** Take Pass 1 output as fixed input, no re-extraction. Dispatch claims in parallel batches, apply the status decision tree to each, append to `results.jsonl` keyed by `claim_id`, and report grouped by status.

## Claim taxonomy

**Extract (IN):** statistics (any number with unit or context — "92.3% accuracy", "$4.7B market"), comparatives ("3x faster than baseline"), temporal assertions, attributions ("Smith et al. (2024) found…"), causal claims, existence claims ("500M users"), rankings ("largest", "first"), and direct quotes with an attributed author.

**Skip (OUT):** definitions, marked opinions ("we believe"), hypotheticals, questions, unsourced future predictions, methodology descriptions, acknowledgments.

**High-stakes override.** For papers, safety-critical reports and external talks, also extract three normally-OUT categories: methodology descriptions, because a wrong model name or hyperparameter is a reproducibility bug; the embedded statistic inside a hypothetical ("if adoption continues at 40%/yr…"), which is verifiable even when the conditional isn't; and the supporting data inside a marked opinion ("we believe X, given that 70% of users…"). The default OUT list is tuned for slide decks, so ask before extraction starts: **"Default mode (slide-deck) or high-stakes mode (paper/safety-critical)?"**

## Numerical precision: rounding is correct reporting, not an error

**Rounding and significant-figure reduction pass.** A claim is a finding only when it says something the source does not: a different value, a flipped direction, a wrong order of magnitude, or a genuine unit mismatch.

| Source | Claim | Status |
|--------|-------|--------|
| 96.555% | 96.555% | Verified |
| 96.555% | 96.6% | Verified (rounded) |
| 96.555% | 96.5% | Verified (truncated to 3 s.f.) |
| 96.555% | 97% | Verified (rounded) |
| 0.834 | 0.83 | Verified (2 s.f.) |
| 96.555% | "0.96555%" | Unit mismatch — the value is stated as a percentage but carries the fraction's digits |
| +12% growth | +15% growth | Hallucination (different value) |
| +12% growth | −12% growth | Hallucination (wrong direction) |
| $4.7B | $47B | Hallucination (order of magnitude) |

Two clarifications on the unit row. "0.96555" presented as a **fraction** of a source's 96.555% is Verified — same quantity, different unit. It is an error only when the unit label and the digits disagree, as in "0.96555%" or "96.555" captioned as a fraction. And an order-of-magnitude gap is never rounding: $4.7B → $5B is fine, $4.7B → $47B is not.

**Record the rounding anyway.** A Verified-rounded claim goes in the report with the source value beside it, so the author can see where precision was dropped and tighten it if the venue wants exact figures. That is a note, not a finding, and it does not count toward the issue total.

**Tightening the rule:** for a camera-ready paper or a regulatory filing the user may want exact digits enforced. Ask, and only then treat rounding as an error — the default never does.

## Status decision tree

```
Is this a CITATION claim (references a paper/report/source)?
├─ YES → CITATION VALIDATION
└─ NO  → STATISTIC/FACT VALIDATION

CITATION VALIDATION
├─ Cited source exists?
│   ├─ NO  → "Citation Not Found"
│   └─ YES → Source contains the claimed topic?
│             ├─ NO  → "Misquoted"
│             └─ YES → Source supports the claim?
│                       ├─ YES exact      → Verified (exact)
│                       ├─ YES paraphrase → Verified (paraphrase)
│                       ├─ PARTIAL        → Misleading (note missing context)
│                       └─ NO             → Hallucination (note what source says)

STATISTIC/FACT VALIDATION
├─ Authoritative source found?
│   ├─ NO  → "Unverified" (NOT "Hallucination" — absence ≠ contradiction)
│   └─ YES → Claimed value consistent with source (rounding and sigfigs OK)?
│             ├─ YES → Verified (note the source value if the claim rounds)
│             └─ NO  → Numerical Error (different value, direction, magnitude or unit)

DOC-ONLY MODE
└─ Claim traceable to provided source?
    ├─ YES → run normal validation against that source
    └─ NO  → "Not in Source" (likely external knowledge / training-data hallucination)
```

## Visual integrity

For every chart or table: extract every data point, axis label, unit, scale and legend; find the source for the underlying numbers; compare value by value; then check integrity.

| Check | Issue type |
|-------|------------|
| Y-axis starts at non-zero (bar chart) | Visual Distortion: axis manipulation |
| 3D effects distort proportions | Visual Distortion: 3D exaggeration |
| Missing error bars when the source has them | Misleading: uncertainty omitted |
| Different time range than the source | Misleading: cherry-picked timeframe |
| Colour or encoding implies an ordering the source doesn't support | Misleading: false ranking |
| Inset zoom without indication | Misleading: hidden truncation |

## Doc-only mode

Build a source index first (page → key facts, numbers, tables, figures). Pass 1 extraction proceeds normally; Pass 2 verifies **only against the index**, with no web search. Any claim that doesn't trace to the index is **Not in Source**, regardless of whether it happens to be true elsewhere.

This mode is what you want when auditing an LLM-generated summary of a specific document — the question is what *isn't* in the source, not what's true in general.

## Sources and search

Prefer, in order: primary source (original study, official report, raw data) → government or institutional (WHO, CDC, World Bank) → peer-reviewed → named industry report with methodology → reputable news citing a primary → secondary compilations. If only the last two turn up, the status is "Unverified — only secondary sources found".

Run **all** applicable queries per claim; don't stop at the first hit.

| Claim kind | Queries |
|---|---|
| Academic citation | `"<first author> <year> <first 3 title words>"`; `"<full title>" site:arxiv.org OR site:semanticscholar.org`; `doi:<DOI>` |
| Statistic | `"<number with unit> <topic> <year>"`; `"<topic> <year>" site:gov OR site:edu`; `"<topic> <number> original source"` |
| Company / product | `"<company> <topic> press release <year>"`; `site:<company-domain> "<topic>"`; `"<company> <claim> SEC filing"` |
| Health / medical | `"<topic>" site:who.int OR site:cdc.gov OR site:nih.gov`; `"<claim>" systematic review site:cochrane.org` |
| Government / policy | `"<policy name>" site:gov`; `"<statistic> official statistics <country>"` |

For claims carrying an arXiv ID, **don't WebSearch** — write the IDs to a throwaway bib and batch them:

```bash
cat > "$TMPDIR/claim-check.bib" <<'EOF'
@misc{c1, eprint = {2401.12345}, archivePrefix = {arXiv}}
EOF
uv run ~/.claude/skills/check-bib-references/check_bib.py "$TMPDIR/claim-check.bib"
```

The orchestrator generates this bib programmatically from `claims.jsonl`. Pre-resolving arXiv in main context saves roughly 60s of throttle per agent — never let agents hit arXiv individually.

**Tie-breakers.** Missing date → assume the most recent year available and flag "needs date". Conflicting sources → cite both, prefer the most recent authoritative, note the conflict. Nothing found after all queries → "Unverified", never "Hallucination". Ambiguous currency or units → flag "needs clarification". "Approximately"/"about" → verify the base number is within ±10%. Paywalled or non-English source → say so, and note the translation if you made one.

## Orchestration

For **more than 20 claims**, see [`orchestrator.md`](./orchestrator.md) — the batch runtime pattern covering parallel agents, persistent state, resumability and arXiv pre-resolution. Below 20, verify inline in the main session; the orchestration overhead exceeds the savings.

## Output format

```markdown
## Verification Report

**Mode:** [Search / Doc-Only] · **Document:** <filename> · **Generated:** <UTC timestamp>

| Metric | Count |
|--------|-------|
| Total claims extracted | N |
| Verified (incl. rounded) | … |
| Numerical Error | … |
| Hallucination | … |
| Misleading | … |
| Unverified | … |
| Citation Not Found | … |
| Not in Source (doc-only) | … |

**Overall:** [PASS / FAIL — N issues]
```

Then findings grouped by status: Verified (ID, claim, source, location, confidence — with the source value where the claim rounds), Numerical Errors (ID, claim, source value, claimed value, deviation, fix), Hallucinations (ID, claim, issue, what the source says), Unverified, Misleading (with the missing context), and Sources Consulted (ID, citation, type, URL, used for).

## Critical rules

1. **Two passes, never one.** Extract, freeze, then verify.
2. **Confirm extraction with the user** before Pass 2. They catch the missed claims.
3. **Rounding is not an error.** 97% for 96.555% verifies. Only a different value, direction, magnitude or unit mismatch is a finding.
4. **Absence ≠ contradiction.** No source found → "Unverified", not "Hallucination".
5. **Run all search queries** per claim, not just the first.
6. **Citations must be real** — anything with an arXiv, DOI or OpenReview ID goes to `check-bib-references/check_bib.py`.
7. **Check what sources actually say** — a real paper can still be misquoted.
8. **In doc-only mode, flag everything external**, even claims that happen to be true.
9. **Conservative when uncertain** — "Unverified" beats a false "Verified".
10. **Verify agent output on disk, not from agent status** — `classifyHandoffIfNeeded` returns false failures. Read `results.jsonl` to confirm.

## Cross-references

- `~/.claude/rules/delegation.md` — never delegate factual lookup to an agent without tools; delegate Pass 1 on long PDFs
- `~/.claude/rules/verify-before-instructing.md` — same epistemic standard, applied mid-conversation
- `~/.claude/rules/research-core.md` § Causal Claims Match Evidence — for the causal/correlational distinction
- `check-bib-references` — bib entry existence, titles, authors, arXiv IDs
