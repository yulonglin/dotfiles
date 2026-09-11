---
name: write-prose
description: Use when drafting or revising human-facing prose — artifacts, reports, specs, skills, rules and PR descriptions. Delegate the draft to the designated writer.
---

# Delegate the draft, not the polish

For in-scope prose, commission the writing instead of doing it yourself. The owner's standing judgement is that Opus 5 and Fable 5/5.1 write unclear prose; do not reopen that decision. Send source material before drafting so the writer chooses the structure. Polishing your draft preserves the structure this rule is meant to replace.

## In scope

- Artifacts, reports and specs
- Skill and rule text
- PR bodies and descriptions

## Out of scope

- Chat replies
- Commit messages
- Code comments
- Anything under about 150 words

## Seats, in order

1. `sol(high)` — GPT-5.6 Sol: default writer.
2. `astra(high)` — GPT-6 Astra: second writer; preferred reviewer and restructurer.
3. `kimi` — Kimi K3: cross-family fallback.

On a quota or cooldown failure, move to the next available seat; the failure is not a finding. Sol and Astra share Codex OAuth credentials, so a quota failure can block both. If the error names `usage_limit_reached ... via provider codex`, use Kimi, which runs on OpenRouter.

## Brief requirements

- Supply the findings, constraints, decisions and numbers. Raw material is fine; the brief must stand alone.
- Name the audience and what they will do with the text.
- Include reviewer comments verbatim for revisions.
- Include the applicable conventions from `~/.claude/checklists/writing.md`: one line per paragraph; headings assert a point in 4–7 words; results belong in figures; sourced claims link to sources; no checkbox syntax outside working todo lists.
- Set a length target.
- Require: "Return only the markdown, no preamble, no outer code fence. Do not write any file."

## Verify before writing the file

- Read the returned text. Check for invented claims, numbers that differ from their sources and omitted scope. You remain responsible for accuracy.
- Write the verified text to the file.
- Show the diff.
- Tell the user which exact model produced the text.
