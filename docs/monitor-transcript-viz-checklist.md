# Monitor / Judge Transcript Visualization Checklist

Reference checklist for building or evaluating a tool that reads model transcripts and displays
LLM-judge or monitor verdicts on them (safety monitors, deception judges, eval scorers — anything
where you read a rollout and check whether an automated judge got it right). Portable across
projects; see the project's own `docs/`/`specs/` for a repo-specific instantiation of this
checklist against a concrete reader.

Grounded in: [Inspect AI's log viewer](https://inspect.aisi.org.uk) (score-filterable sample
table, per-sample Messages/Scoring/Metadata tabs), [Docent](https://transluce.org/introducing-docent)
(Transluce's claim that the *interface* — not the model — bottlenecks human exploration of agent
transcripts; summarization, search, clustering, intervention), and an internal reader
(`nla_monitor/analysis/`) built for a multi-surface monitorability study.

## Information architecture

The three things a reader could be organized around are distinct, and worth being deliberate
about which is primary:

- **Verdict audit** — per-sample deep-read: open one rollout, see transcript + verdict + ground
  truth, decide if the judge was right.
- **Triage** — overview-table-first: scan many samples to find the interesting ones
  (disagreements, borderline cases, flips) *before* opening any transcript. This is Docent's
  core lesson — surfacing which transcripts to read is where the hours go, not reading one well.
- **Comparison** — side-by-side: the same samples scored by multiple judges/surfaces/channels,
  organized around "which judge got it right, at a glance."

Most tools need all three, fused: a triage table (sortable, filterable, groupable) as the entry
point, which opens into a per-sample view that fuses audit + comparison (every judge/surface
stacked, correctness-coloured). Treating them as three separate, equally-weighted sections tends
to bloat the tool instead of composing it.

## Checklist

### Fidelity — full inputs and outputs
- [ ] Every judge/monitor call is inspectable end to end: the exact rendered input (with all
      formatting — not a paraphrase) and the exact raw output, side by side.
- [ ] The **prompt template** itself is visible somewhere, not just the filled-in material — you
      should be able to see what varies per-sample vs. what's fixed boilerplate.
- [ ] Reasoning is shown when the model provides it (raw CoT / `<think>` blocks). When raw
      reasoning is unavailable (closed models, redacted CoT), a clearly labelled **summary**
      stands in its place — the label must make raw vs. summarized unmistakable; never let a
      summary masquerade as the real trace.
- [ ] The full rollout composes for free: system/developer/user/assistant/tool messages, tool
      call arguments, tool results, and the roster of tools *offered* (not just tools used) are
      all part of the same conversation view — not a separate panel you have to reconcile.
- [ ] Every message role — system, developer, user, assistant, tool/tool-result, and any
      provider-specific role (e.g. a distinct "reasoning" block) — gets its own consistent colour
      (background tint, left border, or avatar chip), applied identically everywhere it appears.
      Legible at a glance without reading the role label; a single legend states the mapping once
      rather than repeating it per message.
- [ ] Turn boundaries are visually distinct from message boundaries — a rule, spacing gap, or
      background band separates one turn (a full assistant-side step, which may span several tool
      calls and tool results before the next user/environment input) from the next. "Turn" and
      "message" are not the same unit in agentic rollouts; a reader that only distinguishes
      messages loses the higher-level structure of how many turns the rollout took and where each
      one starts.
- [ ] Non-text content (images produced by tools, etc.) renders inline, not just a boolean flag.

### Judge/monitor introspection
- [ ] Raw response and parsed verdict shown together, so parsing errors and rationalizations are
      visible rather than silently discarded.
- [ ] Provenance on every derived value: is this persisted-verbatim or reconstructed, and by what
      method — shown at the point of display, not buried in a README.
- [ ] Sampling/generation hyperparameters used to produce the transcript (temperature, top_p,
      max_tokens, etc.) are visible per-sample or per-run, not just in a config file elsewhere.
- [ ] Tool-call environment facts are visible: retries needed, error rates, stop reason.

### Comparison across judges/monitors
- [ ] Two or more judges/surfaces on the same sample are visible together, not requiring you to
      flip between views to compare.
- [ ] Correctness against ground truth is instantly legible — colour and/or symbol coding (not
      just text), consistent across every judge/surface shown.
- [ ] Disagreement between judges is a first-class, filterable/sortable signal, not something you
      have to compute by eye.

### Triage and grouping
- [ ] A sortable/filterable overview table exists — by verdict, correctness, disagreement — as
      the entry point before diving into any one transcript.
- [ ] Similar samples are grouped or clusterable (by outcome pattern, by content similarity, by
      quadrant) so you review a batch of related cases together rather than one at a time in
      arbitrary order.
- [ ] Epoch / repeat-rollout handling: multiple samples of the same underlying problem are
      grouped, not scattered.
- [ ] Summary statistics are plotted against ground truth when ground truth exists (confusion
      counts, agreement rates, CIs) — not left as raw counts the reader has to interpret.

### Navigation and ergonomics
- [ ] Long transcripts stay readable: collapsible sections by default (turns, tool params, raw
      judge output), with expand-all / collapse-all.
- [ ] In-content search across transcripts, not just search over sample keys.
- [ ] Deep-linkable/permalinkable samples for citing a specific rollout elsewhere.
- [ ] Scales past the small-n case the tool was first built for (pagination or virtualization) —
      a static reader that inlines every sample into one page breaks silently at scale.

### Annotation and ad hoc analysis
- [ ] Samples can be annotated/labelled by a human reviewer, and that label persists and is
      visible on return visits (not re-derived or lost on rebuild).
- [ ] An ad hoc query can be run across all samples on demand — "flag every rollout where X" —
      via a cheap LLM call per sample, and the result becomes a new filterable column rather than
      a one-off report. (Reported precedent: Apollo Research's internal "Revealer" tool
      reportedly parallelizes LLM-judge scoring across transcripts on the fly, using a cheap
      model such as Gemini 2.5 Flash for cost — unverified by me beyond the user's own report;
      treat as a design pattern to consider, not a citable fact.)
- [ ] Docent-style clustering of ad hoc query hits, so "which of these 40 flagged rollouts are
      actually the same failure mode" doesn't require manual re-reading of all 40.

### Framing
- [ ] The guiding research question(s) the tool is meant to answer are stated somewhere in the
      tool itself (header, sidebar) — not only in an external doc, so a reader opening the
      artifact cold knows what it's for.
- [ ] A narrative-level summary (not just a stats table) exists per run: what happened, what
      surprised, what's still open — see the parent CLAUDE.md's "Auditability" convention for
      the `summary.md` pattern this generalizes from.

## Notably absent from a naively-built reader

These are easy to skip because nothing forces you to notice the gap until someone hits it:

1. Judge's *full prompt template* — usually you show the filled material and forget the template
   is itself worth inspecting.
2. Ad hoc/on-demand LLM-judge queries over the corpus — most readers are built to display
   pre-computed verdicts, not to run new ones interactively.
3. Clustering/grouping of similar samples — triage tables usually sort/filter on existing columns
   but don't group by similarity.
4. Persistent human annotation — read-only readers have no write path for a reviewer's own label.
5. Scale beyond the first run's sample count — collapsibility and pagination are easy to defer
   until the reader silently produces a 100MB single-page HTML file.
