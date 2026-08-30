# Checklists

Five files that say what good looks like, carved by activity. Yulong owns and edits these; everything else points at them. They fold his own meta-prompts directly — there is no separate "source" layer any more: **these files are the source**, and the verbatim originals live in Bear (`#prompt/meta`) and git history.

| File | Activity | The question it answers |
|---|---|---|
| `writing.md` | clear writing — sentences and paragraphs | Will the reader finish holding the idea I meant? |
| `presentation.md` | research presentation — docs, slides, artifact pages | Can a busy reviewer get the findings in minutes? |
| `results-analysis.md` | analysing a finished run — evidence, review, annotation | Is the claim supported, and can a reader check it? |
| `research.md` | brainstorming and experiment design | Is this worth running, and could it come out the other way? |
| `experiments.md` | running experiments | Will this run finish, and will I trust it when it does? |

`results-analysis/` holds domain subskills — what the generic standard cannot say about a specific research area: `monitoring.md` (usable verbatim as an analysis prompt), `jlens.md`, `sandbagging.md`.

They are checklists, not essays. Each item is checkable by looking at a draft: a reader or a model can say yes or no. An item nobody can check is an aspiration and belongs in a different file.

## Why five files and not thirty skills

Skills multiply. Five of them ended up saying overlapping things about clarity, three about artifacts, and nine about running experiments — which is unmaintainable, and worse, means edits land in one copy and not the others. The content now lives here once. A skill's job is to *route*: a thin description that fires at the right moment and points at the section it needs, so the checklist is loaded on demand rather than restated in every file that touches it.

That also fixes the loading cost. A skill's description sits in context every session; its body loads on invoke; a file it points at loads only when reached for. Content here is paid for only when used.

## How to edit these

Add the rule where you would look for it, not where it was learned. Say what a violation costs the reader — a rule with a stated cost survives argument; a rule without one gets ignored the first time it is inconvenient. Prefer a test over an adjective: "the first sentence of each paragraph, read alone, gives the argument" beats "be well structured".

Where a rule is borrowed, cite it with a link, and mark whether the source was read directly or through a summary. Where two sources disagree, keep both and say who disagrees — averaging them produces advice that is true of nothing.

Delete freely. A checklist nobody has failed in a year is not protecting anything.
