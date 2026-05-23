---
name: check-prose-claims
description: Fact-check prose claims in slides, reports, PDFs, and papers — statistics, comparatives, attributions, causal claims, quotes. Two-pass extract-then-verify protocol with strict numerical precision and a doc-only mode. Use when the user asks to "check the claims in this deck", "fact-check this report", "audit this PDF", "verify the numbers in these slides", or before publishing/shipping any externally-facing document with quantitative claims. Complements `check-bib-references` (which handles BibTeX entries) — this skill handles the prose around them.
---

# Check prose claims against authoritative sources

## When to invoke

- **Before any external publication** — papers, slide decks, blog posts, reports, talks with quantitative or attributed claims
- **After LLM-assisted drafting** — anything Claude/Codex/another LLM wrote that contains numbers, attributions, or comparisons
- **When a claim smells off** — round numbers, suspiciously clean comparatives ("3x faster"), confident attributions to a paper without a page reference
- User asks: "check the claims in this deck", "fact-check the report", "audit this PDF", "verify the numbers", "are these statistics right?"
- **Doc-only audit mode** — user says "only use this document" / "verify against the PDF only" / "don't search the web". Everything must trace to provided source

## When NOT to use this skill

| Situation | Use instead |
|-----------|-------------|
| BibTeX entry verification (titles/authors/arXiv IDs) | `check-bib-references` |
| Code review / type-checking a script | `code:code-reviewer` |
| Verifying a single fact mid-conversation | `~/.claude/rules/verify-before-instructing.md` (just WebSearch in main context) |
| Editing for tone/style/clarity (not factual content) | Writing skills |
| "Does this paper exist?" (single bib entry) | `check-bib-references/check_bib.py --key <citekey>` |
| Drafting *new* claims (you have data, need to write the sentence) | Just write it, then run this skill on the draft |

## The failure mode this catches

Prose drift between source and claim. The bib entry can be correct and the cited paper real — but the sentence attached to the cite says something the paper doesn't.

| Failure | Example |
|---------|---------|
| **Wrong number** — paper says 96.555%, slide says 97% | Source rounded; deck is now technically wrong in academic mode |
| **Wrong direction** — paper says X reduces Y, slide says X increases Y | Sign flip — pure hallucination |
| **Wrong comparator** — paper compares against baseline, slide compares against SOTA | Same effect size, different (and bigger) claim |
| **Missing context** — paper finding holds for subset A, slide drops the qualifier | "Best performance" when paper says "best on the easy subset" |
| **Confidently attributed to nobody** — "Studies show X" / "According to research..." with no actual source | Padding that sounds authoritative but verifies to nothing |
| **Causal inflation** — paper shows correlation, slide says "X causes Y" | See `~/.claude/rules/research-integrity.md` § Causal Claims |
| **Visual distortion** — bar chart with truncated y-axis exaggerates a 2% gap to look like 40% | Chart looks compelling, source data is mundane |
| **Cherry-picked timeframe** — chart shows 2022-2024 spike, full series is flat with one anomaly | Misleading by omission |

## Two-pass architecture (the core protocol)

**Never interleave extraction and verification.** Discovering new claims mid-verification breaks consistency.

```
Pass 1 (extract) → freeze list → user confirms → Pass 2 (verify in parallel) → report
```

### Pass 1: extraction

1. Read the entire document (slides, PDF, report). For PDFs >10 pages, delegate to a subagent — see `~/.claude/rules/context-management.md`
2. Extract every claim matching the IN taxonomy below. **No verification yet.**
3. Output a numbered list and **present to user for confirmation** before moving on. The user often spots extraction errors (missed claims, mis-typed claims) at this gate
4. Freeze the list to `out/claim-check-<UTC-timestamp>/claims.jsonl`

### Pass 2: verification

1. Take Pass 1 output as fixed input — no re-extraction
2. Dispatch claims in parallel batches (see `orchestrator.md`)
3. Apply the status decision tree to each claim
4. Append results to `results.jsonl` keyed by `claim_id`
5. Generate report grouped by status

## Claim taxonomy

### EXTRACT (the IN list)

