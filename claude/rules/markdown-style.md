# Markdown Authoring Style

Rules for how Claude writes `.md` files (CLAUDE.md, rules, docs, plans, READMEs).

## No hard line breaks within paragraphs

A paragraph is one line. Never insert a hard newline inside a paragraph — not mid-sentence, and not between sentences. Blank lines separate paragraphs; the reading software soft-wraps long lines, so long lines are fine. This applies to prose, bullet-point bodies, and table cells.

❌ Wrong — hard-wrapped mid-sentence:
```
The hook runs on every permission request and checks whether
the tool call is safe to auto-approve.
```

❌ Also wrong — sentence-per-line within one paragraph:
```
The hook runs on every permission request.
It checks whether the tool call is safe to auto-approve.
```

✅ Right — the whole paragraph on one line:
```
The hook runs on every permission request. It checks whether the tool call is safe to auto-approve.
```

## Rich markdown highlighting (Bear syntax)

Yulong prefers **Bear markdown**. Bear's syntax isn't fully documented (its FAQ omits the colour encoding below), so treat Yulong's copied-from-Bear examples as the source of truth, not the FAQ.

- **Highlight:** `==text==` — default highlight colour.
- **Per-colour highlight (real Bear syntax):** Bear encodes a coloured highlight as a coloured-dot emoji at the **start of the highlighted span** — `==🔴text==`. This is literally what Bear writes to markdown when you apply a colour (Yulong copied it directly from Bear), which is why it round-trips. 🔴 is confirmed = red ("flag this / verify before shipping"); other highlight colours follow the same pattern with their matching coloured dot. Example Yulong gave:
  ```
  ==🔴Could the work be net-negative? … not a green light.==
  ```
- **Other Bear marks:** strikethrough `~~text~~`, underline `~text~`.

Don't use `==` / `~text~` in files meant to render as plain GitHub markdown (READMEs, CLAUDE.md, rules) — they show as literal characters there.

## Links never end with a full stop

When a link (bare URL or `[text](url)`) ends a sentence, drop the trailing period — end the sentence without one.
This avoids copy-paste errors where the period gets included as part of the URL.

❌ Wrong: `See https://example.com/docs.`
✅ Right: `See https://example.com/docs`

## Prioritise clarity and rigour/honesty over volume

Write what is true and verifiable; keep it short.

- **State uncertainty** — "~80% confident", "speculative", "unverified" when relevant. Never imply more certainty than you have.
- **Report what didn't work** — failed approaches and null results belong in the record, not the bin.
- **One claim per sentence** — avoid sentences that pack multiple facts so each can be evaluated independently.
- **No padding** — don't restate what the section heading already says; don't add caveats that don't change the reader's decision.
