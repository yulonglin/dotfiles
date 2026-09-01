# Technical Writing Checklist

One common checklist for papers, slides, artifacts, and reports. **Every writing comment, edit, or piece of feedback Yulong gives gets distilled into an item here in the same session it lands** — dated, phrased as a checkable rule, merged into an existing item when it names the same class. Run the list before sending any technical prose, and again on any draft that fails review.

## Clarity — the reader must never have to decode

- Every header and section lead makes one point, stated plainly. If a reader asks "what's the point you're trying to make?", the section fails. (2026-09-01)
- Answer the reader's next question in place. A claim that provokes "why?" or "which ones?" carries the answer in the same sentence or the next. (2026-09-01)
- One claim per bullet; every number attributed to its metric, method, and setting. Never cram several numbers into one sentence. (2026-08)
- Enumerations go in bullets, numbered lists, or delimited strings — never dense paragraphs. Narrative logic goes in prose, not bullets. (2026-08)

## Terminology — only words the venue already uses

- Never coin a term when a standard one exists: "substrate" → dataset; "arm" → condition ("arm" is bandits-only at ML venues); "upstream" → name the actual source ("the benchmark's authors", "the original paper"). Test: would a NeurIPS reviewer who skipped Section 2 know the word? (2026-09-01)
- One name per method, used everywhere; access differences are stated as surfaces or inputs, not new method names (trusted monitor, not transcript/trace monitor). (2026-09-01)

## Claims — sized to the evidence, no drama

- Causal and strength verbs match the design: "associated with", "consistent with", "we observe" by default; plain strong claims only for tested mechanisms. Never dramatic framing ("confesses", "blabbers", "clear win", "earns its keep"). (2026-09-01)
- Summary claims judge a method against chance; a behaviour-free baseline diagnoses the dataset, not the method. Don't mix the two nulls in a headline. (2026-09-01)
- Don't dress a null up in numbers that carry no information: a failed attempt is "we could not get it to work", not take-rates with Wilson bounds. Report numbers where they discriminate, prose where they don't. (2026-09-01)

## Selection — the important thing, not the available thing

- Cut caveats that restate the standard setup; keep only limitations a reader would act on. A caveat repeated from the field's default design is noise. (2026-09-01)
- The details a reader actually needs (which datasets, which models, what failed and why) beat exhaustive hedging about minor conditions. If a section is mostly qualifications, invert it. (2026-09-01)

## Register — reads like a paper, not a story

- No narrative self-reference: "this half of the report", "five findings carry the report", "the most useful single view of our data". Conventional framing only. (2026-09-01)
- Bold only table cells, defined terms, headline numbers, and paragraph leads of ≤6 words. Never whole claim sentences. (2026-09-01)
- Standard section names: Discussion, Limitations and Future Work. No imperative or metaphorical headers. (2026-09-01)

## Mechanics

- No FIXME/TODO/placeholder text that renders into the output; author notes are `%` comments. Resolve every placeholder before shipping. (2026-09-01)
- No inline arXiv IDs; every citation verified against live metadata (title and full author list) before the entry is written. (2026-09-01)
- Artifacts are mobile-first (~390px, wrapped code, capped SVG width); slides follow 6×6. (2026-08)
