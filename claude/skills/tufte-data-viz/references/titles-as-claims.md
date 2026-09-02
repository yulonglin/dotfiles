# Titles as Claims — Writing Findings, Not Labels

Skill rule 20: titles assert findings. Not "Revenue by Quarter" but "Revenue Surged 23% in Q3". This is where the chart stops being a passive display and starts being an argument. The chart's title is the most-read piece of text on the page and the place most charts under-deliver.

## The shift

| Label (what's there) | Claim (what it means) |
|----------------------|------------------------|
| "Revenue by Quarter, 2024" | "Revenue Surged 23% in Q3" |
| "Monthly Active Users" | "MAU Doubled After Launch" |
| "Model Performance Across Conditions" | "Persona Prompting Cut Accuracy by 18%" |
| "CO₂ Concentration, 1958–2024" | "CO₂ Has Risen Every Year Since Records Began" |

Left column describes axes. Right column states findings. The chart's reason for existing is the right column.

## Five syntactic moves that carry weight

### 1. Front-load the subject

"Revenue surged 23%" — *Revenue* in the topic position tells the reader the chart is about revenue before they read the verb. Compare: "There was a 23% surge in revenue" — buries the subject behind *there was*.

### 2. Use a finite, active verb

*Surged, doubled, cut, fell, outperformed* — verbs that assert change. Avoid copular *to be* and nominalizations: "was a decrease" → "fell"; "showed an improvement" → "improved".

### 3. Quantify in the title

"23%" in the title front-loads the magnitude. The reader gets the answer in the heading and consults the chart for evidence. Without the number, the title is a tease.

### 4. Parallelism for comparison

When the chart compares two things, mirror the syntax: "Honest models refuse; deceptive models comply." Parallel verbs (*refuse*, *comply*) and matched subjects highlight the contrast.

### 5. Subtitle carries scope and units

Title makes the claim; subtitle states the conditions:

- Title: "Reasoning Models Outperform Base Models on AIME"
- Subtitle: "Pass@1 accuracy, AIME 2024, n=30 problems, 95% CI"

Don't pack the title with caveats — it weakens the claim. Caveats live in the subtitle.

## Anti-patterns

- **"Analysis of X"** — the chart *is* an analysis; saying so wastes the title.
- **"Figure 3:" prefixes** in standalone charts (slides, blog posts) — no figure number; the title carries the load.
- **Questions as titles** ("What Happened to Revenue?") — withholds the answer. The chart has the answer; the title should too.
- **Hedged verbs** ("Revenue May Have Increased") — if the data shows it, state it; if it doesn't, the chart isn't ready.

## When to use a neutral label instead

Two cases:

1. **Lookup tools** — reference plots in appendices, regulatory filings, monitoring dashboards. The reader already has the question; a label is enough.
2. **No single finding** — a scatter whose message is "no relationship" can be titled "X vs. Y, n=240" — but consider whether the chart needs to exist (skill rule 22).

In papers, decks, and posts, a chart earns its space by *making a point*. The title is where that point goes.
