---
name: council
description: Put a question to the standing multi-family LLM council (8 seats, one per lab, chaired by Fable 5) and consolidate the answers. Use for "ask the council", "llm council", "panel review", "review this report with multiple models", "get several models to critique this", "what would other models say", before publishing a results page or spec someone will act on.
---

# The LLM Council

Eight models, one per lab family, answer the same question independently. A chair then synthesises them — and with `--rank`, each member first ranks the others' answers blind. The output worth reading is not the consensus; it is **which parts of your argument survive disagreement**.

One question at a time, one command:

```
with-secrets OPENROUTER_API_KEY -- openrouter-cli council ask "<self-contained brief>"
```

## The roster is picked by index, not by hand

`config/openrouter-models.toml` is the single place any of this is configured — seats, chair, price cap, review cadence. Nothing else names a model.

Seats are chosen automatically from the Epoch Capabilities Index (and Artificial Analysis when `AA_API_KEY` is set): the highest-scoring model per family whose output price is under the cap, preferring a newer sibling in the same product line when the index has not scored it yet. Run `openrouter-cli council roster` to see who is seated and `--check` to compare against a fresh pick.

**Do not hand-edit the seats block.** It sits between `# BEGIN council-auto` / `# END council-auto` markers and a refresh overwrites it. Change the *rule* instead — `families`, `max_output_price` — or the chair, which is hand-picked.

A seat whose `basis` is `newest-in-line` is seated on **recency alone**; no index has scored it. Say so if you quote the roster as evidence of capability.

## Two modes, and what each one actually is

| Mode | What runs | Calls |
|---|---|---|
| default | One OpenRouter `fusion` call: the panel answers server-side in parallel, an analyst returns consensus, contradictions, unique insights and blind spots, the chair writes the answer | 9 |
| `--rank` | Eight answers gathered directly, then **every member ranks the others blind**, then the chair synthesises with the Borda tally | 17 |

**Fusion has no peer-ranking stage** — panel models never see each other's answers, and OpenRouter ships no "council" product (checked 2026-09-01: Labs offers Fusion, Cost Simulator and Spawn). `--rank` is the part built here, and it is the only way to learn which answer the *other models* found strongest.

Reach for `--rank` when the answers will disagree and you need to know who is persuasive to peers rather than to you — a contested design call, a result you are about to publish. Skip it for a straightforward question; it roughly doubles the cost for a signal you will not use.

`--dry-run` prints the plan, the call count and a priced estimate before spending. A short question costs about **$0.34** in default mode and **$0.60** with `--rank`; a long brief with `--context` files costs more, and the dry run is how you find out which.

## Both modes fail closed

A council that quietly lost three members is worse than no council, because it still looks like corroboration. Default mode inherits fusion's integrity check; `--rank` refuses outright if any seat returns no answer. **If it refuses, report the degraded panel and stop** — do not retry with `--panel` trimmed to whoever answered, which converts a failure into a fabricated consensus.

## Brief completeness is the main quality lever

Every seat is amnesiac. None can see your conversation, open a URL, or read an artifact. A model given a gap fills it confidently, invents a method you did not use, and critiques the invention — so every omission becomes a fabricated finding you then have to triage away.

Convert the target to plain text first: an Artifact via the Artifact tool's `read` then `any2md`; a local `.html` via `any2md`; results JSON or CSV pasted verbatim, never summarised — numbers you summarise are numbers nobody can check.

Write the brief to a file and pass it in:

```markdown
## What this is
The system, the experiment, who acts on the result.

## The claims, verbatim
The headline sentences exactly as written.

## The numbers
Each estimate with its interval, what the interval covers, and the null
beside it. Denominators as counts.

## Method, in two lines
Arms, what is held constant, what varies, unit of analysis.

## The decision riding on this
What changes depending on whether the claim holds.

## Known limitations
The ones you already know — so the panel spends its budget past them.

## What I want critiqued
"Is the null right for this metric?" beats "any thoughts?".
```

