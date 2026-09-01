# Checklists

Five activity checklists that say what good looks like, plus the domain subskills under `results-analysis/` that say it for one research area. Yulong owns and edits these; everything else points at them. They fold his own meta-prompts directly — there is no separate "source" layer any more: **these files are the source**, and the verbatim originals live in Bear (`#prompt/meta`) and git history.

| File | Activity | The question it answers |
|---|---|---|
| `writing.md` | clear writing — sentences and paragraphs | Will the reader finish holding the idea I meant? |
| `presentation.md` | research presentation — docs, slides, artifact pages | Can a busy reviewer get the findings in minutes? |
| `results-analysis.md` | analysing a finished run — evidence, review, annotation | Is the claim supported, and can a reader check it? |
| `research.md` | brainstorming and experiment design | Is this worth running, and could it come out the other way? |
| `experiments.md` | running experiments | Will this run finish, and will I trust it when it does? |

`results-analysis/` holds domain subskills — what the generic standard cannot say about a specific research area: `monitoring.md` (usable verbatim as an analysis prompt), `jlens.md`, `sandbagging.md`.

`claude/rules/research-core.md` is the always-loaded companion, and it owns the red lines rather than the craft: the reviewer test, no circular reasoning, separation of concerns, and report what happened. The checklists carry everything else, so a standard you cannot find in that file is delegated here, not missing.

They are checklists, not essays: a reader or a model can say yes or no to an item. What an item is checked *against* differs by file, and the difference matters — an un-checkable item mixed in with checkable ones gets rubber-stamped along with them.

- `writing.md`, `presentation.md` and `results-analysis.md` are checked against a **draft**.
- `research.md` is checked against the **design artifacts**: the threat-model paragraph and who it says controls the prompt, the manifest's pre-run prediction and planned `n`, the named alternative explanations and the control that separates them. Its timeboxes ("thirty minutes, thirty ideas") are marked in place as advice, because nobody can check them off a document.
- `experiments.md` is mostly run-time behaviour, so it is checked after the fact against the **run log, the manifest and the output directory** — the spend estimate, the pilot, the hashes.

An item nothing can be checked against is an aspiration and belongs in a different file.

## Why five files and not thirty skills

Skills multiply. Five of them ended up saying overlapping things about clarity, three about artifacts, and nine about running experiments — which is unmaintainable, and worse, means edits land in one copy and not the others. The content now lives here once. A skill's job is to *route*: a thin description that fires at the right moment and points at the section it needs, so the checklist is loaded on demand rather than restated in every file that touches it.

That also fixes the loading cost. A skill's description sits in context every session; its body loads on invoke; a file it points at loads only when reached for. Content here is paid for only when used.

## How to edit these

Every writing, presentation or results comment Yulong gives in a session is distilled into an item in the matching checklist in that same session — merged into an existing item when it names the same class.

Add the rule where you would look for it, not where it was learned. Say what a violation costs the reader — a rule with a stated cost survives argument; a rule without one gets ignored the first time it is inconvenient. Prefer a test over an adjective: "the first sentence of each paragraph, read alone, gives the argument" beats "be well structured".

Where a rule is borrowed, cite it with a link, and mark whether the source was read directly or through a summary. Where two sources disagree, keep both and say who disagrees — averaging them produces advice that is true of nothing.

Delete freely. A checklist nobody has failed in a year is not protecting anything.
