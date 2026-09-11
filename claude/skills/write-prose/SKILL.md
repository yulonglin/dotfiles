---
name: write-prose
description: Use when drafting or revising human-facing prose — artifacts, reports, specs, skills, rules and PR descriptions. Select the writer from the router config.
---

# Commission prose before drafting it

Use this workflow for the document types above. Keep these inline:

- Chat replies
- Commit messages
- Code comments
- Text under about 150 words

## Select writers from one source

Read `config/model-router.toml` in the dotfiles repo. Select an eligible writer by `writer-priority` and follow the fallback and quota guidance there. Use the selected model's generated agent in `claude/agents/`; never hand-write a foreign-model agent. If this session already runs the selected writer, write directly.

## Brief the writer with sources

Send source material before drafting so the writer can choose the structure. Include:

- Findings, decisions, constraints and source paths or links.
- The audience, intended action and length target.
- Reviewer comments verbatim when revising.
- `~/.claude/CLAUDE.md` and `~/.claude/checklists/writing.md` for the current standards; do not restate them here.
- The output contract: return only the document text, without a preamble or outer code fence; do not write files.

## Verify the text before delivery

- Check claims and numbers against the sources.
- Confirm the requested scope.
- Return substantive corrections to the writer.
- Save the verified text and inspect the diff.
- Name the exact model that wrote it.