## Code goes in with `--context`, agentic loops do not

`--context <path>` inlines a file into the brief, repeatable, so all eight families see the same code. That is the right tool for "review this diff", "is this design sound", "what breaks here".

It is **not** an agentic loop: no seat can run the tests, grep the repo, or iterate. When the question genuinely needs that, the council is the wrong instrument — use `codex-companion` for GPT or `opencode run -m openrouter/<slug>` for the others, both covered in `second-opinion`. Do not fake it by pasting a whole repository.

## Reading the result

De-duplicate first: three families raising one point is **one finding with three names on it**, not three findings.

| Bucket | What goes in it |
|---|---|
| (a) Factual / statistical errors | A number, a test, or a claim about the data that is wrong |
| (b) Overclaims and missing nulls | Causal verbs the design does not support; a rate with no null or ceiling; an interval omitting a known source of variation |
| (c) Presentation and clarity | Topic headings that should be claims, numbers in prose that should be a figure, undefined jargon |
| **(d) Disagreements between members** | Where seats reached opposite conclusions on the same passage |

**(d) is the highest-signal bucket and must never be averaged away.** Report both positions and who held each, then adjudicate against the data yourself. A synthesis that resolves a contradiction into a middle position has destroyed the finding — which is why the chair is instructed not to, and why you should check that it did not.

Two rules that survive every council:

- **Agreement is weak evidence, not strong.** These models share most of their training data, so a unanimous panel may be one prior wearing eight labels. Weight a contradiction above a consensus, and never quote "all eight agreed" as corroboration.
- **The council never adjudicates data.** It critiques reasoning, framing and presentation. A measured number from the repo beats the panel's aggregate opinion every time; if a seat disputes a number, re-derive it from the source, and if the source holds, the finding is declined.

Triage every finding as must-fix (bucket a or b, or anything that changes what a reader would do), should-fix, or **noted and declined with a stated reason**. Name the seat that raised each one, so a later reader can tell an eight-family consensus from one model's idiosyncrasy.

## The chair grades its own answer

Fable 5 chairs while holding the anthropic seat. The blind ranking already excludes a ranker's own answer from its ballot, so the self-preference is confined to the synthesis step — but it is real. **Where the synthesis favours the anthropic seat's contribution, discount it or read that answer yourself.** `--show-answers` prints every seat's raw answer before the synthesis, which is the cheap way to check.

## Keys, and why the council cannot be subagents

`council ask` spends money and needs `OPENROUTER_API_KEY`. Secrets here are per-project, never global: `setup-envrc` for a repo, or `with-secrets OPENROUTER_API_KEY -- ...` for one shot. `roster` and `refresh` need no key at all — both data sources are public.

Non-Anthropic models **cannot** be reached through subagents: an agent's frontmatter `model:` resolves only against api.anthropic.com, so a non-Anthropic name there either hard-fails or answers from Claude wearing another family's label — a panel that is secretly one model agreeing with itself. `second-opinion` has the full reasoning. The CLI is the only sanctioned route.

## Staleness is handled for you

A fortnightly timer (`council-roster.timer`) compares the roster against the indices and writes `~/.local/state/council-roster/roster-report.txt`. When the roster goes past `review_days`, a session-start nudge says so and asks for `council refresh --apply` plus a commit. The timer never edits the config — it runs `ProtectHome=read-only`, and an automated edit to a tracked file leaves uncommitted drift nobody notices.

Attribution is required by the data licences wherever these scores appear: **Epoch AI** (CC-BY) and **artificialanalysis.ai**.

## Related

- `second-opinion` — one family rather than eight, plus codex-companion, OpenCode and the key rules
- `advisor` — the only channel that already has the conversation; no brief needed
- `check-misreads` — how a draft could be *misread*, a different pass; run it after the council's substantive findings are fixed
- `results-artifact` — the intervals, nulls and ceilings the council will be checking against
- `config/openrouter-models.toml` — the single place: seats, chair, cap, cadence
