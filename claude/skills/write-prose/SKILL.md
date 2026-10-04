---
name: write-prose
description: Use when drafting or revising human-facing prose — artifacts, reports, specs, paper sections, skills, rules and PR descriptions. Select the writer from the router config. Also when block_claude_authored_artifact.sh refuses a publish.
---

# Commission prose before drafting it

Use this workflow for the document types above. Opus 4.8, Opus 5 and Fable never draft them (Yulong, 2026-09-08); Opus 4.6 is allowed but is not a listed writer. Keep these inline:

- Chat replies
- Commit messages
- Code comments
- Text under about 150 words
- Applying Yulong's exported comments and suggested edits verbatim; a comment asking for a new or rewritten paragraph goes back to the writer

## Select writers from one source

Read `config/model-router.toml` in the dotfiles repo. Select an eligible writer by `writer-priority` and follow the fallback and quota guidance there. Use the selected model's generated agent in `claude/agents/`; never hand-write a foreign-model agent. If this session already runs the selected writer, write directly.

## Brief the writer with sources

Send source material before drafting so the writer can choose the structure. Include:

- Findings, decisions, constraints and source paths or links, as a skeleton rather than a draft: headers that assert the finding, each number with its interval, `n`, null and source, each figure by path. If you catch yourself writing a paragraph, that paragraph is the writer's job.
- The audience, intended action and length target.
- Reviewer comments verbatim when revising.
- `~/.claude/CLAUDE.md` and `~/.claude/checklists/writing.md` for the current standards; do not restate them here.
- The output contract: return only the document text, without a preamble or outer code fence; do not write files.

## Verify the text before delivery

- Check claims and numbers against the sources.
- Confirm the requested scope.
- Return substantive corrections to the writer.
- Save the verified text and inspect the diff.
- Name the exact model that wrote it. For an artifact, set `author_model` in its `meta.yml` to that model's id (`gpt-5.6-sol`, `kimi-k3`, ...); `claude/hooks/block_claude_authored_artifact.sh` refuses a publish whose `meta.yml` lacks the field or names a banned model. `author_model: generated` is reserved for a page a script emits from structured data with no drafted prose, such as the hosted index. The field is the record of the dispatch, never a way past the hook.
