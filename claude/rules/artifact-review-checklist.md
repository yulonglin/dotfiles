# Artifact Review Checklist

Yulong's standard for every research artifact (2026-08-27). Build against it before publishing; it is what he checks first.

## Presentation

- **Numbers in prose can be a table; numbers in a table can be a plot.** Escalate to the richest form the data supports (house style: pastelplot/anthroplot, embedded as data URIs).
- Mermaid diagrams for mechanisms and pipelines.
- Commenting layer (see `artifact-first-replies.md`): save / delete / update a comment; copy all comments; highlights are stable — no flicker while selecting text.

## Clarity

- **Every heading is a claim (hedged appropriately) or a question.** Reading the headings alone states what the page found; the sections elaborate or provide evidence.
- **Research questions, one sentence each per section, listed at the start of the page.**
- Column names and axis labels carry hover/click definitions.
- **P0/P1/P2… are reserved for priorities.** Hypotheses and predictions are H1/H2…; requirements R1/R2…; never P-numbers.
- Claude's habitual jargon is defined where it appears: what an **arm** is and which arms exist; what a **smoke test** is, what it exercises, what it does and does not show.
- A **Terminology** and an **FAQ** section at the bottom.
- Write for a new colleague: context first, no buzzwords, no corporate phrasing, no fluffy transitions.

## Visibility and transparency — per set of experiments

- The research question it answers.
- Models, datasets, hyperparameters: what is held constant, what is varied.
- Prompts and prompt templates **in full**, verbatim, collapsible.
- **A full example task/transcript, ideally one positive and one negative**, verbatim, collapsible, roles colour-coded with emoji + label per model (agent model, monitor model, judge).
- Agent and monitor affordances (tools, what each can see).
- Environment components and how the environment state changes.

## Rigour

- Metric: what is the ground truth (pre-labelled? LLM judge/scorer?); for classification, which is the positive and which the negative class; the data distribution / skew; known issues with the data.
- Model inputs and outputs verbatim in a collapsible block, for every model in the loop (agent, monitor, judge, …).
- Every estimate with its interval and what the interval covers; every rate beside its null (see `research-integrity.md`).
