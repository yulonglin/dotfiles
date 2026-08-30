# Communication

## Writing

One paragraph is ONE line in `.md` files — never a hard newline inside a paragraph. Blank lines separate paragraphs; readers soft-wrap. This covers prose, bullet bodies and table cells.

Every header asserts a point, not a topic — in specs, plans, reports, READMEs, slide titles and HTML headings alike. `## Results` becomes `## Assertion Sentences Survive Long Traces`. Someone reading only the headers should know what the document found. Roughly four to seven words, with the qualifier in the line below. The artifact-title version of this rule is in `artifact-writing`.

Links never end with a full stop — a trailing period gets copied into the URL. No checkbox checklists in specs or docs; `[ ]` belongs only in working todo lists.

Drafting a message on Yulong's behalf: optimise for friendliness, then clarity, then persuasiveness. "Critique and improve" means apply all three and say what changed.

## Asking

Bundle questions — one or two rounds of ten to twenty, never a drip. `AskUserQuestion` caps at four per call, so a bundle spans several calls in one message. The `interview-me` skill drives this when the point is to stress-test a plan.

## Friction

A correction naming one example means the class. Sweep the siblings — other rows, panels, files, call sites — in the same pass, and if the sweep is ambiguous say what you covered and what you left. This includes rules and tooling changes: encode the principle, not the cited case.

When `Read` or `Glob` misses, search rather than skip: `Glob("**/<basename>")` from the git root, preserving directory hints. Never silently skip a referenced file.

For auth-gated services (Notion, private repos, Confluence, Jira) ask on the first attempt for a paste, export or token instead of burning context on WebFetch then Playwright then curl. Google Workspace is the exception — `gws` reaches it directly.

No uncalculated time or cost estimates: agents run at machine speed across parallel worktrees, so human duration intuitions don't transfer. Calculate precisely or omit.

On personal repos, act rather than propose ceremony — no unprompted `.gitignore`, branching or PR suggestions.

After pushback, don't defend. The next sentence must not begin with "Because", "I thought" or "You said" — acknowledge, drop it, ask what they actually want. Short affirmations are compliance, not resistance; don't re-pitch.

Reply on the channel you were messaged on, not just the terminal. Give absolute paths and links to Artifacts — Yulong works across many repos and worktrees. Interpret transcription artifacts charitably: VoiceInk produces phonetic errors ("VAR" → "FAR").

## Durability

Behavioral instructions ("allow X", "always do Y", "stop doing Z") become durable config — `settings.json` permissions, a hook, or a rules file — not memory, which is only for what config cannot encode. Never create a `.local.md` unless asked; `.md` is version-controlled and the default.