| Type | Pattern | Example |
|------|---------|---------|
| **Statistic** | Any number with unit/context (%, $, count, ratio, decimal) | "92.3% accuracy", "$4.7B market" |
| **Comparative** | X is [comparative] than Y | "3x faster than baseline" |
| **Temporal** | Time-bound assertion | "In 2024, adoption reached…" |
| **Attribution** | Claim tied to a source | "According to WHO…", "Smith et al. (2024) found…" |
| **Causal** | X causes / leads to / results in Y | "Fine-tuning on X reduces hallucination by Y%" |
| **Existence** | Asserts something exists or is true | "500M users", "the model supports tool use" |
| **Ranking** | Position claim | "largest", "first", "top 3" |
| **Quote** | Direct quotation attributed to a source | Anything in quote marks with an author |

### SKIP by default (the OUT list)

| Type | Example | Reason |
|------|---------|--------|
| Definitions | "Machine learning is a subset of AI" | Definitional, not factual |
| Marked opinions | "We believe…", "In our view…" | Explicitly subjective |
| Hypotheticals | "If adoption continues…" | Speculative |
| Questions | "What drives growth?" | Not an assertion |
| Future predictions without source | "Will reach $10B by 2030" | Unless citing a forecast |
| Methodology descriptions | "We used PyTorch 2.0" | Process, not factual claim |
| Acknowledgments | "Thanks to our collaborators" | Not verifiable |

### Override for high-stakes audits

For papers, safety-critical reports, and external talks, **also extract**:

| Normally OUT | Why extract anyway |
|--------------|--------------------|
| Methodology descriptions ("we used model X with hyperparameter Y") | Wrong model name or wrong hyperparameter is a reproducibility bug. Audit if the document will be published |
| Hypothetical presuppositions ("If adoption continues at current rates…") | The presupposed rate is a verifiable claim even if the conditional isn't. Extract the embedded statistic |
| Marked opinions backed by data ("We believe X, given that 70% of users…") | The supporting data inside the opinion is a Statistic — extract it, skip the opinion wrapper |

The default OUT list is tuned for slide decks. Ask the user before extraction starts: **"Default mode (slide-deck) or high-stakes mode (paper/safety-critical)?"**

## Numerical precision rules (academic standard)

**Default: strict. Exact numbers only.**

| Source | Claim | Status |
|--------|-------|--------|
| 96.555% | 96.555% | Verified |
| 96.555% | 97% | Numerical Error (rounding) |
| 96.555% | 96.6% | Numerical Error (rounding) |
| 96.555% | 96.5% | Numerical Error (truncation) |
| 0.834 | 0.83 | Numerical Error (sigfigs) |
| 96.555% | 0.96555 | Numerical Error (unit mismatch) |
| +12% growth | +15% growth | Hallucination (different value) |
| +12% growth | −12% growth | Hallucination (wrong direction) |
| $4.7B | $47B | Hallucination (order of magnitude) |

**Exception:** if the source itself rounds ("96.555% (approximately 97%)"), then "97%" verifies — cite the approximation.

**Loosening the rule:** if the user is checking a slide deck for a general audience, ask whether to permit 1-sigfig rounding. Default to strict; relax only on explicit request.

## Status decision tree

Apply to every claim. No shortcuts.

```
Is this a CITATION claim (references a paper/report/source)?
├─ YES → CITATION VALIDATION
└─ NO  → STATISTIC/FACT VALIDATION

CITATION VALIDATION
├─ Cited source exists?
│   ├─ NO  → "Citation Not Found"
│   └─ YES → Source contains the claimed topic?
│             ├─ NO  → "Misquoted"
│             └─ YES → Source supports the exact claim?
│                       ├─ YES exact     → Verified (exact)
│                       ├─ YES paraphrase → Verified (paraphrase)
│                       ├─ PARTIAL       → Misleading (note missing context)
│                       └─ NO            → Hallucination (note what source says)

STATISTIC/FACT VALIDATION
├─ Authoritative source found?
│   ├─ NO  → "Unverified" (NOT "Hallucination" — absence ≠ contradiction)
│   └─ YES → Values match exactly?
│             ├─ YES → Verified
│             └─ NO  → Numerical Error (record source value, claimed value, deviation)

DOC-ONLY MODE
└─ Claim traceable to provided source?
    ├─ YES → run normal validation against that source
    └─ NO  → "Not in Source" (likely external knowledge / training-data hallucination)
```

