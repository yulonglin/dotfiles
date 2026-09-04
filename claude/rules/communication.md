# Communication

## Writing

One paragraph is ONE line in `.md` files — never a hard newline inside a paragraph. Blank lines separate paragraphs; readers soft-wrap. This covers prose, bullet bodies and table cells.

**Todos and separate points are bullet lists, one item per line, sub-points nested** — in notes, plans, schedules and replies alike. Several items packed into one line with commas, semicolons or "then" is a list you have not drawn yet; a todo is its own `- [ ]` line so it can be ticked on its own. Bear-specific mechanics: `bear`.

Every header asserts a point, not a topic — in specs, plans, reports, READMEs, slide titles and headings alike; setup, methods and appendix sections take a plain descriptive name instead. State it plainly, with concrete referents, not a metaphor the body must decode — roughly four to seven words, qualifier below. Artifact-title version: `artifact-writing`.

**Results belong in figures, not in paragraphs.** A passage carrying three or more numbers with intervals is a figure you have not drawn yet. This holds for papers, reports, artifacts, specs and slides alike: a reader compares positions on an axis far faster than they parse bracketed intervals in prose, and a comparison across conditions is nearly unreadable as sentences. Keep a number inline only when it is the single headline value, or the one figure a reader must be able to quote. Every comparison plot shows its chance line and its null. Tooling and style: `house-plots` for papers, `dataviz` for artifact pages.

**Every sourced figure, quote or claim links to its source** — IRS page, Gmail thread (`https://mail.google.com/mail/u/0/#all/<threadId>`), Slack permalink, Bear note — in notes, artifacts and replies alike; a computed number links to its inputs. Links never end with a full stop — a trailing period gets copied into the URL. No checkbox checklists in specs or docs; `[ ]` belongs only in working todo lists.

**Stale items never sit there looking current.** When a plan step, draft, todo, document row or decision is superseded, dropped or cancelled, strike it through, rewrite it or delete it — whichever leaves the least clutter — and, where the reason matters, add a short trailing note saying why and what replaced it: "~~Send the Anti Entropy request~~ dropped 3 Sep 2026: the signed variation covers the period". Completed items are ticked, not struck; struck means cancelled. In git-tracked files deletion is fine because history holds the old text; in Bear, which has no version history, rewrite or strike through rather than delete.

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
