# Tufte's Principles — The Why Behind the Rules

The skill's universal rules (1–14) are operational. This is the underlying philosophy. Read when a rule feels wrong for a specific chart and you need to reason about what's actually at stake.

## Data-ink ratio

`data-ink ÷ total ink`. Maximize it by erasing non-data-ink and redundant data-ink.

**Operational test:** if you can remove an element and lose no information, remove it. Borders, ticks beyond the data range, redundant labels, decorative fills — all candidates.

**When to relax:** lookup tables and instrument-style dashboards where reading precision beats minimalism. Light gridlines earn their ink when the chart's job is "tell me the exact value."

## Chartjunk

Useless, non-informative, or information-obscuring elements. Three flavors:

- **Moiré vibrations** — optical noise from heavy hatching or fine repeating patterns
- **Grids** — heavy frames that overwhelm the data
- **Ducks** — when the design becomes the content (3D pies, themed shapes, decorative chart frames)

## Small multiples

A series of small charts, identical structure, varying one parameter. Beats one cluttered chart with N overlapping series — comparison happens by eye-saccade across panels, not by tracing one line among many.

**Hard requirement:** shared scale across panels. Different scales = lying about relative magnitude.

**Why it works:** answers "Compared to what?" — the question every quantitative chart must answer.

## Range-frame axes

Axis lines span only `[min(data), max(data)]`, not from arbitrary 0 to arbitrary max. The axis itself becomes data-ink — its endpoints carry information.

**When not to use:** when 0 is meaningful (counts, proportions, bar charts) and the reader needs to see the baseline.

## Sparklines

Word-sized, intense, simple, word-like. Embedded inline in text or table cells. Show shape and recent values; precision is secondary.

**Anti-pattern:** sparklines with axes, gridlines, or larger than surrounding text — they lose their inline-text affordance and become tiny line charts.

## Lie factor

`effect size shown ÷ effect size in data`. Honest charts have lie factor ≈ 1.

The classic violation: showing a 53% increase as a 783% increase via misleading area encoding or truncated baselines. Whenever an encoding distorts the proportion the data represents, lie factor breaks.

**Corollary:** bar charts conventionally start at zero, because bar length encodes proportion — a non-zero baseline distorts magnitude visually. (This is the practitioner consensus; the underlying principle is lie factor.) Lines and dots encode position, not length — they're exempt, and forced-zero baselines on time series throw away resolution.

## What Tufte doesn't address (and the skill extends)

- **Screens.** Hover, tap, responsive, prefers-reduced-motion → skill rules 15–19.
- **Accessibility.** WCAG contrast, dual encoding, keyboard nav → skill rule 16.
- **Title authoring.** "Titles assert findings" → skill rule 20 and `titles-as-claims.md`.

## When to deviate from a rule

Tufte's rules optimize for one set of priorities: data integrity, reader comprehension, ink economy. They are not universal. Deviate when:

- The chart is a lookup tool — gridlines earn their ink (financial dashboards, scientific instruments).
- The audience reads conventions, not principles — regulatory filings, executive templates, journal house style.
- Following the rule would mislead — omitting zero on a bar chart violates lie factor more severely than a bit of chartjunk would.

The rules exist so deviations are conscious, not accidental.
