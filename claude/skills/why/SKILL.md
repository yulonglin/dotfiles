---
name: why
description: Find out why code, a config line, a rule, a hook or an experiment choice is the way it is — search every evidence source in parallel (git and PRs, the Claude session transcripts that wrote it, specs and artifacts, Slack, Granola, Gmail, docs, trackers) and return a cited answer that keeps what was stated apart from what is inferred and what nobody recorded. Use on "why does X work this way", "why did we pick Y", "where did this rule/threshold come from", "is this still needed", before deleting or rewriting something whose purpose is unclear, and for postmortems. For what code does now, read it; for what a change breaks, use `blast-radius`.
---

# Why

Adapted from pstack's `why` skill in [pstack-claude](https://github.com/michael-denyer/pstack-claude) (MIT), the Claude Code port of Lauren Tan's pstack. `references/epistemics.md` is kept close to upstream; the evidence sources are replaced with this setup's.

Code shows what it does, not why it exists. The why lives in commits, PRs, session transcripts, specs, chats and meetings — all incomplete, and some of it written by an agent that guessed. The output's value is its honesty, not its authority: the user acts on it, so a confident guess is worse than a named gap.

## 1. Pin the target and the question

The target is a file range, a symbol, a config key, a rule sentence, a hook, a threshold or a design choice. The question is a rationale, a tradeoff, an edge case, an external constraint, or "is this dead". If the referent is vague, take the best guess from context (open files, recent edits, what was just discussed), state it in one line, and proceed.

A hypothesis inside the question ("I assume it's for performance?") is one candidate to test, not a conclusion to confirm.

## 2. Build the code anchor inline

Before spawning anything, collect: paths with line ranges; key symbols; recent commits (`git log --follow --oneline -20 -- <file>`); last-touch commits (`git blame -L <start>,<end> <file>`); commits that added or removed the exact text (`git log -S '<string>'`); PR numbers from merge subjects; then each substantive PR's summary (`gh pr view <n> --json title,body,author,createdAt,mergedAt,labels`). Review threads stay with the source-control investigator, since a long one would flood this context. The anchor, plus the commit dates, goes to every investigator and the synthesizer — the dates are what lets the transcript and chat investigators search the right window.

## 3. Spawn one investigator per available source, all in one message

`references/sources.md` lists the sources, which tools reach each one, and how to search them. Spawn one investigator per source that is reachable in this session — never one agent across several sources — each with `references/investigator-prompt.md` filled in, its section of `sources.md`, and the anchor. Add the defensive-code queries in `sources.md` when the target is a guard, retry, timeout, limit, flag or hook that refuses something.

- **Always** spawn source control and session transcripts: for agent-written code, the transcript that wrote it is often the only record of why.
- **Skip** a source only with a written reason that goes into Sources Consulted: no tool reaches it ("Bear: MCP not connected"), or it is provably irrelevant (not merely probably). An unreachable source is a gap, not a choice.
- **Answer inline** only when the target is a single commit whose PR body already answers the question completely, and say so.
- Spread investigators across model families (`delegation.md`); MCP searches run inside the investigators with a page size of at most 10, after loading the connector skill (`gmail-connector`, `bear`).

## 4. Synthesize in another family

Spawn one synthesizer from a different model family than most investigators, with every investigator report (including empty ones and skip reasons), the anchor, the question, `references/epistemics.md` and `references/synthesizer-prompt.md`. It spot-checks citations and writes the answer in the template's structure.

## 5. Present

Relay the synthesizer's answer. Edit lightly for context; never strengthen its confidence language. Sources Consulted keeps one line per source, including the empty and the skipped.

If the question is a precursor to changing the target, end with a constraint set for the change: **Preserve** (what the evidence says must survive), **Change** (what is safe to alter), **Avoid** (what was tried and failed), **Risk** (what nobody recorded).

## Failure modes

- **Recency bias**: the latest commit is rarely the reason; the shape accreted. Trace back.
- **Echoed summaries**: an agent's paraphrase of a user instruction, copied into three notes, is one source, not three. Find the user's original words (`epistemics.md` § Claims about human decisions).
- **Code as its own evidence**: "the author chose X" from reading the code is an observation, not intent.
