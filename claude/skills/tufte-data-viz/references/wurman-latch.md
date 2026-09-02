# LATCH — Ordering Information

When you have N items in a table, legend, faceted grid, or small-multiple layout — the order is not arbitrary. There are five (and only five) ways to order anything: **L A T C H**.

## The five

| Letter | Method | Best for | Example |
|--------|--------|----------|---------|
| **L** | Location | Geographic, spatial, anatomical | Sales by country |
| **A** | Alphabet | Lookup tables when reader knows the name | Glossary, directory |
| **T** | Time | Sequential or chronological | Timeline, transaction log |
| **C** | Category | Discrete groups without intrinsic order | Product type, department |
| **H** | Hierarchy | Ranked by magnitude | Top 10 by revenue, sorted bar chart |

## Picking among them

Most data admits multiple orderings. Choose by **what the reader needs to find**:

- "What is X?" → Alphabet (if reader knows the name)
- "Which is biggest/smallest?" → Hierarchy
- "How did it change?" → Time
- "Where does it happen?" → Location
- "What kinds are there?" → Category

The skill's rule 6 — "horizontal bar chart sorted by value descending" — is LATCH-by-Hierarchy. It's right because the dominant question for a bar chart is *which is biggest*. Alphabetical sort forces the reader to scan all bars to find the leader.

## Common misuses

- **Alphabetical when the reader doesn't know the names.** A chart of US states alphabetized is hostile to "which is largest" — scan all 50. Sort by value.
- **Category order when comparison is the task.** Default Excel/ggplot ordering is often Category (input order, factor levels). Override to Hierarchy.
- **Multiple orderings competing.** A grid faceted by region (Location) with bars by year (Time) and color by product (Category) asks the reader to track three orderings. The fix isn't "pick one" — it's *be deliberate about what each axis encodes*.

## Application to small multiples

Small-multiple grids inherit LATCH for their layout — the panel order is itself a free encoding channel:

- Countries → **Location** (geographic arrangement, even if approximate)
- Months → **Time** (left-to-right, top-to-bottom)
- Customers → **Hierarchy** (largest first, reading order)
- Unrelated metrics → **Category** (group similar)

A grid in random order wastes the channel.

## Why this matters

Tufte covers what to put in the chart. Bertin covers which visual variable to use. LATCH covers **what order to put things in** — a question the others mostly sidestep. For tables, legends, and faceted grids, it's the operational guide.
