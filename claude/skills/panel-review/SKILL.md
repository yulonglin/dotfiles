---
name: panel-review
description: Run a report, results page or artifact past a multi-family review panel (openrouter fusion, Fable, codex) and consolidate the critiques. Use for "panel review", "review this report with multiple models", "get several models to critique this", "multi-model review of my findings", before publishing a results page or spec that someone will act on.
---

# Panel Review

One reviewer tells you whether your argument survives one set of priors. A panel tells you which parts of it survive *disagreement* — and that is the output worth reading. Use this before publishing a results page, a spec, or any write-up someone will act on unattended.

Channel mechanics — how each family is reached, why non-Anthropic families cannot be subagents, keys, panel aliases, and capturing which model actually served a floating slug — live in `second-opinion`. Read it first; this skill does not restate any of it. What is here is the workflow around those channels.

Do not run this on a draft you are still restructuring. The panel critiques what is written, so it earns its cost once the claims are final and only their soundness is in question.

## Step 1 — Get the target into plain text

Every channel is amnesiac and none can open a URL or an artifact. Convert first.

| Target | Command |
|---|---|
| Artifact URL | Artifact tool, `action: "read"` with that `url` — owned artifacts return raw HTML, saved to a local file when large — then `any2md <that file>` |
| Local `.html` | `any2md /abs/path/page.html` |
| Local `.md` | Use as-is |
| Results JSON / CSV | Paste the rows verbatim into the brief; never summarise numbers you want critiqued |

Markup is noise the panel will spend tokens on, so strip it. Check the converted text still carries the tables and the numbers — a stripped page that lost its results table sends the panel a brief with no evidence in it.

## Step 2 — Write one self-contained brief

**Brief completeness is the main quality lever.** A panel model given a gap fills it confidently and invents a method you did not use, then critiques the invention. Every omission becomes a fabricated finding you have to triage away.

Write to `$TMPDIR/panel-brief.md`:

```markdown
## What this is
One paragraph: the system, the experiment, who acts on the result.

## The claims, verbatim
The headline sentences exactly as written in the report.

## The numbers
Each estimate with its interval, what the interval covers, and the null
beside it. Denominators as counts. Chance and degenerate values.

## Method, in two lines
Arms, what is held constant, what varies, unit of analysis.

## The decision riding on this
What happens differently depending on whether the claim holds.

## Known limitations
The ones you have already identified — so the panel spends its budget
past them rather than rediscovering them.

## What I want critiqued
Specific questions. "Is the null the right null for this metric?" beats
"any thoughts?".
```

## Step 3 — Fan out, in parallel, from main context

Dispatch all three in **one message**. Never nest these inside a subagent — a subagent cannot own work that outlives its turn, and the Monitor route is not available to it.

| Reviewer | Invocation | Covers |
|---|---|---|
| Multi-family panel | `with-secrets OPENROUTER_API_KEY -- openrouter-cli fusion "$(cat $TMPDIR/panel-brief.md)"` | Seven families in parallel, one judge synthesis; returns consensus, contradictions and unique insights per member |
| Fable subagent | Agent tool, `model: "fable"`, brief pasted in full | Research taste, whether the question is worth asking, whether the design answers it |
| codex-companion | Monitor tool, `adversarial-review` | Only when a diff or analysis code is in scope — the panel reads prose, codex reads the implementation |

`fusion` is one call, not seven, and it **fails closed**: if a panel member drops out it refuses rather than presenting a collapsed panel as corroboration. If it refuses, report the degraded panel and stop; do not retry around it with `--panel` trimmed to whoever answered.

## Step 4 — Consolidate into four buckets

De-duplicate first: three families raising the same point is one finding with three names on it, not three findings.

| Bucket | What goes in it |
|---|---|
| (a) Factual / statistical errors | A number, a test, or a claim about the data that is wrong |
| (b) Overclaims and missing nulls | Causal verbs the design does not support; a rate with no null or ceiling beside it; an interval that omits a known source of variation |
| (c) Presentation and clarity | Headings that are topics not claims, numbers in prose that should be a figure, undefined jargon |
| **(d) Disagreements between panel members** | Where reviewers reached opposite conclusions on the same passage |

**(d) is the highest-signal bucket and must never be averaged away.** Report both positions and which reviewer held each, then adjudicate against the data yourself. A synthesis that resolves a contradiction into a middle position has destroyed the finding.

Two rules that survive every panel:

- **Agreement is weak evidence, not strong.** These models share most of their training data, so a unanimous panel may be one prior wearing seven labels. Weight a contradiction above a consensus, and never quote "all seven agreed" as corroboration.
- **The panel never adjudicates data.** It critiques reasoning, framing and presentation. A measured number from the repo beats the panel's aggregate opinion every time — if a reviewer disputes a number, re-derive it from the source, and if the source holds, the finding is declined.

## Step 5 — Triage, with a reason for every decline

| Tier | Meaning |
|---|---|
| Must-fix | Bucket (a) or (b), or anything that changes what a reader would do |
| Should-fix | Real but not load-bearing; fix if the rewrite is cheap |
| Noted and declined | **Requires a stated reason** — wrong about the data, out of scope, or a cost the finding does not justify |

Every row names the reviewer that raised it, so a later reader can tell a seven-family consensus from one model's idiosyncrasy. Capture the resolved model ids from the call log at the same time (`second-opinion`), because the floating aliases will have moved by the time anyone asks who said what.

## Related

- `second-opinion` — channel choice, aliases, keys, provenance. Read before this.
- `check-misreads` — how the draft could be *misread*, which is a different pass; run it after the panel's substantive findings are fixed.
- `results-artifact` — the intervals, nulls and ceilings the panel will be checking against.