## Visual integrity checklist (charts, graphs, tables)

For every visual:

1. **Extract** every data point, axis label, unit, scale, legend
2. **Find source** for the underlying numbers
3. **Compare** value-by-value (one row per visual element)
4. **Check integrity**:

| Check | Issue type |
|-------|------------|
| Y-axis starts at non-zero (bar chart) | Visual Distortion: axis manipulation |
| 3D effects distort proportions | Visual Distortion: 3D exaggeration |
| Missing error bars when source has them | Misleading: uncertainty omitted |
| Different time range than source | Misleading: cherry-picked timeframe |
| Color/encoding suggests ordering source doesn't support | Misleading: false ranking |
| Inset zoom without indication | Misleading: hidden truncation |

## Doc-only mode

**Triggers:** "only use this document" / "don't search the web" / "verify against the PDF only" / "everything should be from the source"

In this mode:
1. Build a source index first (page → key facts/numbers/tables/figures)
2. Pass 1 extraction proceeds normally
3. Pass 2 verifies **only against the index** — no web search
4. Any claim that doesn't trace to the index → **Not in Source** (regardless of whether it's true elsewhere). Likely external knowledge or training-data leakage

This mode is essential when auditing an LLM-generated summary of a specific document — you want to know what *isn't* in the source, not what's true in general.

## Source authority hierarchy (search mode)

When multiple sources found, prefer in this order:

| Rank | Type | Examples |
|------|------|----------|
| 1 | Primary source | Original study, official report, raw data |
| 2 | Government/institutional | WHO, CDC, World Bank, national stats offices |
| 3 | Peer-reviewed | Nature, Science, IEEE, ACM proceedings |
| 4 | Named industry report | Gartner, McKinsey, Statista (with methodology) |
| 5 | Reputable news citing primary | NYT/Reuters citing original source |
| 6 | Secondary compilations | Wikipedia (check their sources) |

If only Rank 5–6 sources are found → status = "Unverified", note "only secondary sources found".

## Search templates

Run **all** applicable templates per claim — don't stop at the first hit.

### Academic citations
```
Q1: "<first author last name> <year> <first 3 words of title>"
Q2: "<full paper title>" site:semanticscholar.org OR site:arxiv.org
Q3: "doi:<DOI>"            (if DOI provided)
Q4: "arxiv:<arxiv_id>"     (if arXiv ID provided)
```

For arXiv-ID-bearing claims, **don't WebSearch — use `check-bib-references/check_bib.py`** (batched API, no rate-limit hassle):

```bash
uv run ~/.claude/skills/check-bib-references/check_bib.py --arxiv-id <id>
```

### Statistics (market size, usage, etc.)
```
Q1: "<exact number with unit> <topic> <year>"
Q2: "<topic> <year>" site:statista.com OR site:gartner.com OR site:mckinsey.com
Q3: "<topic> <year>" site:gov OR site:edu
Q4: "<topic> <number> original source"
```

### Company / product claims
```
Q1: "<company> <claim topic> press release <year>"
Q2: site:<company-domain> "<claim topic>"
Q3: "<company> <metric> official announcement"
Q4: "<company> <claim> SEC filing"   (public companies)
```

### Health / medical
```
Q1: "<topic>" site:who.int OR site:cdc.gov OR site:nih.gov
Q2: "<claim>" systematic review site:cochrane.org
Q3: "<claim>" meta-analysis pubmed
```

### Government / policy
```
Q1: "<policy/law name>" site:gov
Q2: "<statistic> official statistics <country>"
Q3: "<claim> <agency name> report"
```

## Tie-breaker rules

| Situation | Rule |
|-----------|------|
| Missing date on claim | Assume most recent year available; flag "needs date" |
| Conflicting sources | Most recent authoritative; cite both; note conflict |
| Source not found after all queries | "Unverified" (not "Hallucination") |
| Currency/unit conversion ambiguity | Flag "needs clarification: currency/units" |
| Same org, multiple reports | Use most recent; cite with date |
| Claim uses "approximately" / "about" | Verify base number is within ±10% of source |
| Source behind paywall | "Source behind paywall, unable to verify exact text" |
| Source in different language | Translate and verify; note translation |

