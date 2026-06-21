# Markdown Authoring Style

Rules for how Claude writes `.md` files (CLAUDE.md, rules, docs, plans, READMEs).

## No mid-sentence line breaks

Never insert a hard newline in the middle of a sentence or paragraph.
Each sentence or continuous thought goes on its own line — editors and viewers soft-wrap.
Long lines are fine.
This applies to prose, bullet-point bodies, and table cells.

❌ Wrong — wrapping mid-sentence:
```
The hook runs on every permission request and checks whether
the tool call is safe to auto-approve.
```

✅ Right — one thought per line:
```
The hook runs on every permission request and checks whether the tool call is safe to auto-approve.
```

## Prioritise clarity and rigour/honesty over volume

Write what is true and verifiable; keep it short.

- **State uncertainty** — "~80% confident", "speculative", "unverified" when relevant. Never imply more certainty than you have.
- **Report what didn't work** — failed approaches and null results belong in the record, not the bin.
- **One claim per sentence** — avoid sentences that pack multiple facts so each can be evaluated independently.
- **No padding** — don't restate what the section heading already says; don't add caveats that don't change the reader's decision.
