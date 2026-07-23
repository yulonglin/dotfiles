# Fable Second Opinion

Fable 5 (`claude-fable-5`) is a distinct Claude model family from Sonnet/Opus. Use it via the `Agent` tool's `model: "fable"` parameter to get a genuinely independent second opinion — a different perspective from a different training lineage, not just another Sonnet/Opus call.

## When to Spawn a Fable Subagent

| Trigger | Action |
|---------|--------|
| **Stuck** — the same approach has failed 2+ times, or a hypothesis doesn't hold up under evidence | Spawn Fable with the failing approach + evidence gathered so far, before attempting a 4th fix |
| **Hard/high-ambiguity problem** — architecture decision, tricky algorithm, subtle bug, research design | Get Fable's input in parallel before committing to an approach |
| **Second opinion on a conclusion or plan** — high-stakes call where being wrong is costly | Spawn Fable alongside (or after) `advisor` |

## How

Fable has **no memory of the conversation** — unlike `advisor`, which auto-forwards the full transcript. Brief it like any fresh subagent: full context, what's been tried, what evidence exists, and the specific question.

```
Agent({
  description: "Second opinion from Fable on X",
  model: "fable",
  prompt: "<self-contained context: the problem, what's been tried, the evidence, the specific question>"
})
```

## Relationship to `advisor`

`advisor` (Opus-backed, per `advisorModel` in `claude/settings.json`) auto-forwards the full transcript and is the default check before substantive work or when declaring done (see `advisor` tool description). Fable is a separate model family for when a genuinely different perspective is wanted — adversarial verification, breaking a stuck loop, or corroborating a high-stakes call `advisor` already weighed in on.

## Escalation Order (Stuck Loop)

1. First failure → retry with an informed fix based on the error.
2. Second failure → step back, form an explicit hypothesis before trying again (see `rules/effortful-learning.md`).
3. Third failure, or the hypothesis still doesn't hold → spawn a Fable subagent before a fourth attempt.