## Integration with sibling skills

| Claim contains… | Use… |
|-----------------|------|
| arXiv ID, DOI, OpenReview forum ID | `check-bib-references/check_bib.py` (batched, rate-limit-aware) |
| Citation to a paper that has no ID in the bib | WebSearch → WebFetch the abstract — same as Pass 2 |
| Pure prose stat ("70% of users…") with no cite | WebSearch templates above |
| Visual chart | Vision pass first (extract values), then verify per template |
| Long PDF (>10 pages) | Delegate Pass 1 extraction to a subagent (`~/.claude/rules/context-management.md`) |

**Cross-references:**
- `~/.claude/rules/agents-and-delegation.md` § Factual Verification — never delegate factual lookup to an agent without tools
- `~/.claude/rules/verify-before-instructing.md` — verify before stating; same epistemic standard
- `~/.claude/rules/research-integrity.md` § Causal Claims Match Evidence — for causal/correlational distinctions

## Orchestration

For >20 claims, see [`orchestrator.md`](./orchestrator.md) for the batch runtime pattern (parallel agents, persistent state, resumability, arXiv pre-resolve).

For small batches (<20 claims), verify inline in the main session — orchestration overhead exceeds the savings.

## Output format

### Summary (always first)

```markdown
## Verification Report

**Mode:** [Search / Doc-Only]
**Document:** <filename>
**Generated:** <UTC timestamp>

### Summary
| Metric | Count |
|--------|-------|
| Total claims extracted | N |
| Verified | … |
| Numerical Error | … |
| Hallucination | … |
| Misleading | … |
| Unverified | … |
| Citation Not Found | … |
| Not in Source (doc-only) | … |

**Overall:** [PASS / FAIL — N issues]
```

### Findings (grouped by status)

```markdown
### Verified (N)
| ID | Claim | Source | Location | Confidence |

### Numerical Errors (N)
| ID | Claim | Source Value | Claimed Value | Deviation | Fix |

### Hallucinations (N)
| ID | Claim | Issue | Source Says |

### Unverified (N)
| ID | Claim | Issue |

### Misleading (N)
| ID | Claim | Issue | Missing Context |

### Sources Consulted
| ID | Citation | Type | URL | Used For |
```

## Critical rules

1. **Two passes, never one.** Extract first, freeze, then verify.
2. **Confirm extraction with the user** before Pass 2. They will catch missed claims.
3. **Exact numbers only** in default mode. 96.555% ≠ 97%.
4. **Absence ≠ contradiction.** No source found → "Unverified", not "Hallucination".
5. **Run ALL search templates** per claim, not just the first.
6. **Citations must be real** — for anything with an arXiv/DOI/OpenReview ID, defer to `check-bib-references/check_bib.py`.
7. **Check what sources actually say** — a real paper can still be misquoted.
8. **In doc-only mode, flag everything external** — even claims that happen to be true.
9. **Conservative when uncertain** — "Unverified" beats false "Verified".
10. **Verify agent output on disk, not from agent status** — `classifyHandoffIfNeeded` returns false failures. Read `results.jsonl` to confirm.

## Lessons from designing this

*Placeholder — fill in after first real audit.*

Initial notes (pre-use):
- arXiv pre-resolution in main context (batched) saves ~60s of throttle per agent. Don't let agents hit arXiv individually.
- The user-confirmation gate between Pass 1 and Pass 2 is where most of the value lands — extraction quality is what differentiates a useful audit from a noisy one.
- Two failure modes from the audit reference that probably hit us too: (a) discovering "new" claims mid-verification (handled by Pass 1 freeze), (b) accepting secondary sources without seeking primaries (handled by authority hierarchy).
- The "high-stakes override" of the OUT list is our addition — the reference is tuned for slide decks. For papers, methodology errors are real bugs.

## Files

- `SKILL.md` — this protocol
- `orchestrator.md` — batch-orchestration runtime pattern (only needed for >20 claims)

## Adapting to other repos

The skill is generic — point it at any document. For per-project use, drop `SKILL.md` + `orchestrator.md` into the repo's `.claude/skills/check-prose-claims/` if you want project-specific extensions (e.g., a custom IN list for a specific report format).
